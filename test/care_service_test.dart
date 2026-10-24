import 'dart:async';

import 'package:dosemate/core/utils/care_dates.dart';
import 'package:dosemate/data/models/medicine.dart';
import 'package:dosemate/data/models/user_profile.dart';
import 'package:dosemate/data/models/visit.dart';
import 'package:dosemate/data/repositories/care_repository.dart';
import 'package:dosemate/data/repositories/profile_repository.dart';
import 'package:dosemate/data/services/care_service.dart';
import 'package:dosemate/data/services/profile_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'support/fake_care.dart';

import 'support/fake_profiles.dart';

const uid = 'uid-1';

/// Lets the fake Firestore deliver snapshots.
Future<void> settle() => Future<void>.delayed(Duration.zero);

Medicine med(
  String id, {
  String name = 'Amoxicillin',
  Frequency frequency = Frequency.multipleDaily,
  List<int> doses = const [8 * 60, 20 * 60],
  List<int> days = const [],
  DateTime? start,
  int courseDays = 7,
  int quantity = 14,
  MedicineStatus status = MedicineStatus.active,
}) => Medicine(
  id: id,
  name: name,
  frequency: frequency,
  doseMinutes: doses,
  days: days,
  startDate: start ?? DateTime(2026, 10, 24),
  courseDays: courseDays,
  quantity: quantity,
  status: status,
);

void main() {
  // Saturday 24 Oct 2026, 2:00 PM local.
  var now = DateTime(2026, 10, 24, 14);
  late FakeCare db;
  late ProfileService profiles;
  late CareService care;

  setUp(() async {
    Get.testMode = true;
    now = DateTime(2026, 10, 24, 14);
    db = FakeCare();
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
    profiles = ProfileService(store);
    await profiles.start(uid, selfName: 'Eleanor Vance');
    care = putCare(profiles, db, now: () => now);
    await settle();
  });

  tearDown(Get.reset);

  test('an account with no profiles gets Myself and loads', () async {
    Get.reset();
    final empty = FakeProfiles();
    final fresh = ProfileService(empty);
    final service = putCare(fresh, FakeCare(), now: () => now);
    await fresh.start('uid-2', selfName: 'Sam Lee');
    await settle();
    expect(empty.profilesOf('uid-2').keys, [UserProfile.selfId]);
    expect(fresh.activeProfile?.fullName, 'Sam Lee');
    expect(service.status.value, CareStatus.ready);
  });

  test(
    'if Myself can’t be created, an error replaces endless loading',
    () async {
      Get.reset();
      final empty = FakeProfiles()
        ..saveFailure = const ProfileFailure("You're offline.");
      final fresh = ProfileService(empty);
      final service = putCare(fresh, FakeCare(), now: () => now);
      await fresh.start('uid-2', selfName: 'Sam Lee');
      await settle();
      expect(service.status.value, CareStatus.error);
      expect(service.error.value, "You're offline.");

      empty.saveFailure = null;
      await service.retry();
      await settle();
      expect(service.status.value, CareStatus.ready);
    },
  );

  test('profile updates don’t restart the schedule listeners', () async {
    await care.saveMedicine('self', med('m1'), isNew: true);
    await settle();
    var restarts = 0;
    ever(care.status, (CareStatus s) {
      if (s != CareStatus.ready) restarts++;
    });
    // A profile edit arrives as a new profiles snapshot.
    profiles.profiles.value = [...profiles.profiles];
    await settle();
    expect(restarts, 0);
    expect(care.medicines, isNotEmpty);
  });

  test('one listener set at a time across switches', () async {
    expect(db.listeners, 3);
    await profiles.switchTo('p1');
    await settle();
    expect(db.listeners, 3);
  });

  test('errors are reported and retry recovers', () async {
    db.failNext = const CareFailure(
      'No permission.',
      code: 'permission-denied',
    );
    await expectLater(
      care.saveMedicine('self', med('m1'), isNew: true),
      throwsA(isA<CareFailure>()),
    );
    expect(db.medicinesOf(uid, 'self'), isEmpty);
    db.offline = true;
    expect(
      await care.saveMedicine('self', med('m1'), isNew: true),
      WriteResult.pending,
    );
  });

  test('records live under the account and profile, never mixed', () async {
    expect(care.status.value, CareStatus.ready);
    await care.saveMedicine('self', med('m1'), isNew: true);
    await care.saveMedicine('p1', med('m2', name: 'Lisinopril'), isNew: true);
    await settle();

    expect(db.medicinesOf(uid, 'self').keys, ['m1']);
    expect(db.medicinesOf(uid, 'p1').keys, ['m2']);
    expect(care.medicines.map((m) => m.name), ['Amoxicillin']);

    await profiles.switchTo('p1');
    await settle();
    expect(care.medicines.map((m) => m.name), ['Lisinopril']);
    expect(care.profileId, 'p1');

    await profiles.switchTo('self');
    await settle();
    expect(care.medicines.map((m) => m.name), ['Amoxicillin']);
  });

  test('switching clears stale data before the new profile loads', () async {
    await care.saveMedicine('self', med('m1'), isNew: true);
    await settle();
    expect(care.medicines, isNotEmpty);

    profiles.activeProfileId.value = 'p1';
    // Synchronously cleared: nothing of Myself is visible under Ruth.
    expect(care.medicines, isEmpty);
    expect(care.status.value, CareStatus.loading);
  });

  test('sign out cancels listeners and clears everything', () async {
    await care.saveMedicine('self', med('m1'), isNew: true);
    await settle();
    profiles.stop();
    expect(care.medicines, isEmpty);
    expect(care.status.value, CareStatus.idle);

    expect(db.listeners, 0);
    // A change made elsewhere after sign out never reaches this state.
    await db.saveMedicine(uid, 'self', med('m9'), isNew: true);
    await settle();
    expect(care.medicines, isEmpty);
  });

  test('saving the same new record twice keeps one document', () async {
    final m = med('m1');
    await care.saveMedicine('self', m, isNew: true);
    await care.saveMedicine('self', m, isNew: false);
    expect(db.medicinesOf(uid, 'self').length, 1);
    expect(db.creates, 1);
  });

  test('schedules follow local days, course bounds and weekdays', () async {
    final today = DateTime(2026, 10, 24); // Saturday
    final m = med('m1', courseDays: 2);
    expect(m.endDate, DateTime(2026, 10, 25));
    expect(m.isScheduledOn(today), isTrue);
    expect(m.isScheduledOn(DateTime(2026, 10, 25, 23, 59)), isTrue);
    expect(m.isScheduledOn(DateTime(2026, 10, 26)), isFalse);
    expect(m.isScheduledOn(DateTime(2026, 10, 23)), isFalse);

    final weekly = med(
      'm2',
      frequency: Frequency.specificDays,
      doses: [9 * 60],
      days: [DateTime.monday],
      courseDays: 30,
    );
    expect(weekly.isScheduledOn(today), isFalse);
    expect(weekly.isScheduledOn(DateTime(2026, 10, 26)), isTrue);

    expect(
      med('m3', status: MedicineStatus.paused).isScheduledOn(today),
      isFalse,
    );
    expect(
      med('m4', frequency: Frequency.asNeeded).occurrencesOn(today),
      isEmpty,
    );

    // Stored as day keys, so they read back as the same local days.
    final copy = Medicine.fromMap(
      'm1',
      m.toWriteMap()
        ..remove('photoUrl')
        ..remove('photoPath'),
    );
    expect(copy.startDate, today);
    expect(copy.courseDays, 2);
    expect(CareDates.dayKey(DateTime(2026, 3, 9)), '2026-03-09');
  });

  test(
    'today’s doses are ordered and the next one skips logged doses',
    () async {
      await care.saveMedicine(
        'self',
        med('m1', doses: [20 * 60, 8 * 60]),
        isNew: true,
      );
      await care.saveMedicine(
        'self',
        med('m2', name: 'Vitamin D3', doses: [9 * 60]),
        isNew: true,
      );
      await settle();
      expect(care.todaysDoses.map((o) => '${o.medicine.name} ${o.minutes}'), [
        'Amoxicillin 480',
        'Vitamin D3 540',
        'Amoxicillin 1200',
      ]);
      await care.logDose(care.todaysDoses.first, DoseStatus.taken);
      await settle();
      expect(care.nextDose!.medicine.name, 'Vitamin D3');
    },
  );

  test(
    'logging one occurrence is idempotent and adjusts supply once',
    () async {
      await care.saveMedicine('self', med('m1', quantity: 5), isNew: true);
      await settle();
      final dose = care.todaysDoses.first;

      // Repeated taps while the first write is in flight.
      db.gate = Completer<void>();
      final first = care.logDose(dose, DoseStatus.taken);
      expect(await care.logDose(dose, DoseStatus.taken), isNull);
      db.gate!.complete();
      await first;
      db.gate = null;
      await settle();
      // Again after it landed: already taken, so nothing changes.
      expect(await care.logDose(dose, DoseStatus.taken), isNull);
      await settle();

      expect(db.logsOf(uid, 'self').keys, ['m1_2026-10-24_480']);
      expect(care.medicineById('m1')!.quantity, 4);

      // Only that occurrence: the evening dose is still due.
      expect(care.logFor(care.todaysDoses.last), isNull);

      // Changing to skipped returns the dose; undo of a skip changes nothing.
      await care.logDose(dose, DoseStatus.skipped);
      await settle();
      expect(care.medicineById('m1')!.quantity, 5);
      await care.undoDose(care.logFor(dose)!);
      await settle();
      expect(care.logFor(dose), isNull);
      expect(care.medicineById('m1')!.quantity, 5);
    },
  );

  test('streak counts days with every dose taken', () async {
    final start = DateTime(2026, 10, 21);
    await care.saveMedicine(
      'self',
      med('m1', doses: [9 * 60], start: start, courseDays: 10),
      isNew: true,
    );
    await settle();
    final m = care.medicineById('m1')!;
    for (final day in [21, 22, 23]) {
      await care.logDose(
        DoseOccurrence(m, DateTime(2026, 10, day), 9 * 60),
        DoseStatus.taken,
      );
    }
    await settle();
    expect(care.streak(m), 3);
  });

  test('upcoming visits are scheduled ones from today, soonest first, and '
      'the window moves at midnight', () async {
    Visit visit(String id, DateTime at, {VisitStatus? status}) => Visit(
      id: id,
      title: id,
      category: 'Dentist',
      startsAt: at,
      status: status ?? VisitStatus.scheduled,
    );
    for (final v in [
      visit('later', DateTime(2026, 10, 30, 9)),
      visit('yesterday', DateTime(2026, 10, 23, 16)),
      visit('this morning', DateTime(2026, 10, 24, 8)),
      visit(
        'cancelled',
        DateTime(2026, 10, 25, 9),
        status: VisitStatus.cancelled,
      ),
      visit('tomorrow', DateTime(2026, 10, 25, 15, 30)),
    ]) {
      await care.saveVisit('self', v, isNew: true);
    }
    await settle();
    expect(care.visits.map((v) => v.title), [
      'this morning',
      'tomorrow',
      'later',
    ]);

    now = DateTime(2026, 10, 25, 0, 0, 1);
    care.rollOver();
    await settle();
    expect(care.today.value, DateTime(2026, 10, 25));
    expect(care.visits.map((v) => v.title), ['tomorrow', 'later']);
  });

  test('delete removes the medicine with its logs in one batch', () async {
    await care.saveMedicine('self', med('m1'), isNew: true);
    await settle();
    await care.logDose(care.todaysDoses.first, DoseStatus.taken);
    await settle();
    await care.deleteMedicine('self', care.medicineById('m1')!);
    await settle();
    expect(care.medicines, isEmpty);
    expect(care.logs, isEmpty);
    expect(db.logsOf(uid, 'self'), isEmpty);
  });
}
