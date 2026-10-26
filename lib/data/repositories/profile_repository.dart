import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../core/utils/image_validator.dart';
import '../models/user_profile.dart';

/// A user-facing profile error. [message] is safe to show in the UI.
class ProfileFailure implements Exception {
  const ProfileFailure(this.message, {this.code});

  final String message;

  /// Firebase error code, kept for diagnostics (never shown to users).
  final String? code;

  @override
  String toString() => 'ProfileFailure($code): $message';
}

/// An uploaded profile photo.
typedef ProfilePhoto = ({String url, String path});

enum _Operation { load, save, upload }

class ProfileRepository {
  ProfileRepository(this._firestore, this._storage);

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  /// Personal fields that lived on `users/{uid}` before profiles existed.
  static const legacyFields = [
    'profileFor',
    'fullName',
    'relationship',
    'dateOfBirth',
    'emergencyContactName',
    'emergencyContactPhone',
    'photoUrl',
    'photoPath',
    'profileCompleted',
  ];

  /// Deterministic id for a legacy loved-one profile, so migrating twice can
  /// never create a duplicate.
  static const migratedProfileId = 'migrated';

  DocumentReference<Map<String, dynamic>> _account(String uid) =>
      _firestore.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> _profiles(String uid) =>
      _account(uid).collection('profiles');

  /// A fresh id for a profile that hasn't been saved yet.
  String newProfileId(String uid) => _profiles(uid).doc().id;

  /// Live list of the account's profiles. Errors arrive as [ProfileFailure].
  /// Profiles other accounts shared with [uid], live.
  Stream<List<UserProfile>> watchSharedProfiles(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .collection('sharedProfiles')
      .snapshots()
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs) UserProfile.shared(doc.data()),
        ],
      )
      .handleError((Object e) {
        if (e is FirebaseException) throw _failure(_Operation.load, e);
        throw e;
      });

  Stream<List<UserProfile>> watchProfiles(String uid) => _profiles(uid)
      .snapshots()
      .map(
        (snapshot) => [
          for (final doc in snapshot.docs)
            UserProfile.fromMap(doc.id, doc.data()),
        ],
      )
      .handleError((Object e) {
        if (e is FirebaseException) throw _failure(_Operation.load, e);
        throw e;
      });

  /// Falls back to the cached copy when offline.
  Future<AccountState> fetchAccount(String uid) =>
      _guard(_Operation.load, () async {
        DocumentSnapshot<Map<String, dynamic>> snapshot;
        try {
          snapshot = await _account(uid).get();
        } on FirebaseException catch (e) {
          if (e.code != 'unavailable') rethrow;
          snapshot = await _account(uid)
              .get(const GetOptions(source: Source.cache));
        }
        return AccountState.fromMap(snapshot.data());
      });

  /// Moves a pre-profiles personal profile from `users/{uid}` into
  /// `users/{uid}/profiles` in one transaction, so data is never lost or
  /// half-moved. A legacy "for myself" profile becomes Myself; a legacy
  /// "loved one" profile becomes a Parent/Spouse/Other profile and Myself is
  /// created from [selfName]. Does nothing when there is nothing to migrate.
  Future<void> migrateLegacyProfile(String uid, {required String selfName}) =>
      _guard(
        _Operation.load,
        () => _firestore.runTransaction((transaction) async {
          final accountRef = _account(uid);
          final selfRef = _profiles(uid).doc(UserProfile.selfId);
          final migratedRef = _profiles(uid).doc(migratedProfileId);

          // Firestore transactions need every read before any write.
          final legacy = (await transaction.get(accountRef)).data();
          if (legacy == null || !legacy.containsKey('fullName')) return;
          final selfExists = (await transaction.get(selfRef)).exists;
          final migratedExists = (await transaction.get(migratedRef)).exists;

          final now = FieldValue.serverTimestamp();
          final personal = {
            for (final key in legacyFields)
              if (legacy.containsKey(key) &&
                  key != 'profileFor' &&
                  key != 'profileCompleted')
                key: legacy[key],
          };
          final createdAt = legacy['createdAt'] ?? now;

          if (legacy['profileFor'] == 'caregiver') {
            if (!migratedExists) {
              transaction.set(migratedRef, {
                ...personal,
                'type': ProfileType.fromRelationship(
                  legacy['relationship'] as String?,
                ).name,
                'createdAt': createdAt,
                'updatedAt': now,
              });
            }
            if (!selfExists) {
              transaction.set(selfRef, {
                'type': ProfileType.self.name,
                'fullName': selfName,
                'createdAt': now,
                'updatedAt': now,
              });
            }
          } else if (!selfExists) {
            transaction.set(selfRef, {
              ...personal..remove('relationship'),
              'type': ProfileType.self.name,
              'createdAt': createdAt,
              'updatedAt': now,
            });
          }

          transaction.update(accountRef, {
            for (final key in legacyFields) key: FieldValue.delete(),
            'setupCompleted': legacy['profileCompleted'] as bool? ?? false,
            'profilesMigratedAt': now,
            'updatedAt': now,
          });
        }),
      );

  /// Saves one profile's editable fields; other profiles and unrelated
  /// fields are never touched. With [markSetupComplete], also records that
  /// setup is done and makes sure a Myself profile exists (named [selfName]).
  Future<void> saveProfile(
    String uid,
    UserProfile profile, {
    bool markSetupComplete = false,
    String? selfName,
  }) => _guard(
    _Operation.save,
    () => _firestore.runTransaction((transaction) async {
      final ref = _profiles(uid).doc(profile.id);
      final selfRef = _profiles(uid).doc(UserProfile.selfId);
      final exists = (await transaction.get(ref)).exists;
      final needsSelf =
          markSetupComplete &&
          !profile.isSelf &&
          selfName != null &&
          !(await transaction.get(selfRef)).exists;

      final now = FieldValue.serverTimestamp();
      transaction.set(ref, {
        ...profile.toWriteMap(),
        'updatedAt': now,
        if (!exists) 'createdAt': now,
      }, SetOptions(merge: true));
      if (needsSelf) {
        transaction.set(selfRef, {
          'type': ProfileType.self.name,
          'fullName': selfName,
          'createdAt': now,
          'updatedAt': now,
        });
      }
      if (markSetupComplete) {
        transaction.set(_account(uid), {
          'setupCompleted': true,
          'updatedAt': now,
        }, SetOptions(merge: true));
      }
    }),
  );

  /// Remembers the active profile across restarts and devices. Not a
  /// transaction, so it also works offline and syncs later.
  Future<void> setActiveProfile(String uid, String profileId) => _guard(
    _Operation.save,
    () => _account(uid).set({
      'activeProfileId': profileId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)),
  );

  /// Uploads to a new path each time so cached images never go stale.
  /// [onProgress] receives values from 0 to 1.
  Future<ProfilePhoto> uploadPhoto(
    String uid,
    String profileId,
    File file, {
    void Function(double progress)? onProgress,
  }) async {
    final problem = ImageValidator.validate(file);
    if (problem != null) throw ProfileFailure(problem, code: 'invalid-image');
    final format = ImageValidator.detect(file)!;
    return _guard(_Operation.upload, () async {
      final path =
          'users/$uid/profiles/$profileId/avatar_${DateTime.now().millisecondsSinceEpoch}.${format.extension}';
      final ref = _storage.ref(path);
      final task = ref.putFile(
        file,
        SettableMetadata(contentType: format.contentType),
      );
      final progress = task.snapshotEvents.listen((s) {
        if (s.totalBytes > 0) {
          onProgress?.call(s.bytesTransferred / s.totalBytes);
        }
      }, onError: (_) {});
      try {
        await task;
      } finally {
        await progress.cancel();
      }
      return (url: await ref.getDownloadURL(), path: path);
    });
  }

  /// Best effort: a leftover file is harmless, so failures are ignored.
  Future<void> deletePhoto(String path) async {
    try {
      await _storage.ref(path).delete();
    } on FirebaseException {
      // Already gone or offline.
    }
  }

  Future<T> _guard<T>(_Operation operation, Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseException catch (e) {
      throw _failure(operation, e);
    }
  }

  static ProfileFailure _failure(_Operation operation, FirebaseException e) {
    // Codes and plugin names only; no user data or tokens.
    if (kDebugMode) {
      debugPrint('Profile ${operation.name} ${e.plugin} error: ${e.code}');
    }
    return ProfileFailure(code: e.code, _messageFor(operation, e.code));
  }

  static String _messageFor(_Operation operation, String code) =>
      switch (code) {
        'unavailable' || 'retry-limit-exceeded' =>
          "You're offline. Check your connection and try again.",
        'permission-denied' || 'unauthorized' || 'unauthenticated' =>
          'Your session has expired. Sign in again and retry.',
        'quota-exceeded' =>
          'Storage is full right now. Please try again later.',
        _ => switch (operation) {
          _Operation.load => 'Could not load your profile. Please try again.',
          _Operation.save => 'Could not save your profile. Please try again.',
          _Operation.upload => 'Could not upload your photo. Please try again.',
        },
      };
}
