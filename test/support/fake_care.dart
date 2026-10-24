import 'dart:async';
import 'dart:io';

import 'package:dosemate/core/utils/care_dates.dart';
import 'package:dosemate/data/models/medicine.dart';
import 'package:dosemate/data/models/visit.dart';
import 'package:dosemate/data/repositories/care_repository.dart';
import 'package:dosemate/data/services/care_service.dart';
import 'package:dosemate/data/services/profile_service.dart';
import 'package:get/get.dart';

/// In-memory stand-in for the per-profile Firestore collections, with live
/// streams that apply the same filters as the real queries.
class FakeCare implements CareRepository {
  /// "uid/profileId" → id → record.
  final medicines = <String, Map<String, Medicine>>{};
  final visits = <String, Map<String, Visit>>{};
  final logs = <String, Map<String, DoseLog>>{};
  final _streams = <StreamController<void>>[];
  int _ids = 0;
  int writes = 0;
  int creates = 0;

  /// Thrown by the next write (then cleared), e.g. a permission error.
  CareFailure? failNext;

  /// Writes report pending, as when offline.
  bool offline = false;

  /// Makes new listeners fail, as with a permission or index error.
  CareFailure? loadFailure;

  /// Holds writes until completed, to test repeated taps.
  Completer<void>? gate;

  /// Listeners currently attached.
  int get listeners => _streams.where((c) => c.hasListener).length;

  Map<String, Medicine> medicinesOf(String uid, String pid) =>
      medicines.putIfAbsent('$uid/$pid', () => {});
  Map<String, Visit> visitsOf(String uid, String pid) =>
      visits.putIfAbsent('$uid/$pid', () => {});
  Map<String, DoseLog> logsOf(String uid, String pid) =>
      logs.putIfAbsent('$uid/$pid', () => {});

  void _emit() {
    for (final c in _streams) {
      if (c.hasListener) c.add(null);
    }
  }

  Stream<T> _live<T>(T Function() read) {
    if (loadFailure case final error?) return Stream.error(error);
    late final StreamController<void> c;
    c = StreamController<void>(
      onListen: () => c.add(null),
      onCancel: () => _streams.remove(c),
    );
    _streams.add(c);
    return c.stream.map((_) => read());
  }

  Future<WriteResult> _write(void Function() apply) async {
    if (failNext case final error?) {
      failNext = null;
      throw error;
    }
    await gate?.future;
    writes++;
    apply();
    _emit();
    return offline ? WriteResult.pending : WriteResult.confirmed;
  }

  @override
  String newMedicineId(String uid, String pid) => 'med-${++_ids}';

  @override
  String newVisitId(String uid, String pid) => 'visit-${++_ids}';

  @override
  Stream<List<Medicine>> watchMedicines(String uid, String pid) =>
      _live(() => medicinesOf(uid, pid).values.toList());

  @override
  Stream<List<Visit>> watchUpcomingVisits(
    String uid,
    String pid,
    DateTime from,
  ) => _live(
    () =>
        visitsOf(uid, pid).values
            .where(
              (v) =>
                  v.status == VisitStatus.scheduled &&
                  !v.startsAt.isBefore(from),
            )
            .toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt)),
  );

  @override
  Stream<List<DoseLog>> watchLogs(String uid, String pid, DateTime since) =>
      _live(
        () => logsOf(
          uid,
          pid,
        ).values.where((l) => !l.day.isBefore(since)).toList(),
      );

  @override
  Future<WriteResult> saveMedicine(
    String uid,
    String pid,
    Medicine medicine, {
    required bool isNew,
  }) => _write(() {
    if (isNew) creates++;
    medicinesOf(uid, pid)[medicine.id] = medicine;
  });

  Future<WriteResult> _updateMedicine(
    String uid,
    String pid,
    String id,
    Medicine Function(Medicine) change,
  ) => _write(() {
    final m = medicinesOf(uid, pid)[id];
    if (m == null) throw const CareFailure('This record no longer exists.');
    medicinesOf(uid, pid)[id] = change(m);
  });

  @override
  Future<WriteResult> setMedicineStatus(
    String uid,
    String pid,
    String id,
    MedicineStatus status,
  ) => _updateMedicine(uid, pid, id, (m) => m.copyWith(status: status));

  @override
  Future<WriteResult> addSupply(String uid, String pid, String id, int count) =>
      _updateMedicine(
        uid,
        pid,
        id,
        (m) => m.copyWith(quantity: m.quantity + count),
      );

  @override
  Future<WriteResult> deleteMedicine(
    String uid,
    String pid,
    String id, {
    Iterable<String> logIds = const [],
  }) => _write(() {
    medicinesOf(uid, pid).remove(id);
    for (final l in logIds) {
      logsOf(uid, pid).remove(l);
    }
  });

  @override
  Future<WriteResult> logDose(
    String uid,
    String pid,
    DoseOccurrence occurrence,
    DoseStatus status, {
    int supplyChange = 0,
  }) => _write(() {
    logsOf(uid, pid)[occurrence.logId] = DoseLog(
      medicineId: occurrence.medicine.id,
      day: occurrence.day,
      minutes: occurrence.minutes,
      status: status,
      loggedAt: CareDates.at(occurrence.day, occurrence.minutes),
    );
    final m = medicinesOf(uid, pid)[occurrence.medicine.id];
    if (m != null && supplyChange != 0) {
      medicinesOf(uid, pid)[m.id] = m.copyWith(
        quantity: m.quantity + supplyChange,
      );
    }
  });

  @override
  Future<WriteResult> undoDose(
    String uid,
    String pid,
    DoseLog log, {
    int supplyChange = 0,
  }) => _write(() {
    logsOf(uid, pid).remove(log.id);
    final m = medicinesOf(uid, pid)[log.medicineId];
    if (m != null && supplyChange != 0) {
      medicinesOf(uid, pid)[m.id] = m.copyWith(
        quantity: m.quantity + supplyChange,
      );
    }
  });

  @override
  Future<WriteResult> saveVisit(
    String uid,
    String pid,
    Visit visit, {
    required bool isNew,
  }) => _write(() {
    if (isNew) creates++;
    visitsOf(uid, pid)[visit.id] = visit;
  });

  @override
  Future<WriteResult> cancelVisit(String uid, String pid, String id) =>
      _write(() {
        final v = visitsOf(uid, pid)[id]!;
        visitsOf(uid, pid)[id] = Visit(
          id: v.id,
          title: v.title,
          category: v.category,
          startsAt: v.startsAt,
          status: VisitStatus.cancelled,
        );
      });

  @override
  Future<WriteResult> deleteVisit(String uid, String pid, String id) =>
      _write(() => visitsOf(uid, pid).remove(id));

  @override
  Future<({String url, String path})> uploadMedicinePhoto(
    String uid,
    String pid,
    String medicineId,
    File file,
  ) async =>
      (url: 'https://storage.example/$medicineId', path: 'p/$medicineId');

  @override
  Future<void> deletePhoto(String path) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Registers a [CareService] over [repository] as the app does over
/// Firestore. [now] fixes the clock.
CareService putCare(
  ProfileService profiles,
  FakeCare repository, {
  DateTime Function()? now,
}) =>
    Get.put(CareService(repository, profiles, clock: now, autoRollOver: false));

/// Fixed "now" for screen tests: Saturday 24 Oct 2026, 2:00 PM.
DateTime fixedNow() => DateTime(2026, 10, 24, 14);

/// Myself: Amoxicillin (8 AM, 8 PM; low supply), Vitamin D3 (9 AM, taken)
/// and a dentist visit on Thursday. Ruth/Arthur (p1): Lisinopril only.
void seedCare(FakeCare c, {String uid = 'uid-1'}) {
  final today = DateTime(2026, 10, 24);
  final amox = Medicine(
    id: 'amox',
    name: 'Amoxicillin',
    dosage: '500mg - 1 capsule',
    notes: 'Take with dinner & full glass of water',
    frequency: Frequency.multipleDaily,
    doseMinutes: const [8 * 60, 20 * 60],
    startDate: today,
    courseDays: 7,
    quantity: 3,
  );
  final vitamin = Medicine(
    id: 'vitd',
    name: 'Vitamin D3',
    dosage: '1000 IU',
    frequency: Frequency.onceDaily,
    doseMinutes: const [9 * 60],
    startDate: DateTime(2026, 10, 1),
    courseDays: 90,
    quantity: 38,
  );
  c.medicinesOf(uid, 'self')
    ..[amox.id] = amox
    ..[vitamin.id] = vitamin;
  final taken = DoseOccurrence(vitamin, today, 9 * 60);
  c.logsOf(uid, 'self')[taken.logId] = DoseLog(
    medicineId: vitamin.id,
    day: today,
    minutes: 9 * 60,
    status: DoseStatus.taken,
    loggedAt: DateTime(2026, 10, 24, 9, 8),
  );
  c.visitsOf(uid, 'self')['dentist'] = Visit(
    id: 'dentist',
    title: 'Dentist Checkup & Cleaning',
    category: 'Dentist',
    startsAt: DateTime(2026, 10, 29, 15, 30),
    doctor: 'Dr. Robert Sterling',
    clinic: 'St. Jude Dental Clinic',
    phone: '(555) 234-5678',
  );
  c.medicinesOf(uid, 'p1')['lis'] = Medicine(
    id: 'lis',
    name: 'Lisinopril',
    frequency: Frequency.onceDaily,
    doseMinutes: const [7 * 60],
    startDate: today,
    courseDays: 30,
    quantity: 30,
  );
}
