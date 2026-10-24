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

  CollectionReference<Map<String, dynamic>> _logs(String uid, String pid) =>
      _profile(uid, pid).collection('doseLogs');

  String newMedicineId(String uid, String pid) => _medicines(uid, pid).doc().id;

  String newVisitId(String uid, String pid) => _visits(uid, pid).doc().id;

  // Live queries.

  Stream<List<Medicine>> watchMedicines(String uid, String pid) =>
      _watch(_medicines(uid, pid).limit(medicinesLimit), Medicine.fromMap);

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

  /// Dose logs from local day [since] on.
  Stream<List<DoseLog>> watchLogs(String uid, String pid, DateTime since) =>
      _watch(
        _logs(uid, pid)
            .where('day', isGreaterThanOrEqualTo: CareDates.dayKey(since))
            .limit(logsLimit),
        (_, data, {isPending = false}) =>
            DoseLog.fromMap(data, isPending: isPending),
      );

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

  Future<WriteResult> setMedicineStatus(
    String uid,
    String pid,
    String id,
    MedicineStatus status,
  ) => _write(
    _Op.save,
    () => _medicines(uid, pid).doc(id).update({
      'status': status.name,
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
  }) => _write(_Op.delete, () {
    final batch = _firestore.batch()..delete(_medicines(uid, pid).doc(id));
    for (final logId in logIds.take(400)) {
      batch.delete(_logs(uid, pid).doc(logId));
    }
    return batch.commit();
  });

  // Dose logs.

  /// Records Taken/Skipped for one occurrence and adjusts the supply in the
  /// same batch: [supplyChange] is -1 when a dose becomes taken, +1 when a
  /// taken dose is changed or undone. The log id is per occurrence, so a
  /// repeated write can't create a second log.
  Future<WriteResult> logDose(
    String uid,
    String pid,
    DoseOccurrence occurrence,
    DoseStatus status, {
    int supplyChange = 0,
  }) => _write(_Op.save, () {
    final batch = _firestore.batch()
      ..set(_logs(uid, pid).doc(occurrence.logId), {
        'medicineId': occurrence.medicine.id,
        'day': CareDates.dayKey(occurrence.day),
        'minutes': occurrence.minutes,
        'status': status.name,
        'loggedAt': FieldValue.serverTimestamp(),
      });
    if (supplyChange != 0) {
      batch.update(_medicines(uid, pid).doc(occurrence.medicine.id), {
        'quantity': FieldValue.increment(supplyChange),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    return batch.commit();
  });

  Future<WriteResult> undoDose(
    String uid,
    String pid,
    DoseLog log, {
    int supplyChange = 0,
  }) => _write(_Op.save, () {
    final batch = _firestore.batch()..delete(_logs(uid, pid).doc(log.id));
    if (supplyChange != 0) {
      batch.update(_medicines(uid, pid).doc(log.medicineId), {
        'quantity': FieldValue.increment(supplyChange),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    return batch.commit();
  });

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
    'permission-denied' || 'unauthorized' || 'unauthenticated' =>
      "You don't have permission to change this. Sign in again and retry.",
    'not-found' => 'This record no longer exists.',
    'failed-precondition' => 'This list needs a database update before it can load. Please try again later.',
    _ => switch (op) {
      _Op.load => 'Could not load your schedule. Please try again.',
      _Op.save => 'Could not save your changes. Please try again.',
      _Op.delete => 'Could not delete this. Please try again.',
      _Op.upload => 'Could not upload your photo. Please try again.',
    },
  };
}

enum _Op { load, save, delete, upload }
