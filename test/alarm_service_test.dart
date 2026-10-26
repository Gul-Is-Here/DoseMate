import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:dosemate/data/models/medicine.dart';
import 'package:dosemate/data/models/user_profile.dart';
import 'package:dosemate/data/models/visit.dart';
import 'package:dosemate/data/repositories/auth_repository.dart';
import 'package:dosemate/data/services/alarm_actions.dart';
import 'package:dosemate/data/services/alarm_service.dart';
import 'package:dosemate/data/services/auth_service.dart';
import 'package:dosemate/data/services/care_service.dart';
import 'package:dosemate/data/services/notification_service.dart';
import 'package:dosemate/data/services/profile_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'support/fake_care.dart';
import 'support/fake_profiles.dart';
import 'support/shell_harness.dart';

void main() {
  const uid = 'uid-1';
  late FakeCare care;
  late AlarmService alarms;
  var now = fixedNow(); // Sat 24 Oct 2026, 2:00 PM

  Future<void> start({
    bool followUps = false,
    NotificationService? notify,
  }) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    final store = FakeProfiles()
      ..put(
        uid,
        const UserProfile(
          id: UserProfile.selfId,
          type: ProfileType.self,
          fullName: 'Eleanor Vance',
        ),
      )
      ..put(
        uid,
        const UserProfile(
          id: 'p1',
          type: ProfileType.parent,
          fullName: 'Ruth Vance',
        ),
      );
    final profiles = ProfileService(store);
    await profiles.start(uid, selfName: 'Eleanor Vance');
    final auth = Get.put(AuthService(AuthRepository(NoAuth()), profiles));
    auth.user.value = FakeUser();
    care = FakeCare();
    seedCare(care);
    alarms = AlarmService(
      auth,
      profiles,
      care,
      notify ?? NotificationService(),
      clock: () => now,
      followUps: followUps,
    ).init();
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() async {
    now = fixedNow();
    await start();
  });

  tearDown(() {
    alarms.onClose();
    Get.reset();
  });

  List<String> keys() => [for (final p in alarms.plan()) p.payload.key];

  test('every owned profile gets alarms, not only the active one', () {
    final plans = alarms.plan();
    // Next 48 h from Sat 2 PM: Amoxicillin 8 PM Sat, 8 AM/8 PM Sun, 8 AM
    // Mon; Vitamin D3 9 AM Sun/Mon; Lisinopril (Ruth) 7 AM Sun/Mon.
    expect(plans.first.payload.key, 'alarm:dose:self:2026-10-24_1200');
    expect(plans.first.title, 'Time for Amoxicillin');
    expect(plans.first.body, contains('Eleanor Vance • 8:00 PM'));
    expect(plans.first.body, contains('Amoxicillin — 500mg - 1 capsule'));
    final ruth = plans.where((p) => p.payload.pid == 'p1').toList();
    expect(ruth, isNotEmpty);
    expect(ruth.first.body, startsWith('Ruth Vance • 7:00 AM'));
    expect(plans.every((p) => p.at.isAfter(now)), isTrue);
    expect(
      plans.every((p) => !p.at.isAfter(now.add(AlarmService.horizon))),
      isTrue,
    );
  });

  test('ids are stable and keys unique', () {
    final a = alarms.plan();
    final b = alarms.plan();
    expect([for (final p in a) p.id], [for (final p in b) p.id]);
    expect(keys().toSet().length, keys().length);
    expect(a.first.id, AlarmActions.idFor(a.first.payload.key));
  });

  test('doses at the same minute share one alarm', () async {
    care.medicinesOf(uid, 'self')['iron'] = Medicine(
      id: 'iron',
      name: 'Iron',
      frequency: Frequency.onceDaily,
      doseMinutes: const [20 * 60],
      startDate: DateTime(2026, 10, 1),
      courseDays: 90,
      quantity: 30,
    );
    care.emit();
    await Future<void>.delayed(Duration.zero);
    final eight = alarms
        .plan()
        .where((p) => p.payload.key == 'alarm:dose:self:2026-10-24_1200')
        .single;
    expect(eight.title, 'Time for 2 medicines');
    expect(eight.payload.medicineIds, ['amox', 'iron']);
  });

  test('a logged dose and a paused medicine get no alarm', () async {
    final amox = care.medicinesOf(uid, 'self')['amox']!;
    final o = DoseOccurrence(amox, DateTime(2026, 10, 24), 20 * 60);
    care.logsOf(uid, 'self')[o.logId] = DoseLog(
      medicineId: 'amox',
      day: o.day,
      minutes: o.minutes,
      status: DoseStatus.taken,
      loggedAt: now,
    );
    care.emit();
    await Future<void>.delayed(Duration.zero);
    expect(keys(), isNot(contains('alarm:dose:self:2026-10-24_1200')));

    care.medicinesOf(uid, 'p1')['lis'] = care
        .medicinesOf(uid, 'p1')['lis']!
        .withStatus(MedicineStatus.paused, DateTime(2026, 10, 24));
    care.emit();
    await Future<void>.delayed(Duration.zero);
    expect(alarms.plan().where((p) => p.payload.pid == 'p1'), isEmpty);
  });

  test('appointment reminders follow the chosen offsets and moves', () async {
    care.visitsOf(uid, 'self')['gp'] = Visit(
      id: 'gp',
      title: 'GP Visit',
      category: 'General',
      startsAt: DateTime(2026, 10, 25, 10),
      clinic: 'Main St Clinic',
      reminders: const ['1 day before', '1 hour before'],
    );
    care.emit();
    await Future<void>.delayed(Duration.zero);
    final visits = alarms
        .plan()
        .where((p) => p.payload.kind == AlarmPayload.visit)
        .toList();
    // "1 day before" (Sat 10 AM) has passed; only the 9 AM one is left.
    expect(visits, hasLength(1));
    expect(visits.single.at, DateTime(2026, 10, 25, 9));
    expect(visits.single.title, 'GP Visit — 1 hour before');
    expect(visits.single.body, contains('Main St Clinic'));
    final before = visits.single.payload.key;

    care.visitsOf(uid, 'self')['gp'] = Visit(
      id: 'gp',
      title: 'GP Visit',
      category: 'General',
      startsAt: DateTime(2026, 10, 25, 11),
      reminders: const ['1 hour before'],
    );
    care.emit();
    await Future<void>.delayed(Duration.zero);
    final moved = alarms.plan().singleWhere(
      (p) => p.payload.kind == AlarmPayload.visit,
    );
    expect(moved.payload.key, isNot(before));
    expect(moved.at, DateTime(2026, 10, 25, 10));
  });

  test('at most maxAlarms, soonest first', () async {
    for (var i = 0; i < 40; i++) {
      care.medicinesOf(uid, 'self')['m$i'] = Medicine(
        id: 'm$i',
        name: 'Med $i',
        frequency: Frequency.onceDaily,
        doseMinutes: [600 + i],
        startDate: DateTime(2026, 10, 1),
        courseDays: 90,
        quantity: 30,
      );
    }
    care.emit();
    await Future<void>.delayed(Duration.zero);
    final plans = alarms.plan();
    expect(plans, hasLength(AlarmService.maxAlarms));
    for (var i = 1; i < plans.length; i++) {
      expect(plans[i].at.isBefore(plans[i - 1].at), isFalse);
    }
  });

  test('payload survives the notification round trip', () {
    final p = alarms.plan().first.payload;
    final back = AlarmPayload.from(p.toMap());
    expect(back.key, p.key);
    expect(back.logIds, ['amox_2026-10-24_1200']);
    expect(back.uid, uid);
    expect(AlarmPayload.from({...p.toMap(), 'snooze': '1'}).snoozed, isTrue);
  });

  test('a shared alarm stops only once all its doses are logged', () async {
    care.medicinesOf(uid, 'self')['iron'] = Medicine(
      id: 'iron',
      name: 'Iron',
      frequency: Frequency.onceDaily,
      doseMinutes: const [8 * 60],
      startDate: DateTime(2026, 10, 1),
      courseDays: 90,
      quantity: 30,
    );
    const eight = 'alarm:dose:self:2026-10-24_480';
    void log(String id) {
      final m = care.medicinesOf(uid, 'self')[id]!;
      final o = DoseOccurrence(m, DateTime(2026, 10, 24), 8 * 60);
      care.logsOf(uid, 'self')[o.logId] = DoseLog(
        medicineId: id,
        day: o.day,
        minutes: o.minutes,
        status: DoseStatus.taken,
        loggedAt: now,
      );
      care.emit();
    }

    log('amox');
    await Future<void>.delayed(Duration.zero);
    expect(alarms.loggedGroups(), isNot(contains(eight)));
    log('iron');
    await Future<void>.delayed(Duration.zero);
    expect(alarms.loggedGroups(), contains(eight));
    // Vitamin D3 (9 AM, alone, taken in the seed) is done too.
    expect(alarms.loggedGroups(), contains('alarm:dose:self:2026-10-24_540'));
  });

  test('a snooze in the app reaches the alarms and the server', () async {
    final profiles = Get.find<AuthService>().profiles;
    final service = putCare(profiles, care, now: () => now);
    service.onSnooze.add(alarms.snoozeDose);
    await Future<void>.delayed(Duration.zero);
    final o = service.todaysDoses.firstWhere((o) => o.medicine.id == 'amox');
    service.snooze(o);
    await Future<void>.delayed(Duration.zero);
    expect(service.isSnoozed(o), isTrue);
    expect(
      care.snoozes['$uid/self/${o.logId}'],
      now.add(CareService.snoozeFor),
    );
  });

  group('Android follow-ups for unanswered alarms', () {
    Future<void> android() async {
      alarms.onClose();
      Get.reset();
      await start(followUps: true);
    }

    const eightPm = 'alarm:dose:self:2026-10-24_1200';

    test('each alarm leaves a quiet "still due" reminder once it stops '
        'ringing, with its own id', () async {
      await android();
      final plans = alarms.plan().where((p) => p.payload.key == eightPm);
      final alarm = plans.singleWhere((p) => !p.payload.followUp);
      final late = plans.singleWhere((p) => p.payload.followUp);
      expect(late.at, alarm.at.add(AlarmActions.followUpAfter));
      expect(AlarmActions.followUpAfter, greaterThan(AlarmActions.ringFor));
      expect(late.title, 'Still due: Amoxicillin');
      expect(late.body, endsWith('Not logged yet'));
      expect(late.id, AlarmActions.followUpIdFor(eightPm));
      expect(late.id, isNot(alarm.id));
      expect(late.id, isNot(AlarmActions.snoozeIdFor(eightPm)));
      // It logs the same doses from its buttons.
      expect(late.payload.logIds, alarm.payload.logIds);
      // A follow-up is a reminder that stays: no insistent ring, no timeout.
      final content = AlarmActions.content(
        payload: late.payload,
        title: late.title,
        body: late.body,
      );
      expect(content.category, NotificationCategory.Reminder);
      expect(content.timeoutAfter, isNull);
      final ringing = AlarmActions.content(
        payload: alarm.payload,
        title: alarm.title,
        body: alarm.body,
      );
      expect(ringing.category, NotificationCategory.Alarm);
      expect(ringing.timeoutAfter, AlarmActions.ringFor);
      // Visit reminders get one too.
      care.visitsOf(uid, 'self')['gp'] = Visit(
        id: 'gp',
        title: 'GP Visit',
        category: 'General',
        startsAt: DateTime(2026, 10, 25, 10),
        reminders: const ['1 hour before'],
      );
      care.emit();
      await Future<void>.delayed(Duration.zero);
      final visit = alarms.plan().singleWhere(
        (p) => p.payload.kind == AlarmPayload.visit && p.payload.followUp,
      );
      expect(visit.title, 'Reminder: GP Visit — 1 hour before');
      expect(visit.at, DateTime(2026, 10, 25, 9, 3, 5));
    });

    test('after the alarm time only the follow-up is left, and after that '
        'neither', () async {
      await android();
      now = DateTime(2026, 10, 24, 20, 1);
      var plans = alarms.plan().where((p) => p.payload.key == eightPm);
      expect(plans.single.payload.followUp, isTrue);
      now = DateTime(2026, 10, 24, 20, 4);
      plans = alarms.plan().where((p) => p.payload.key == eightPm);
      expect(plans, isEmpty);
    });

    test('a logged dose gets no follow-up', () async {
      await android();
      final amox = care.medicinesOf(uid, 'self')['amox']!;
      final o = DoseOccurrence(amox, DateTime(2026, 10, 24), 20 * 60);
      care.logsOf(uid, 'self')[o.logId] = DoseLog(
        medicineId: 'amox',
        day: o.day,
        minutes: o.minutes,
        status: DoseStatus.taken,
        loggedAt: now,
      );
      care.emit();
      await Future<void>.delayed(Duration.zero);
      expect(keys(), isNot(contains(eightPm)));
    });

    test('iOS keeps every notification, so it gets none', () {
      expect(alarms.plan().where((p) => p.payload.followUp), isEmpty);
    });

    test('the follow-up flag survives the round trip', () async {
      await android();
      final late = alarms.plan().firstWhere((p) => p.payload.followUp);
      final back = AlarmPayload.from(late.payload.toMap());
      expect(back.followUp, isTrue);
      expect(back.id, late.id);
    });
  });

  test('alarms set while exact alarms were off are set again once they are '
      'allowed, so they ring on time', () async {
    alarms.onClose();
    Get.reset();
    final plugin = _FakePlugin();
    final notify = NotificationService(plugin: plugin)
      ..ready = true
      ..permission.value = NotifyPermission.granted
      ..exactAlarms.value = false;
    await start(notify: notify);
    Future<void> granted() async {
      for (final f in List.of(notify.onGranted)) {
        await f();
      }
    }

    await granted();
    final first = plugin.scheduled.length;
    expect(first, greaterThan(0));
    expect(
      plugin.scheduled.values.map((n) => n.schedule!.preciseAlarm),
      everyElement(isFalse),
    );

    // Allowed on the system page: every pending alarm is set again, exact.
    notify.exactAlarms.value = true;
    plugin.created = 0;
    await granted();
    expect(plugin.scheduled.length, first);
    expect(plugin.created, first);
    expect(
      plugin.scheduled.values.map((n) => n.schedule!.preciseAlarm),
      everyElement(isTrue),
    );

    // Nothing changed: nothing is set again.
    plugin.created = 0;
    await granted();
    expect(plugin.created, 0);
  });
}

/// Keeps scheduled alarms in memory, like the plugin's own list.
class _FakePlugin extends AwesomeNotifications {
  final scheduled = <int, NotificationModel>{};
  var created = 0;

  @override
  Future<bool> createNotification({
    required NotificationContent content,
    NotificationSchedule? schedule,
    List<NotificationActionButton>? actionButtons,
    Map<String, NotificationLocalization>? localizations,
  }) async {
    created++;
    scheduled[content.id!] = NotificationModel(
      content: content,
      schedule: schedule,
      actionButtons: actionButtons,
    );
    return true;
  }

  @override
  Future<List<NotificationModel>> listScheduledNotifications() async =>
      scheduled.values.toList();

  @override
  Future<void> cancel(int id) async => scheduled.remove(id);

  @override
  Future<void> dismiss(int id) async {}
}
