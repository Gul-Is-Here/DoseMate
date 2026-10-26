import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../core/utils/care_dates.dart';
import '../../core/utils/image_validator.dart';
import '../models/medicine.dart';
import '../models/visit.dart';

/// A user-facing medicine/visit error. [message] is safe to show in the UI.
class CareFailure implements Exception {
  const CareFailure(this.message, {this.code});

  final String message;

  /// Firebase error code, kept for diagnostics (never shown to users).
  final String? code;

  @override
  String toString() => 'CareFailure($code): $message';
}

/// What Log History lists: logs of local days in [from, to), optionally
/// one medicine and one status, newest or oldest first.
class HistoryQuery {
  const HistoryQuery({
    required this.from,
    required this.to,
    this.medicineId,
    this.status,
    this.newestFirst = true,
  });

  final DateTime from;
  final DateTime to;
  final String? medicineId;
  final DoseStatus? status;
  final bool newestFirst;

  /// Query order: day, then scheduled minute, then id, so equal times are
  /// still ordered the same way on every load.
  int compare(DoseLog a, DoseLog b) {
    var c = a.day.compareTo(b.day);
    if (c == 0) c = a.minutes.compareTo(b.minutes);
    if (c == 0) c = a.id.compareTo(b.id);
    return newestFirst ? -c : c;
  }

  @override
  bool operator ==(Object other) =>
      other is HistoryQuery &&
      other.from == from &&
      other.to == to &&
      other.medicineId == medicineId &&
      other.status == status &&
      other.newestFirst == newestFirst;

  @override
  int get hashCode => Object.hash(from, to, medicineId, status, newestFirst);
}

/// One page of history; [fromCache] when Firestore answered offline, so a
/// short page does not prove the end was reached.
typedef HistoryPage = ({List<DoseLog> logs, bool fromCache});

/// How far a write got: confirmed by the server, or saved on this device
/// and waiting to sync (offline or slow network).
enum WriteResult { confirmed, pending }

/// Firestore access for one account's per-profile medicines, visits and
/// dose logs. Every path includes both the account and the profile.
class CareRepository {
  CareRepository(this._firestore, [this._storageOverride]);

  final FirebaseFirestore _firestore;
  final FirebaseStorage? _storageOverride;

  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;

  /// Upper bounds for the live queries; a profile never needs more at once.
  static const medicinesLimit = 200;
  static const visitsLimit = 20;
  static const logsLimit = 1000;

  /// Most visits one calendar week can hold.
  static const rangeVisitsLimit = 100;

  /// Days of dose history kept live (for streaks and recent logs).
  static const historyDays = 30;

  /// How long a save waits for the server before reporting it as pending.
  static Duration confirmTimeout = const Duration(seconds: 8);

  DocumentReference<Map<String, dynamic>> _profile(String uid, String pid) =>
      _firestore.collection('users').doc(uid).collection('profiles').doc(pid);

  CollectionReference<Map<String, dynamic>> _medicines(
    String uid,
    String pid,
  ) => _profile(uid, pid).collection('medicines');

  CollectionReference<Map<String, dynamic>> _visits(String uid, String pid) =>
      _profile(uid, pid).collection('visits');

  CollectionReference<Map<String, dynamic>> _logs(
    String uid,
    String pid, {
    bool shared = false,
  }) => _profile(uid, pid).collection(shared ? 'shareLogs' : 'doseLogs');

  String newMedicineId(String uid, String pid) => _medicines(uid, pid).doc().id;

  String newVisitId(String uid, String pid) => _visits(uid, pid).doc().id;

  // Live queries.

  /// [shared] reads the caregiver-safe copies (no dosage, notes or photos)
  /// of a profile another account shared.
  Stream<List<Medicine>> watchMedicines(
    String uid,
    String pid, {
    bool shared = false,
  }) => _watch(
    _profile(
      uid,
      pid,
    ).collection(shared ? 'shareChecklist' : 'medicines').limit(medicinesLimit),
    Medicine.fromMap,
  );

  /// Scheduled visits from [from] on, soonest first.
  Stream<List<Visit>> watchUpcomingVisits(
    String uid,
    String pid,
    DateTime from,
  ) => _watch(
    _visits(uid, pid)
        .where('status', isEqualTo: VisitStatus.scheduled.name)
        .where('startsAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .orderBy('startsAt')
        .limit(visitsLimit),
    Visit.fromMap,
  );

  /// Scheduled visits starting in [from, to), soonest first. Uses the same
  /// (status, startsAt) index as [watchUpcomingVisits].
  Stream<List<Visit>> watchVisitsBetween(
    String uid,
    String pid,
    DateTime from,
    DateTime to,
  ) => _watch(
    _visits(uid, pid)
        .where('status', isEqualTo: VisitStatus.scheduled.name)
        .where('startsAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('startsAt', isLessThan: Timestamp.fromDate(to))
        .orderBy('startsAt')
        .limit(rangeVisitsLimit),
    Visit.fromMap,
  );

  /// Dose logs of local days in [from, to).
  Stream<List<DoseLog>> watchLogsBetween(
    String uid,
    String pid,
    DateTime from,
    DateTime to, {
    bool shared = false,
  }) => _watchLogs(
    _logs(uid, pid, shared: shared)
        .where('day', isGreaterThanOrEqualTo: CareDates.dayKey(from))
        .where('day', isLessThan: CareDates.dayKey(to))
        .limit(logsLimit),
  );

  /// Dose logs from local day [since] on. [includeCleared] also returns
  /// undone logs (with [DoseLog.isUndone]) so their revisions are known.
  Stream<List<DoseLog>> watchLogs(
    String uid,
    String pid,
    DateTime since, {
    bool shared = false,
    bool includeCleared = false,
  }) => _watchLogs(
    _logs(uid, pid, shared: shared)
        .where('day', isGreaterThanOrEqualTo: CareDates.dayKey(since))
        .limit(logsLimit),
    includeCleared: includeCleared,
  );

  Stream<List<DoseLog>> _watchLogs(
    Query<Map<String, dynamic>> query, {
    bool includeCleared = false,
  }) =>
      _watch(
        query,
        (_, data, {isPending = false}) =>
            DoseLog.fromMap(data, isPending: isPending),
      ).map(
        (logs) =>
            includeCleared ? logs : logs.where((l) => !l.isUndone).toList(),
      );

  Query<Map<String, dynamic>> _history(
    String uid,
    String pid,
    HistoryQuery q, {
    bool shared = false,
  }) {
    var query = _logs(uid, pid, shared: shared)
        .where('day', isGreaterThanOrEqualTo: CareDates.dayKey(q.from))
        .where('day', isLessThan: CareDates.dayKey(q.to));
    if (q.medicineId case final id?) {
      query = query.where('medicineId', isEqualTo: id);
    }
    // Undone logs are kept as records but never listed.
    query = switch (q.status) {
      final status? => query.where('status', isEqualTo: status.name),
      null => query.where(
        'status',
        whereIn: [DoseStatus.taken.name, DoseStatus.skipped.name],
      ),
    };
    final desc = q.newestFirst;
    return query
        .orderBy('day', descending: desc)
        .orderBy('minutes', descending: desc)
        .orderBy(FieldPath.documentId, descending: desc);
  }

  /// The first [limit] logs of [q], live.
  Stream<List<DoseLog>> watchHistoryHead(
    String uid,
    String pid,
    HistoryQuery q,
    int limit, {
    bool shared = false,
  }) => _watchLogs(_history(uid, pid, q, shared: shared).limit(limit));

  /// The [limit] logs of [q] after [after], read once.
  Future<HistoryPage> fetchHistoryPage(
    String uid,
    String pid,
    HistoryQuery q, {
    required DoseLog after,
    required int limit,
    bool shared = false,
  }) async {
    try {
      final snapshot = await _history(uid, pid, q, shared: shared)
          .startAfter([CareDates.dayKey(after.day), after.minutes, after.id])
          .limit(limit)
          .get();
      return (
        logs: [
          for (final doc in snapshot.docs)
            DoseLog.fromMap(
              doc.data(),
              isPending: doc.metadata.hasPendingWrites,
            ),
        ],
        fromCache: snapshot.metadata.isFromCache,
      );
    } on FirebaseException catch (e) {
      throw _failure(_Op.load, e);
    }
  }

  Stream<List<T>> _watch<T>(
    Query<Map<String, dynamic>> query,
    T Function(String id, Map<String, dynamic> data, {bool isPending}) parse,
  ) => query
      // Metadata changes report when a pending write is confirmed.
      .snapshots(includeMetadataChanges: true)
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs)
            parse(doc.id, doc.data(), isPending: doc.metadata.hasPendingWrites),
        ],
      )
      .handleError((Object e) {
        if (e is FirebaseException) throw _failure(_Op.load, e);
        throw e;
      });

  // Medicines.

  /// Creates or replaces [medicine]. [isNew] adds the creation time; retries
  /// of a create that already reached this device must pass false.
  Future<WriteResult> saveMedicine(
    String uid,
    String pid,
    Medicine medicine, {
    required bool isNew,
  }) => _write(
    _Op.save,
    () => _medicines(uid, pid).doc(medicine.id).set({
      ...medicine.toWriteMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (isNew) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)),
  );

  /// Saves [medicine]'s status with the pauses that record it.
  Future<WriteResult> setMedicineStatus(
    String uid,
    String pid,
    Medicine medicine,
  ) => _write(
    _Op.save,
    () => _medicines(uid, pid).doc(medicine.id).update({
      'status': medicine.status.name,
      'pauses': [for (final p in medicine.pauses) p.toMap()],
      'updatedAt': FieldValue.serverTimestamp(),
    }),
  );

  /// Adds [count] doses to the supply atomically, so refills recorded on
  /// two devices both count.
  Future<WriteResult> addSupply(String uid, String pid, String id, int count) =>
      _write(
        _Op.save,
        () => _medicines(uid, pid).doc(id).update({
          'quantity': FieldValue.increment(count),
          'updatedAt': FieldValue.serverTimestamp(),
        }),
      );

  /// Deletes the medicine and the given logs of it in one batch.
  Future<WriteResult> deleteMedicine(
    String uid,
    String pid,
    String id, {
    Iterable<String> logIds = const [],
  }) => _write(_Op.delete, () async {
    // Every log of the medicine, undone ones included, not only those
    // loaded. Offline, the known ids are deleted and the rest stay.
    final ids = {...logIds};
    try {
      final all = await _logs(
        uid,
        pid,
      ).where('medicineId', isEqualTo: id).get().timeout(confirmTimeout);
      ids.addAll(all.docs.map((d) => d.id));
    } on Exception catch (_) {}
    // Logs first, the medicine last, so a failure leaves no orphans.
    final list = ids.toList();
    for (var i = 0; i < list.length; i += 450) {
      final batch = _firestore.batch();
      for (final logId in list.skip(i).take(450)) {
        batch.delete(_logs(uid, pid).doc(logId));
      }
      await batch.commit();
    }
    await _medicines(uid, pid).doc(id).delete();
  });

  // Dose logs.

  /// Records Taken/Skipped for one occurrence as [action]. The log id is
  /// per occurrence, so a dose has one log; its revision makes the server
  /// refuse a write older than the one it has, and accept a retry of the
  /// same write unchanged. The supply is adjusted by the server from the
  /// log (see `applyDoseStock`), so repeated or late writes can't count a
  /// dose twice.
  Future<WriteResult> logDose(
    String uid,
    String pid,
    DoseOccurrence occurrence,
    DoseStatus status, {
    required DoseTap action,
    String? note,
    bool replacesLegacyTaken = false,
  }) => _dose(
    action,
    (action) => _logs(uid, pid).doc(occurrence.logId).set({
      ..._actionFields(
        occurrence.medicine.id,
        occurrence.day,
        occurrence.minutes,
        status.name,
        action,
      ),
      if (replacesLegacyTaken) ..._legacyTaken,
      'note': note != null && note.isNotEmpty ? note : FieldValue.delete(),
      'medicineName': _clip(occurrence.medicine.name),
      'dosage': occurrence.medicine.dosage.isNotEmpty
          ? _clip(occurrence.medicine.dosage)
          : FieldValue.delete(),
    }, SetOptions(merge: true)),
  );

  static String _clip(String s) => s.length <= 100 ? s : s.substring(0, 100);

  /// Undoes [log] as [action]. The log is kept as an undone record, so an
  /// older Taken from another device can't bring it back.
  Future<WriteResult> undoDose(
    String uid,
    String pid,
    DoseLog log, {
    required DoseTap action,
  }) => _dose(
    action,
    (action) => _logs(uid, pid).doc(log.id).set({
      ..._actionFields(
        log.medicineId,
        log.day,
        log.minutes,
        DoseLog.cleared,
        action,
      ),
      'note': FieldValue.delete(),
    }, SetOptions(merge: true)),
  );

  /// Records that the dose [logId] is snoozed until [until], so the
  /// server's "not logged yet" follow-up waits for it.
  Future<WriteResult> snoozeDose(
    String uid,
    String pid,
    String logId,
    DateTime until,
  ) => _write(
    _Op.dose,
    () => _profile(uid, pid).collection('doseSnoozes').doc(logId).set({
      'until': Timestamp.fromDate(until),
    }),
  );

  /// Writes a dose tap. Refused, it's retried once with
  /// [DoseTap.clockSafe]: a device whose clock runs fast still logs, while
  /// a newer tap from another device still wins.
  Future<WriteResult> _dose(
    DoseTap action,
    Future<void> Function(DoseTap action) write,
  ) async {
    try {
      return await _write(_Op.dose, () => write(action));
    } on CareFailure catch (e) {
      final retry = action.clockSafe;
      if (e.code != 'permission-denied' || retry == null) rethrow;
      return _write(_Op.dose, () => write(retry));
    }
  }

  /// Marks the first write over a Taken log from an app version without
  /// revisions, which took its dose from the supply itself: the server
  /// counts it as already applied, whatever order its events run in.
  static const _legacyTaken = {'legacyBase': 'taken'};

  static Map<String, Object> _actionFields(
    String medicineId,
    DateTime day,
    int minutes,
    String status,
    DoseTap action,
  ) => {
    'medicineId': medicineId,
    'day': CareDates.dayKey(day),
    'minutes': minutes,
    'status': status,
    'rev': action.rev,
    'actionId': action.id,
    'actedAt': Timestamp.fromDate(action.at),
    // Offset of the device's zone at the tap, for reading history later.
    'utcOffset': action.at.timeZoneOffset.inMinutes,
    'loggedAt': FieldValue.serverTimestamp(),
  };

  // Visits.

  Future<WriteResult> saveVisit(
    String uid,
    String pid,
    Visit visit, {
    required bool isNew,
  }) => _write(
    _Op.save,
    () => _visits(uid, pid).doc(visit.id).set({
      ...visit.toWriteMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (isNew) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)),
  );

  Future<WriteResult> cancelVisit(String uid, String pid, String id) => _write(
    _Op.save,
    () => _visits(uid, pid).doc(id).update({
      'status': VisitStatus.cancelled.name,
      'updatedAt': FieldValue.serverTimestamp(),
    }),
  );

  Future<WriteResult> deleteVisit(String uid, String pid, String id) =>
      _write(_Op.delete, () => _visits(uid, pid).doc(id).delete());

  // Photos.

  /// Uploads a medicine's reference photo to a fresh path.
  Future<({String url, String path})> uploadMedicinePhoto(
    String uid,
    String pid,
    String medicineId,
    File file,
  ) async {
    final problem = ImageValidator.validate(file);
    if (problem != null) throw CareFailure(problem, code: 'invalid-image');
    final format = ImageValidator.detect(file)!;
    try {
      final path =
          'users/$uid/profiles/$pid/medicines/$medicineId/'
          'photo_${DateTime.now().millisecondsSinceEpoch}.${format.extension}';
      final ref = _storage.ref(path);
      await ref.putFile(
        file,
        SettableMetadata(contentType: format.contentType),
      );
      return (url: await ref.getDownloadURL(), path: path);
    } on FirebaseException catch (e) {
      throw _failure(_Op.upload, e);
    }
  }

  /// Best effort: a leftover file is harmless.
  Future<void> deletePhoto(String path) async {
    try {
      await _storage.ref(path).delete();
    } on FirebaseException {
      // Already gone or offline.
    }
  }

  /// Runs a write and waits for the server. Offline, Firestore keeps the
  /// write on this device and syncs it later, so a write that isn't
  /// confirmed in time is reported as pending instead of failed.
  Future<WriteResult> _write(_Op op, Future<void> Function() action) async {
    final Future<void> write;
    try {
      write = action();
    } on FirebaseException catch (e) {
      throw _failure(op, e);
    }
    try {
      await write.timeout(confirmTimeout);
      return WriteResult.confirmed;
    } on TimeoutException {
      // Still queued; a later rejection shows up through the listeners.
      write.catchError((Object _) {}).ignore();
      return WriteResult.pending;
    } on FirebaseException catch (e) {
      throw _failure(op, e);
    }
  }

  static CareFailure _failure(_Op op, FirebaseException e) {
    // Codes and plugin names only; no user data.
    if (kDebugMode) debugPrint('Care ${op.name} ${e.plugin} error: ${e.code}');
    return CareFailure(_messageFor(op, e.code), code: e.code);
  }

  static String _messageFor(_Op op, String code) => switch (code) {
    'unavailable' || 'retry-limit-exceeded' =>
      "You're offline. Check your connection and try again.",
    'permission-denied' when op == _Op.dose =>
      'This dose was updated on another device. Showing the latest.',
    'permission-denied' || 'unauthorized' || 'unauthenticated' =>
      "You don't have permission to change this. Sign in again and retry.",
    'not-found' => 'This record no longer exists.',
    'failed-precondition' => 'This list needs a database update before it can load. Please try again later.',
    _ => switch (op) {
      _Op.load => 'Could not load your schedule. Please try again.',
      _Op.save || _Op.dose => 'Could not save your changes. Please try again.',
      _Op.delete => 'Could not delete this. Please try again.',
      _Op.upload => 'Could not upload your photo. Please try again.',
    },
  };
}

enum _Op { load, save, dose, delete, upload }
