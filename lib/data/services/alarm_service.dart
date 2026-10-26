import 'dart:async';

import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../core/utils/care_dates.dart';
import '../models/medicine.dart';
import '../models/user_profile.dart';
import '../models/visit.dart';
import '../repositories/care_repository.dart';
import 'alarm_actions.dart';
import 'auth_service.dart';
import 'notification_service.dart';
import 'profile_service.dart';

/// One alarm the device should have scheduled.
class AlarmPlan {
  const AlarmPlan({
    required this.at,
    required this.payload,
    required this.title,
    required this.body,
  });

  final DateTime at;
  final AlarmPayload payload;
  final String title;
  final String body;

  int get id => AlarmActions.idFor(payload.key);
}

/// Keeps this device's local alarms in step with every profile the
/// signed-in account owns (not only the one on screen): each dose time and
/// each appointment reminder in the next [horizon] gets one alarm.
///
/// - Doses of one profile at the same minute share one alarm (one sound).
/// - A dose logged on any device, an edited, paused or deleted medicine,
///   and a moved or cancelled visit cancel or replace their alarm.
/// - Ids come from stable occurrence keys, so rescheduling never adds a
///   second alarm. Snoozes are separate alarms and leave these alone.
///
/// Profiles shared by other accounts get no alarms in this version.
class AlarmService extends GetxService {
  AlarmService(
    this._auth,
    this._profiles,
    this._repository,
    this._notify, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AuthService _auth;
  final ProfileService _profiles;
  final CareRepository _repository;
  final NotificationService _notify;
  final DateTime Function() _clock;

  static const horizon = Duration(hours: 48);

  /// iOS keeps at most 64 pending notifications per app; this leaves room
  /// for snoozes.
  static const maxAlarms = 48;

  static const _visitOffsets = {
    '1 day before': Duration(days: 1),
    '2 hours before': Duration(hours: 2),
    '1 hour before': Duration(hours: 1),
    '30 mins before': Duration(minutes: 30),
  };

  final _medicines = <String, List<Medicine>>{};
  final _visits = <String, List<Visit>>{};
  final _logs = <String, Map<String, DoseLog>>{};
  final _subscriptions = <String, List<StreamSubscription<Object?>>>{};
  final _workers = <Worker>[];
  Timer? _debounce;
  Timer? _refresh;
  bool _running = false;
  bool _again = false;
  String? _uid;

  AlarmService init() {
    _workers.add(ever<List<UserProfile>>(_profiles.profiles, (_) => _follow()));
    _workers.add(ever(_auth.user, (_) => _follow()));
    _notify.onGranted.add(_reconcileNow);
    _auth.beforeSignOut.add(clearAll);
    // The horizon moves on; new days get their alarms.
    _refresh = Timer.periodic(const Duration(hours: 1), (_) => schedule());
    _follow();
    return this;
  }

  /// Subscribes to each owned profile's medicines, visits and logs.
  void _follow() {
    final uid = _auth.isSignedIn && !_auth.needsVerification
        ? _profiles.uid
        : null;
    if (uid != _uid) {
      _stopAll();
      _uid = uid;
    }
    if (uid == null) {
      // Signed out without [clearAll]: elsewhere, or the session ended
      // because the account was deleted on another device. Its pending
      // alarms and snoozes go too. (Profiles merely reloading keep them.)
      if (!_auth.isSignedIn) schedule();
      return;
    }
    final pids = {
      for (final p in _profiles.profiles)
        if (!p.isShared) p.id,
    };
    for (final pid in _subscriptions.keys.toList()) {
      if (!pids.contains(pid)) _stop(pid);
    }
    final today = CareDates.dateOnly(_clock());
    for (final pid in pids) {
      if (_subscriptions.containsKey(pid)) continue;
      _subscriptions[pid] = [
        _repository
            .watchMedicines(uid, pid)
            .listen((m) => _set(() => _medicines[pid] = m), onError: _onError),
        _repository
            .watchUpcomingVisits(uid, pid, today)
            .listen((v) => _set(() => _visits[pid] = v), onError: _onError),
        _repository
            .watchLogs(uid, pid, CareDates.addDays(today, -1))
            .listen(
              (l) => _set(() => _logs[pid] = {for (final x in l) x.id: x}),
              onError: _onError,
            ),
      ];
    }
    schedule();
  }

  void _set(void Function() update) {
    update();
    schedule();
  }

  void _onError(Object e) => _log('watch', e);

  void _stop(String pid) {
    for (final s in _subscriptions.remove(pid) ?? const []) {
      s.cancel();
    }
    _medicines.remove(pid);
    _visits.remove(pid);
    _logs.remove(pid);
  }

  void _stopAll() {
    for (final pid in _subscriptions.keys.toList()) {
      _stop(pid);
    }
  }

  /// Reconciles soon; bursts of updates (a snapshot per collection) run
  /// once.
  void schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), _reconcileNow);
  }

  /// The alarms that should exist now, soonest first.
  @visibleForTesting
  List<AlarmPlan> plan() {
    final uid = _uid;
    if (uid == null) return const [];
    final now = _clock();
    final until = now.add(horizon);
    final today = CareDates.dateOnly(now);
    final plans = <AlarmPlan>[];
    for (final p in _profiles.profiles.where((p) => !p.isShared)) {
      final pid = p.id;
      final logs = _logs[pid] ?? const {};
      // Doses: grouped per minute; logged doses drop out.
      final groups = <DateTime, List<DoseOccurrence>>{};
      for (var d = 0; d <= horizon.inDays; d++) {
        final day = CareDates.addDays(today, d);
        for (final m in _medicines[pid] ?? const <Medicine>[]) {
          for (final o in m.occurrencesOn(day)) {
            if (!o.at.isAfter(now) || o.at.isAfter(until)) continue;
            if (logs.containsKey(o.logId)) continue;
            (groups[o.at] ??= []).add(o);
          }
        }
      }
      for (final MapEntry(key: at, value: doses) in groups.entries) {
        doses.sort((a, b) => a.medicine.name.compareTo(b.medicine.name));
        final first = doses.first;
        final key =
            'alarm:dose:$pid:${CareDates.dayKey(first.day)}_${first.minutes}';
        final title = doses.length == 1
            ? 'Time for ${first.medicine.name}'
            : 'Time for ${doses.length} medicines';
        final body = [
          '${p.fullName} • ${CareDates.clockOf(at)}',
          for (final o in doses)
            [
              o.medicine.name,
              o.medicine.dosage,
            ].where((s) => s.isNotEmpty).join(' — '),
        ].join('\n');
        plans.add(
          AlarmPlan(
            at: at,
            title: title,
            body: body,
            payload: AlarmPayload(
              kind: AlarmPayload.dose,
              uid: uid,
              pid: pid,
              key: key,
              day: first.day,
              minutes: first.minutes,
              medicineIds: [for (final o in doses) o.medicine.id],
              sig: '$title|$body',
            ),
          ),
        );
      }
      // Appointment reminders the user chose for each visit.
      for (final v in _visits[pid] ?? const <Visit>[]) {
        if (v.status != VisitStatus.scheduled) continue;
        for (final r in v.reminders) {
          final offset = _visitOffsets[r];
          if (offset == null) continue;
          final at = v.startsAt.subtract(offset);
          if (!at.isAfter(now) || at.isAfter(until)) continue;
          final key =
              'alarm:visit:$pid:${v.id}:${offset.inMinutes}:'
              '${v.startsAt.millisecondsSinceEpoch}';
          final body = [
            '${p.fullName} • '
                '${CareDates.long(CareDates.dateOnly(v.startsAt))} at '
                '${CareDates.clockOf(v.startsAt)}',
            if (v.who.isNotEmpty) v.who,
            if (v.address.isNotEmpty) v.address,
          ].join('\n');
          plans.add(
            AlarmPlan(
              at: at,
              title: '${v.title} — $r',
              body: body,
              payload: AlarmPayload(
                kind: AlarmPayload.visit,
                uid: uid,
                pid: pid,
                key: key,
                visitId: v.id,
                sig: '${v.title}|$body',
              ),
            ),
          );
        }
      }
    }
    plans.sort((a, b) => a.at.compareTo(b.at));
    return plans.take(maxAlarms).toList();
  }

  Future<void> _reconcileNow() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        await _reconcile();
      } while (_again);
    } finally {
      _running = false;
    }
  }

  Future<void> _reconcile() async {
    if (!_notify.ready) return;
    final plugin = _notify.plugin;
    final granted = _notify.permission.value == NotifyPermission.granted;
    final wanted = granted ? plan() : const <AlarmPlan>[];
    final byId = {for (final p in wanted) p.id: p};
    try {
      // Only pending alarms: one that's ringing now is left to finish.
      final scheduled = await plugin.listScheduledNotifications();
      // Alarms set on an earlier alarm channel are replaced on this one.
      for (final n in scheduled) {
        final c = n.content;
        if (c?.id != null && AlarmActions.oldChannels.contains(c!.channelKey)) {
          await plugin.cancel(c.id!);
        }
      }
      final pending = scheduled
          .where((n) => n.content?.channelKey == AlarmActions.channel)
          .toList();
      final have = <int, String>{};
      for (final n in pending) {
        final c = n.content!;
        final payload = c.payload ?? const {};
        final id = c.id!;
        if (payload['snooze'] == '1') {
          // A snooze of doses since logged (or of another account) goes.
          final p = AlarmPayload.from(payload);
          if (!granted || p.uid != _uid || _allLogged(p)) {
            await plugin.cancel(id);
          }
          continue;
        }
        if (byId[id]?.payload.sig != payload['sig']) {
          await plugin.cancel(id);
        } else {
          have[id] = payload['sig'] ?? '';
        }
      }
      final exact = _notify.exactAlarms.value ?? false;
      for (final p in wanted) {
        if (have.containsKey(p.id)) continue;
        await plugin.createNotification(
          content: AlarmActions.content(
            payload: p.payload,
            title: p.title,
            body: p.body,
          ),
          actionButtons: AlarmActions.buttons(p.payload),
          schedule: NotificationCalendar.fromDate(
            date: p.at,
            allowWhileIdle: true,
            // Without exact-alarm access Android may deliver a few
            // minutes late (Settings › Notifications offers to allow it).
            preciseAlarm: exact,
          ),
        );
      }
      // An alarm still showing whose doses are now all logged (here or
      // elsewhere): stop it. One with a dose still unlogged keeps ringing.
      for (final key in loggedGroups()) {
        await plugin.dismiss(AlarmActions.idFor(key));
      }
    } catch (e) {
      // Not scheduled now; the next change or hourly refresh tries again.
      _log('schedule', e);
    }
  }

  /// Keys of today's dose alarms whose doses are all logged.
  @visibleForTesting
  Set<String> loggedGroups() {
    final today = CareDates.dateOnly(_clock());
    final keys = <String>{};
    for (final MapEntry(key: pid, value: logs) in _logs.entries) {
      final byMinute = <int, List<DoseOccurrence>>{};
      for (final m in _medicines[pid] ?? const <Medicine>[]) {
        for (final o in m.occurrencesOn(today)) {
          (byMinute[o.minutes] ??= []).add(o);
        }
      }
      for (final MapEntry(key: minutes, value: doses) in byMinute.entries) {
        if (doses.every((o) => logs.containsKey(o.logId))) {
          keys.add('alarm:dose:$pid:${CareDates.dayKey(today)}_$minutes');
        }
      }
    }
    return keys;
  }

  bool _allLogged(AlarmPayload p) {
    final logs = _logs[p.pid];
    if (logs == null || p.kind != AlarmPayload.dose) return false;
    return p.logIds.every(logs.containsKey);
  }

  /// A dose snoozed in the app: the alarm ringing for it stops, a snooze
  /// alarm for just this dose rings at [until], and the server's follow-up
  /// waits. The regular schedule is unchanged.
  Future<void> snoozeDose(DoseOccurrence o, String pid, DateTime until) async {
    final uid = _uid;
    if (uid == null) return;
    final profile = _profiles.profiles.firstWhereOrNull((p) => p.id == pid);
    final group = 'alarm:dose:$pid:${CareDates.dayKey(o.day)}_${o.minutes}';
    final payload = AlarmPayload(
      kind: AlarmPayload.dose,
      uid: uid,
      pid: pid,
      key: 'alarm:dose:$pid:${o.logId}',
      day: o.day,
      minutes: o.minutes,
      medicineIds: [o.medicine.id],
      snoozed: true,
    );
    try {
      await _repository.snoozeDose(uid, pid, o.logId, until);
    } catch (e) {
      _log('snooze', e);
    }
    if (!_notify.ready ||
        _notify.permission.value != NotifyPermission.granted) {
      return;
    }
    try {
      await _notify.plugin.dismiss(AlarmActions.idFor(group));
      await _notify.plugin.createNotification(
        content: AlarmActions.content(
          payload: payload,
          title: 'Time for ${o.medicine.name}',
          body: [
            '${profile?.fullName ?? ''} • ${CareDates.clockOf(o.at)} (snoozed)',
            [
              o.medicine.name,
              o.medicine.dosage,
            ].where((s) => s.isNotEmpty).join(' — '),
          ].join('\n'),
        ),
        actionButtons: AlarmActions.buttons(payload),
        schedule: NotificationCalendar.fromDate(
          date: until,
          allowWhileIdle: true,
          preciseAlarm: _notify.exactAlarms.value ?? false,
        ),
      );
    } catch (e) {
      _log('snooze', e);
    }
  }

  /// A test alarm a minute from now (Dismiss and Snooze only; logs
  /// nothing), for checking sound, lock screen and buttons on a device.
  Future<bool> testAlarm() async {
    final uid = _uid;
    if (uid == null || !_notify.ready) return false;
    final payload = AlarmPayload(
      kind: AlarmPayload.visit,
      uid: uid,
      pid: UserProfile.selfId,
      key: 'alarm:test',
    );
    try {
      return await _notify.plugin.createNotification(
        content: AlarmActions.content(
          payload: payload,
          title: 'DoseMate test alarm',
          body: 'This is how reminders ring on this device.',
        ),
        actionButtons: AlarmActions.buttons(payload),
        schedule: NotificationCalendar.fromDate(
          date: _clock().add(const Duration(minutes: 1)),
          allowWhileIdle: true,
          preciseAlarm: _notify.exactAlarms.value ?? false,
        ),
      );
    } catch (e) {
      _log('test', e);
      return false;
    }
  }

  /// On sign out: no alarms of the account stay on the device.
  Future<void> clearAll() async {
    _stopAll();
    _uid = null;
    if (!_notify.ready) return;
    try {
      await _notify.plugin.cancelNotificationsByChannelKey(
        AlarmActions.channel,
      );
    } catch (e) {
      _log('clear', e);
    }
  }

  static void _log(String step, Object e) {
    if (kDebugMode) debugPrint('Alarms $step error: ${e.runtimeType}');
  }

  @override
  void onClose() {
    _debounce?.cancel();
    _refresh?.cancel();
    for (final w in _workers) {
      w.dispose();
    }
    _stopAll();
    _notify.onGranted.remove(_reconcileNow);
    _auth.beforeSignOut.remove(clearAll);
    super.onClose();
  }
}
