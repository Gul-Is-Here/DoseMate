import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../core/utils/care_dates.dart';
import '../../firebase_options.dart';
import '../models/medicine.dart';
import '../repositories/care_repository.dart';

/// What one alarm is for; travels in the notification payload (strings
/// only), so the buttons work without the app's state.
class AlarmPayload {
  const AlarmPayload({
    required this.kind,
    required this.uid,
    required this.pid,
    required this.key,
    this.day,
    this.minutes,
    this.medicineIds = const [],
    this.visitId,
    this.sig = '',
    this.snoozed = false,
  });

  factory AlarmPayload.from(Map<String, String?> p) => AlarmPayload(
    kind: p['kind'] ?? '',
    uid: p['uid'] ?? '',
    pid: p['pid'] ?? '',
    key: p['key'] ?? '',
    day: CareDates.parseDay(p['day']),
    minutes: int.tryParse(p['minutes'] ?? ''),
    medicineIds: (p['meds'] ?? '')
        .split(',')
        .where((s) => s.isNotEmpty)
        .toList(),
    visitId: p['visit'],
    sig: p['sig'] ?? '',
    snoozed: p['snooze'] == '1',
  );

  static const dose = 'dose';
  static const visit = 'visit';

  final String kind;
  final String uid;
  final String pid;

  /// The occurrence's stable key; its notification id is derived from it.
  final String key;
  final DateTime? day;
  final int? minutes;
  final List<String> medicineIds;
  final String? visitId;

  /// Changes when the alarm's content changes, so it's rescheduled.
  final String sig;
  final bool snoozed;

  Map<String, String?> toMap() => {
    'kind': kind,
    'uid': uid,
    'pid': pid,
    'key': key,
    if (day != null) 'day': CareDates.dayKey(day!),
    if (minutes != null) 'minutes': '$minutes',
    if (medicineIds.isNotEmpty) 'meds': medicineIds.join(','),
    'visit': ?visitId,
    'sig': sig,
    if (snoozed) 'snooze': '1',
  };

  /// Dose log ids of this alarm's doses.
  List<String> get logIds => [
    if (day != null && minutes != null)
      for (final m in medicineIds) DoseLog.idFor(m, day!, minutes!),
  ];
}

/// Alarm notifications and their buttons. Static, because a button can
/// run in a background isolate with nothing else of the app set up.
abstract class AlarmActions {
  static const channel = 'dose_alarms';
  static const oldChannels = {'local_alarms'};
  static const snoozeFor = Duration(minutes: 10);

  /// Android repeats the alarm sound until the alarm is acted on; past
  /// this it's removed (server follow-ups and the Notifications screen
  /// still show the dose).
  static const ringFor = Duration(minutes: 3);

  static const taken = 'taken';
  static const skip = 'skip';
  static const snooze = 'snooze';
  static const dismiss = 'dismiss';

  /// FNV-1a of [key]; the same id on every run and device.
  static int idFor(String key) {
    var h = 0x811c9dc5;
    for (final c in key.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h & 0x7fffffff;
  }

  static int snoozeIdFor(String key) => idFor('snooze:$key');

  static NotificationContent content({
    required AlarmPayload payload,
    required String title,
    required String body,
  }) => NotificationContent(
    id: payload.snoozed ? snoozeIdFor(payload.key) : idFor(payload.key),
    channelKey: channel,
    title: title,
    body: body,
    category: NotificationCategory.Alarm,
    wakeUpScreen: true,
    // A prominent heads-up notification, not a full-screen activity (see
    // AlarmService).
    fullScreenIntent: false,
    autoDismissible: false,
    timeoutAfter: ringFor,
    payload: payload.toMap(),
  );

  static List<NotificationActionButton> buttons(AlarmPayload p) => [
    if (p.kind == AlarmPayload.dose) ...[
      NotificationActionButton(
        key: taken,
        label: 'Taken',
        actionType: ActionType.SilentBackgroundAction,
      ),
      NotificationActionButton(
        key: skip,
        label: 'Skip',
        actionType: ActionType.SilentBackgroundAction,
      ),
    ] else
      NotificationActionButton(
        key: dismiss,
        label: 'Dismiss',
        actionType: ActionType.DismissAction,
      ),
    NotificationActionButton(
      key: snooze,
      label: 'Snooze ${snoozeFor.inMinutes}m',
      actionType: ActionType.SilentBackgroundAction,
    ),
  ];

  /// Every button and tap of every app notification lands here.
  @pragma('vm:entry-point')
  static Future<void> handle(ReceivedAction action) async {
    final raw = action.payload;
    if (raw == null ||
        (action.channelKey != channel &&
            !oldChannels.contains(action.channelKey))) {
      return;
    }
    final p = AlarmPayload.from(raw);
    final plugin = AwesomeNotifications();
    // Any button stops the sound: the alarm itself goes away.
    if (action.id != null) await plugin.dismiss(action.id!);
    try {
      switch (action.buttonKeyPressed) {
        case taken:
          await _log(p, DoseStatus.taken);
        case skip:
          await _log(p, DoseStatus.skipped);
        case snooze:
          await _snooze(p, action);
        default:
        // Dismiss, or a tap that opens the app: nothing is logged.
      }
    } catch (e) {
      _report(plugin, p, action);
      if (kDebugMode) debugPrint('Alarm action error: ${e.runtimeType}');
    }
  }

  static Future<void> _snooze(AlarmPayload p, ReceivedAction a) async {
    final until = DateTime.now().add(snoozeFor);
    final next = AlarmPayload.from({...a.payload!, 'snooze': '1'});
    await AwesomeNotifications().createNotification(
      content: content(payload: next, title: a.title ?? '', body: a.body ?? ''),
      actionButtons: buttons(next),
      schedule: NotificationCalendar.fromDate(
        date: until,
        allowWhileIdle: true,
        preciseAlarm: await _exact(),
      ),
    );
    // Tell the server so its "not logged yet" follow-up waits too.
    if (p.kind == AlarmPayload.dose) {
      final db = await _firestore(p.uid);
      if (db == null) return;
      for (final id in p.logIds) {
        await db
            .doc('users/${p.uid}/profiles/${p.pid}/doseSnoozes/$id')
            .set({'until': Timestamp.fromDate(until)})
            .timeout(const Duration(seconds: 5), onTimeout: () {});
      }
    }
  }

  static Future<bool> _exact() async {
    try {
      final has = await AwesomeNotifications().checkPermissionList(
        channelKey: channel,
        permissions: const [NotificationPermission.PreciseAlarms],
      );
      return has.contains(NotificationPermission.PreciseAlarms);
    } catch (_) {
      return false;
    }
  }

  /// Logs the alarm's doses as the signed-in owner, through the same
  /// repository (revision rules, retry-safe stock) as the app. A dose
  /// already logged on any device is left as it is.
  static Future<void> _log(AlarmPayload p, DoseStatus status) async {
    final db = await _firestore(p.uid);
    final day = p.day, minutes = p.minutes;
    if (db == null || day == null || minutes == null) {
      throw StateError('not signed in');
    }
    final repo = CareRepository(db);
    final profile = db.doc('users/${p.uid}/profiles/${p.pid}');
    for (final id in p.medicineIds) {
      final med = await profile.collection('medicines').doc(id).get();
      if (!med.exists) continue;
      final o = DoseOccurrence(Medicine.fromMap(id, med.data()!), day, minutes);
      final log = await profile.collection('doseLogs').doc(o.logId).get();
      final current = log.data()?['status'];
      if (current == 'taken' || current == 'skipped') continue;
      await repo.logDose(
        p.uid,
        p.pid,
        o,
        status,
        action: DoseTap.at(
          DateTime.now(),
          previousRev: (log.data()?['rev'] as num?)?.toInt(),
        ),
      );
    }
    // A snooze of the same doses is no longer needed.
    await AwesomeNotifications().cancel(snoozeIdFor(p.key));
  }

  /// Firestore as [uid], starting Firebase in a background isolate.
  static Future<FirebaseFirestore?> _firestore(String uid) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    final auth = FirebaseAuth.instance;
    final user =
        auth.currentUser ??
        await auth.authStateChanges().first.timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        );
    // Signed out, or another account since the alarm was set.
    if (user == null || user.uid != uid) return null;
    return FirebaseFirestore.instance;
  }

  /// The button didn't go through: say so, quietly, so it isn't lost.
  static void _report(
    AwesomeNotifications plugin,
    AlarmPayload p,
    ReceivedAction a,
  ) {
    plugin
        .createNotification(
          content: NotificationContent(
            id: idFor('failed:${p.key}'),
            channelKey: 'server_alerts',
            title: 'Not saved: ${a.title ?? 'reminder'}',
            body: 'Open DoseMate to log this dose.',
            category: NotificationCategory.Reminder,
            payload: {'key': p.key},
          ),
        )
        .catchError((Object _) => false);
  }
}
