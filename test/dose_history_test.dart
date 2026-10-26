import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dosemate/core/utils/care_dates.dart';
import 'package:dosemate/core/utils/dose_state.dart';
import 'package:dosemate/data/models/medicine.dart';
import 'package:dosemate/data/models/user_profile.dart';
import 'package:dosemate/data/repositories/care_repository.dart';
import 'package:dosemate/data/services/care_service.dart';
import 'package:dosemate/data/services/profile_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'support/fake_care.dart';
import 'support/fake_profiles.dart';

const uid = 'uid-1';

Future<void> settle() => Future<void>.delayed(Duration.zero);

Medicine med({
  List<int> doses = const [480],
  MedicineStatus status = MedicineStatus.active,
  int quantity = 10,
}) => Medicine(
  id: 'm1',
  name: 'Lisinopril',
  frequency: Frequency.onceDaily,
  doseMinutes: doses,
  startDate: DateTime(2026, 10, 14),
  courseDays: 30,
  quantity: quantity,
  status: status,
);

List<int> minutesOn(Medicine m, DateTime day) => [
  for (final o in m.occurrencesOn(day)) o.minutes,
];

void main() {
  final today = DateTime(2026, 10, 24);
  final past = DateTime(2026, 10, 20);
  final tomorrow = DateTime(2026, 10, 25);

  group('schedule history', () {
    test('an edit applies from today; past days keep the old times', () {
      final old = med();
      final edited = med(doses: [540, 1260]).withHistoryFrom(old, today);
      expect(minutesOn(edited, past), [480]);
      expect(minutesOn(edited, today), [540, 1260]);
      expect(minutesOn(edited, tomorrow), [540, 1260]);

      // A second edit the same day replaces today's schedule only.
      final again = med(doses: [600]).withHistoryFrom(edited, today);
      expect(again.pastSchedules, hasLength(1));
      expect(minutesOn(again, past), [480]);
      expect(minutesOn(again, today), [600]);
    });

    test('an edit that keeps the schedule adds no history', () {
      expect(med().withHistoryFrom(med(), today).pastSchedules, isEmpty);
    });

    test('pausing hides the paused days only; resuming closes the pause', () {
      final paused = med().withStatus(MedicineStatus.paused, past);
      expect(minutesOn(paused, DateTime(2026, 10, 19)), [480]);
      expect(minutesOn(paused, past), isEmpty);
      expect(minutesOn(paused, today), isEmpty);

      final resumed = paused.withStatus(MedicineStatus.active, today);
      expect(minutesOn(resumed, DateTime(2026, 10, 19)), [480]);
      expect(minutesOn(resumed, past), isEmpty);
      expect(minutesOn(resumed, DateTime(2026, 10, 23)), isEmpty);
      expect(minutesOn(resumed, today), [480]);
    });

    test('a pause undone the same day leaves no trace', () {
      final m = med()
          .withStatus(MedicineStatus.paused, today)
          .withStatus(MedicineStatus.active, today);
      expect(m.pauses, isEmpty);
      expect(minutesOn(m, today), [480]);
    });

    test('archived keeps its past doses', () {
      final m = med().withStatus(MedicineStatus.archived, today);
      expect(minutesOn(m, past), [480]);
      expect(minutesOn(m, today), isEmpty);
    });

    test('paused before pauses were recorded shows nothing, as before', () {
      final legacy = med(status: MedicineStatus.paused);
      expect(minutesOn(legacy, past), isEmpty);
    });

    test('history survives a save and load', () {
      final m = med(doses: [540])
          .withHistoryFrom(med(), today)
          .withStatus(MedicineStatus.paused, tomorrow);
      final map = m.toWriteMap();
      // photoUrl/photoPath are deletes on write; not stored.
      final loaded = Medicine.fromMap('m1', {
        for (final e in map.entries)
          if (e.value is! FieldValue) e.key: e.value,
      });
      expect(minutesOn(loaded, past), [480]);
      expect(minutesOn(loaded, today), [540]);
      expect(minutesOn(loaded, tomorrow), isEmpty);
    });
  });

  group('dose state', () {
    final o = DoseOccurrence(med(), today, 480);

    test('one rule for every screen', () {
      DoseState at(DateTime now, [DoseLog? log]) => DoseStates.of(o, log, now);
      expect(at(DateTime(2026, 10, 23, 12)), DoseState.scheduled);
      expect(at(DateTime(2026, 10, 24, 7)), DoseState.due);
      expect(at(DateTime(2026, 10, 24, 8, 15)), DoseState.due);
      expect(at(DateTime(2026, 10, 24, 8, 16)), DoseState.overdue);
      expect(at(DateTime(2026, 10, 25, 0, 1)), DoseState.missed);
      final taken = DoseLog(
        medicineId: 'm1',
        day: today,
        minutes: 480,
        status: DoseStatus.taken,
      );
      expect(at(DateTime(2026, 10, 25, 9), taken), DoseState.taken);
    });

    test('unknown stored status never reads as taken', () {
      final log = DoseLog.fromMap({
        'medicineId': 'm1',
        'day': '2026-10-24',
        'minutes': 480,
        'status': 'something-new',
      });
      expect(log.status, DoseStatus.skipped);
      expect(DoseLog.fromMap({'status': DoseLog.cleared}).isUndone, isTrue);
    });
  });

  group('dose taps', () {
    test('a tap stays above the last revision when the clock is behind', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1000);
      expect(DoseTap.at(now).rev, 1000);
      expect(DoseTap.at(now, previousRev: 5000).rev, 5001);
      expect(DoseTap.at(now).id, isNot(DoseTap.at(now).id));
    });
  });

  group('versioned writes and stock', () {
    var now = DateTime(2026, 10, 24, 9);
    late FakeCare db;
    late CareService care;

    setUp(() async {
      Get.testMode = true;
      now = DateTime(2026, 10, 24, 9);
      db = FakeCare();
      final store = FakeProfiles()
        ..put(
          uid,
          const UserProfile(
            id: UserProfile.selfId,
            type: ProfileType.self,
            fullName: 'Eleanor Vance',
          ),
        );
      final profiles = ProfileService(store);
      await profiles.start(uid, selfName: 'Eleanor Vance');
      care = putCare(profiles, db, now: () => now);
      await settle();
      await care.saveMedicine('self', med(quantity: 2), isNew: true);
      await settle();
    });

    tearDown(Get.reset);

    int quantity() => db.medicinesOf(uid, 'self')['m1']!.quantity;

    test('taken, undo and taken again count one dose', () async {
      final dose = care.todaysDoses.single;
      await care.logDose(dose, DoseStatus.taken);
      await settle();
      expect(quantity(), 1);
      now = now.add(const Duration(minutes: 1));
      await care.undoDose(care.logFor(dose)!);
      await settle();
      expect(care.logFor(dose), isNull);
      expect(quantity(), 2);
      now = now.add(const Duration(minutes: 1));
      await care.logDose(dose, DoseStatus.taken);
      await settle();
      expect(quantity(), 1);
    });

    test('an older tap from another device is refused', () async {
      final dose = care.todaysDoses.single;
      // Another device's tap, made earlier but arriving later.
      final late = DoseTap.at(now.subtract(const Duration(minutes: 5)));
      await care.logDose(dose, DoseStatus.taken);
      await settle();
      await expectLater(
        db.logDose(uid, 'self', dose, DoseStatus.skipped, action: late),
        throwsA(isA<CareFailure>()),
      );
      expect(db.logsOf(uid, 'self')[dose.logId]!.status, DoseStatus.taken);
      expect(quantity(), 1);
    });

    test('an older tap can’t bring back an undone dose', () async {
      final dose = care.todaysDoses.single;
      final early = DoseTap.at(now);
      await db.logDose(uid, 'self', dose, DoseStatus.taken, action: early);
      await settle();
      now = now.add(const Duration(minutes: 1));
      await care.undoDose(care.logFor(dose)!);
      await settle();
      await expectLater(
        db.logDose(uid, 'self', dose, DoseStatus.taken, action: early),
        throwsA(isA<CareFailure>()),
      );
      expect(db.logsOf(uid, 'self'), isEmpty);
      expect(quantity(), 2);
    });

    test('a retry of the same tap is accepted and counted once', () async {
      final dose = care.todaysDoses.single;
      final tap = DoseTap.at(now);
      await db.logDose(uid, 'self', dose, DoseStatus.taken, action: tap);
      await db.logDose(uid, 'self', dose, DoseStatus.taken, action: tap);
      await settle();
      expect(quantity(), 1);
    });

    test('taking a dose never takes the supply below zero', () async {
      await care.saveMedicine('self', med(quantity: 0), isNew: false);
      await settle();
      final dose = care.todaysDoses.single;
      await care.logDose(dose, DoseStatus.taken);
      await settle();
      expect(quantity(), 0);
      now = now.add(const Duration(minutes: 1));
      await care.undoDose(care.logFor(dose)!);
      await settle();
      expect(quantity(), 0);
    });

    test('pausing records the pause; earlier doses still count', () async {
      final yesterday = CareDates.addDays(today, -1);
      now = DateTime(2026, 10, 24, 12);
      await care.setMedicineStatus(
        care.medicineById('m1')!,
        MedicineStatus.paused,
      );
      await settle();
      final m = care.medicineById('m1')!;
      expect(m.pauses.single.from, today);
      expect(m.occurrencesOn(yesterday), hasLength(1));
      expect(care.todaysDoses, isEmpty);
    });
  });

  group('dose tap revisions', () {
    final now = DateTime.utc(2026, 10, 24, 8);
    final ms = now.millisecondsSinceEpoch;

    test('a fast clock falls back to just above the last revision', () {
      final tap = DoseTap.at(now, previousRev: ms - 600000);
      expect(tap.rev, ms);
      final safe = tap.clockSafe!;
      expect(safe.rev, ms - 600000 + 1);
      expect(safe.id, isNot(tap.id));
      expect(DoseTap.at(now).clockSafe!.rev, 1);
    });

    test('no fallback when the tap is already just above the last one', () {
      final tap = DoseTap.at(now, previousRev: ms + 5);
      expect(tap.rev, ms + 6);
      expect(tap.clockSafe, isNull);
    });
  });
}
