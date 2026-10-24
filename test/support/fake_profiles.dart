import 'dart:async';
import 'dart:io';

import 'package:dosemate/data/models/user_profile.dart';
import 'package:dosemate/data/repositories/profile_repository.dart';

/// In-memory stand-in for the Firestore + Storage profile data, with a live
/// profiles stream per account like the real listener.
class FakeProfiles implements ProfileRepository {
  /// uid → profileId → profile.
  final store = <String, Map<String, UserProfile>>{};
  final accounts = <String, AccountState>{};
  final uploads = <String>[];
  final deleted = <String>[];
  final migrations = <String>[];
  final _streams = <String, StreamController<List<UserProfile>>>{};
  int _ids = 0;

  ProfileFailure? readFailure;
  ProfileFailure? saveFailure;
  ProfileFailure? uploadFailure;
  Completer<void>? pendingSave;

  /// Number of profile listeners currently attached for [uid].
  int listeners(String uid) => _streams[uid]?.hasListener ?? false ? 1 : 0;

  Map<String, UserProfile> profilesOf(String uid) =>
      store.putIfAbsent(uid, () => {});

  void put(String uid, UserProfile profile) {
    profilesOf(uid)[profile.id] = profile;
    _emit(uid);
  }

  void completeSetup(String uid) => accounts[uid] = AccountState(
    setupCompleted: true,
    activeProfileId: accounts[uid]?.activeProfileId,
  );

  void _emit(String uid) => _streams[uid]?.add(profilesOf(uid).values.toList());

  @override
  Stream<List<UserProfile>> watchProfiles(String uid) {
    final controller = _streams[uid] = StreamController<List<UserProfile>>(
      onListen: () => _emit(uid),
    );
    return controller.stream;
  }

  @override
  Future<void> migrateLegacyProfile(
    String uid, {
    required String selfName,
  }) async {
    if (readFailure case final error?) throw error;
    migrations.add(uid);
  }

  @override
  Future<AccountState> fetchAccount(String uid) async {
    if (readFailure case final error?) throw error;
    return accounts[uid] ?? const AccountState();
  }

  @override
  String newProfileId(String uid) => 'new-${++_ids}';

  @override
  Future<void> saveProfile(
    String uid,
    UserProfile profile, {
    bool markSetupComplete = false,
    String? selfName,
  }) async {
    if (saveFailure case final error?) throw error;
    await pendingSave?.future;
    profilesOf(uid)[profile.id] = profile;
    if (markSetupComplete) {
      if (!profile.isSelf && selfName != null) {
        profilesOf(uid).putIfAbsent(
          UserProfile.selfId,
          () => UserProfile(
            id: UserProfile.selfId,
            type: ProfileType.self,
            fullName: selfName,
          ),
        );
      }
      completeSetup(uid);
    }
    _emit(uid);
  }

  @override
  Future<void> setActiveProfile(String uid, String profileId) async {
    if (saveFailure case final error?) throw error;
    accounts[uid] = AccountState(
      setupCompleted: accounts[uid]?.setupCompleted ?? false,
      activeProfileId: profileId,
    );
  }

  @override
  Future<ProfilePhoto> uploadPhoto(
    String uid,
    String profileId,
    File file, {
    void Function(double progress)? onProgress,
  }) async {
    if (uploadFailure case final error?) throw error;
    onProgress?.call(0.5);
    onProgress?.call(1);
    final path =
        'users/$uid/profiles/$profileId/avatar_${uploads.length + 1}.jpg';
    uploads.add(path);
    return (url: 'https://storage.example/$path', path: path);
  }

  @override
  Future<void> deletePhoto(String path) async => deleted.add(path);
}
