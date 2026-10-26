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

  /// Holds the first snapshot of new listeners until completed, as on a
  /// slow connection with nothing cached.
  Completer<void>? loadGate;

  /// Listeners currently attached.
  int get listeners => _streams.where((c) => c.hasListener).length;

  Map<String, Medicine> medicinesOf(String uid, String pid) =>
      medicines.putIfAbsent('$uid/$pid', () => {});
  Map<String, Visit> visitsOf(String uid, String pid) =>
      visits.putIfAbsent('$uid/$pid', () => {});
  Map<String, DoseLog> logsOf(String uid, String pid) =>
      logs.putIfAbsent('$uid/$pid', () => {});

  /// Pushes the current records to every listener (after editing them
  /// directly).
  void emit() => _emit();

  void _emit() {
    for (final c in _streams) {
      if (c.hasListener) c.add(null);
    }
  }

  Stream<T> _live<T>(T Function() read) {
    if (loadFailure case final error?) return Stream.error(error);
    late final StreamController<void> c;
    final held = loadGate?.future;
    c = StreamController<void>(
      onListen: () => held == null
          ? c.add(null)
          : held.then((_) {
              if (c.hasListener) c.add(null);
            }),
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

  /// Log ids written with the legacy Taken marker.
  final legacyMarked = <String>[];

  /// Log ids the app asked to delete with a medicine.
  final deletedLogIds = <String>[];

  /// Snoozes recorded for the server: "uid/pid/logId" → until.
  final snoozes = <String, DateTime>{};

  @override
  Future<WriteResult> snoozeDose(
    String uid,
    String pid,
    String logId,
    DateTime until,
  ) => _write(() => snoozes['$uid/$pid/$logId'] = until);

  @override
  String newMedicineId(String uid, String pid) => 'med-${++_ids}';

  @override
  String newVisitId(String uid, String pid) => 'visit-${++_ids}';

  @override
  Stream<List<Medicine>> watchMedicines(
    String uid,
    String pid, {
    bool shared = false,
  }) => _live(() => medicinesOf(uid, pid).values.toList());

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

  List<DoseLog> _history(String uid, String pid, HistoryQuery q) =>
      logsOf(uid, pid).values
          .where(
            (l) =>
                !l.day.isBefore(q.from) &&
                l.day.isBefore(q.to) &&
                (q.medicineId == null || l.medicineId == q.medicineId) &&
                (q.status == null || l.status == q.status),
          )
          .toList()
        ..sort(q.compare);

  /// History reads so far: head listeners opened and pages fetched.
  int historyHeads = 0;
  int historyPages = 0;

  /// Makes the next page fetch fail (then cleared).
  CareFailure? failNextPage;

  /// Pages report coming from the cache, as offline.
  bool pagesFromCache = false;

  /// Holds page fetches until completed, to test repeated triggers.
  Completer<void>? pageGate;

  @override
  Stream<List<DoseLog>> watchHistoryHead(
    String uid,
    String pid,
    HistoryQuery q,
    int limit, {
    bool shared = false,
  }) {
    historyHeads++;
    return _live(() => _history(uid, pid, q).take(limit).toList());
  }

  @override
  Future<HistoryPage> fetchHistoryPage(
    String uid,
    String pid,
    HistoryQuery q, {
    required DoseLog after,
    required int limit,
    bool shared = false,
  }) async {
    historyPages++;
    await pageGate?.future;
    if (failNextPage case final e?) {
      failNextPage = null;
      throw e;
    }
    return (
      logs: _history(
        uid,
        pid,
        q,
      ).where((l) => q.compare(l, after) > 0).take(limit).toList(),
      fromCache: pagesFromCache,
    );
  }

  /// Range queries opened so far, to check listener reuse.
  int rangeQueries = 0;

  @override
  Stream<List<Visit>> watchVisitsBetween(
    String uid,
    String pid,
    DateTime from,
    DateTime to,
  ) {
    rangeQueries++;
    return _live(
      () =>
          visitsOf(uid, pid).values
              .where(
                (v) =>
                    v.status == VisitStatus.scheduled &&
                    !v.startsAt.isBefore(from) &&
                    v.startsAt.isBefore(to),
              )
              .toList()
            ..sort((a, b) => a.startsAt.compareTo(b.startsAt)),
    );
  }

  @override
  Stream<List<DoseLog>> watchLogsBetween(
    String uid,
    String pid,
    DateTime from,
    DateTime to, {
    bool shared = false,
  }) {
    rangeQueries++;
    return _live(
      () => logsOf(uid, pid).values
          .where((l) => !l.day.isBefore(from) && l.day.isBefore(to))
          .toList(),
    );
  }

  @override
  Stream<List<DoseLog>> watchLogs(
    String uid,
    String pid,
    DateTime since, {
    bool shared = false,
    bool includeCleared = false,
  }) => _live(
    () => [
      ...logsOf(uid, pid).values,
      if (includeCleared) ...undoneOf(uid, pid).values,
    ].where((l) => !l.day.isBefore(since)).toList(),
  );

  /// Undone logs, kept for their revision as on the server.
  final undone = <String, Map<String, DoseLog>>{};
  Map<String, DoseLog> undoneOf(String uid, String pid) =>
      undone.putIfAbsent('$uid/$pid', () => {});

  /// What each log has taken from the supply, as `applyDoseStock` records.
  final stockApplied = <String, int>{};

  /// Taps written, in order, as (log id, tap id, revision).
  final taps = <(String, String, int)>[];

  int _revOf(String uid, String pid, String id) =>
      (logsOf(uid, pid)[id] ?? undoneOf(uid, pid)[id])?.rev ?? 0;

  /// The rules: only a newer revision, or a retry of the same tap.
  void _checkRev(String uid, String pid, String id, DoseTap tap) {
    final current = _revOf(uid, pid, id);
    final same = taps.any(
      (t) => t.$1 == id && t.$2 == tap.id && t.$3 == tap.rev,
    );
    if (tap.rev > current || (tap.rev == current && same)) return;
    throw const CareFailure(
      'This dose was updated on another device. Showing the latest.',
      code: 'permission-denied',
    );
  }

  /// The server's applyDoseStock, run right after each write.
  void _applyStock(String uid, String pid, String logId, String medicineId) {
    final key = '$uid/$pid/$logId';
    final applied = stockApplied[key] ?? 0;
    final m = medicinesOf(uid, pid)[medicineId];
    final taken = logsOf(uid, pid)[logId]?.status == DoseStatus.taken;
    final want = taken && (applied == -1 || (m?.quantity ?? 0) > 0) ? -1 : 0;
    if (want == applied) return;
    if (m != null) {
      medicinesOf(uid, pid)[m.id] = m.copyWith(
        quantity: m.quantity + want - applied,
      );
    }
    stockApplied[key] = want;
  }

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
    Medicine medicine,
  ) => _updateMedicine(uid, pid, medicine.id, (_) => medicine);

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
    // Like the real query: every log of the medicine, undone ones too.
    logsOf(uid, pid).removeWhere((_, l) => l.medicineId == id);
    undoneOf(uid, pid).removeWhere((_, l) => l.medicineId == id);
    for (final l in logIds) {
      logsOf(uid, pid).remove(l);
      undoneOf(uid, pid).remove(l);
    }
    deletedLogIds.addAll(logIds);
  });

  @override
  Future<WriteResult> logDose(
    String uid,
    String pid,
    DoseOccurrence occurrence,
    DoseStatus status, {
    required DoseTap action,
    String? note,
    bool replacesLegacyTaken = false,
  }) => _write(() {
    final id = occurrence.logId;
    if (replacesLegacyTaken) legacyMarked.add(id);
    _checkRev(uid, pid, id, action);
    taps.add((id, action.id, action.rev));
    undoneOf(uid, pid).remove(id);
    logsOf(uid, pid)[id] = DoseLog(
      medicineId: occurrence.medicine.id,
      day: occurrence.day,
      minutes: occurrence.minutes,
      status: status,
      loggedAt: CareDates.at(occurrence.day, occurrence.minutes),
      note: note,
      medicineName: occurrence.medicine.name,
      dosage: occurrence.medicine.dosage.isEmpty
          ? null
          : occurrence.medicine.dosage,
      rev: action.rev,
    );
    _applyStock(uid, pid, id, occurrence.medicine.id);
  });

  @override
  Future<WriteResult> undoDose(
    String uid,
    String pid,
    DoseLog log, {
    required DoseTap action,
  }) => _write(() {
    _checkRev(uid, pid, log.id, action);
    taps.add((log.id, action.id, action.rev));
    logsOf(uid, pid).remove(log.id);
    undoneOf(uid, pid)[log.id] = DoseLog(
      medicineId: log.medicineId,
      day: log.day,
      minutes: log.minutes,
      status: DoseStatus.skipped,
      rev: action.rev,
      isUndone: true,
    );
    _applyStock(uid, pid, log.id, log.medicineId);
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
