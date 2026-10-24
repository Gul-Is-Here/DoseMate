import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';

import '../models/user_profile.dart';
import '../repositories/profile_repository.dart';

enum ProfilesStatus { idle, loading, ready, error }

/// The signed-in account's managed profiles and which one is active. Shared
/// app-wide so a save or switch shows up on every screen immediately.
///
/// Profile-specific features should follow [activeProfileId] (e.g. with
/// `ever`) and cancel their own listeners when it changes.
class ProfileService extends GetxService {
  ProfileService(this.repository);

  final ProfileRepository repository;

  final profiles = <UserProfile>[].obs;
  final activeProfileId = UserProfile.selfId.obs;
  final account = const AccountState().obs;
  final status = ProfilesStatus.idle.obs;
  final error = RxnString();

  String? _uid;
  String _selfName = '';
  StreamSubscription<List<UserProfile>>? _subscription;

  /// The active profile, falling back to Myself when it no longer exists.
  UserProfile? get activeProfile =>
      byId(activeProfileId.value) ?? byId(UserProfile.selfId);

  UserProfile? get selfProfile => byId(UserProfile.selfId);

  UserProfile? byId(String id) => profiles.firstWhereOrNull((p) => p.id == id);

  bool get isReady => status.value == ProfilesStatus.ready;

  /// The signed-in account these profiles belong to, if any.
  String? get uid => _uid;

  /// Migrates legacy data, loads account state and starts the single
  /// profiles listener for [uid]. Safe to call repeatedly; pass [force] to
  /// reload. Errors are reported through [status] and [error].
  Future<void> start(
    String uid, {
    required String selfName,
    bool force = false,
  }) async {
    if (!force && _uid == uid && status.value != ProfilesStatus.error) return;
    stop();
    _uid = uid;
    _selfName = selfName;
    status.value = ProfilesStatus.loading;
    try {
      await repository.migrateLegacyProfile(uid, selfName: selfName);
      final loadedAccount = await repository.fetchAccount(uid);
      if (_uid != uid) return; // Signed out or switched user meanwhile.
      account.value = loadedAccount;
      activeProfileId.value =
          loadedAccount.activeProfileId ?? UserProfile.selfId;
    } on ProfileFailure catch (e) {
      if (_uid == uid) _fail(e.message);
      return;
    }

    final firstSnapshot = Completer<void>();
    _subscription = repository
        .watchProfiles(uid)
        .listen(
          (list) {
            if (_uid != uid) return;
            // One notification: assignAll would first report an empty list,
            // which looks like "no profiles" to anything following this.
            profiles.value = list..sort(_order);
            status.value = ProfilesStatus.ready;
            error.value = null;
            if (!firstSnapshot.isCompleted) firstSnapshot.complete();
          },
          onError: (Object e) {
            if (_uid == uid) {
              _fail(
                e is ProfileFailure ? e.message : 'Could not load profiles.',
              );
            }
            if (!firstSnapshot.isCompleted) firstSnapshot.complete();
          },
        );
    await firstSnapshot.future;
  }

  /// Records need a profile to belong to. Accounts that skipped Profile
  /// Setup have none, so this creates Myself from the account name. Setup
  /// stays incomplete and can still be finished later. Errors are reported
  /// through [status] and [error].
  Future<void> ensureSelf() {
    final uid = _uid;
    if (uid == null || !isReady || selfProfile != null) return Future.value();
    // Once per sign in, however often it is asked for.
    return _creatingSelf ??= _createSelf(uid);
  }

  Future<void>? _creatingSelf;

  Future<void> _createSelf(String uid) async {
    final self = UserProfile(
      id: UserProfile.selfId,
      type: ProfileType.self,
      fullName: _selfName.trim().isEmpty ? 'Me' : _selfName.trim(),
    );
    try {
      await repository.saveProfile(uid, self);
    } on ProfileFailure catch (e) {
      // Allow another attempt (e.g. Retry once back online).
      _creatingSelf = null;
      if (_uid == uid) _fail(e.message);
      return;
    }
    if (_uid != uid || selfProfile != null) return;
    profiles
      ..add(self)
      ..sort(_order);
  }

  /// Cancels the listener and forgets everything (sign out / user change).
  void stop() {
    _creatingSelf = null;
    _subscription?.cancel();
    _subscription = null;
    _uid = null;
    profiles.clear();
    activeProfileId.value = UserProfile.selfId;
    account.value = const AccountState();
    status.value = ProfilesStatus.idle;
    error.value = null;
  }

  Future<void> retry() async {
    final uid = _uid;
    if (uid != null) await start(uid, selfName: _selfName, force: true);
  }

  /// Switches immediately on this device and remembers it for next time. A
  /// failure to remember is reported but doesn't undo the switch.
  Future<void> switchTo(String profileId) async {
    final uid = _uid;
    if (uid == null || byId(profileId) == null) return;
    activeProfileId.value = profileId;
    await repository.setActiveProfile(uid, profileId);
  }

  String newProfileId() => repository.newProfileId(_uid!);

  /// Uploads [newPhoto] if given, then saves [edited] under its own id. The
  /// saved photo and profile stay untouched until both succeed; a failed save
  /// removes the new upload. The listener refreshes [profiles] afterwards,
  /// and the local copy is updated right away so screens don't wait for it.
  Future<void> save(
    UserProfile edited, {
    File? newPhoto,
    bool markSetupComplete = false,
    void Function(double progress)? onUploadProgress,
  }) async {
    final uid = _uid;
    if (uid == null) {
      throw const ProfileFailure('You are signed out. Sign in and try again.');
    }
    final existing = byId(edited.id);
    final photo = newPhoto == null
        ? null
        : await repository.uploadPhoto(
            uid,
            edited.id,
            newPhoto,
            onProgress: onUploadProgress,
          );
    final toSave = edited.copyWith(
      photoUrl: photo?.url ?? existing?.photoUrl,
      photoPath: photo?.path ?? existing?.photoPath,
    );
    try {
      await repository.saveProfile(
        uid,
        toSave,
        markSetupComplete: markSetupComplete,
        selfName: _selfName,
      );
    } on ProfileFailure {
      if (photo != null) await repository.deletePhoto(photo.path);
      rethrow;
    }
    if (_uid != uid) return;
    final index = profiles.indexWhere((p) => p.id == toSave.id);
    index >= 0 ? profiles[index] = toSave : profiles.add(toSave);
    profiles.sort(_order);
    if (markSetupComplete) {
      account.value = AccountState(
        setupCompleted: true,
        activeProfileId: account.value.activeProfileId,
      );
    }
    final previousPath = existing?.photoPath;
    if (photo != null && previousPath != null) {
      await repository.deletePhoto(previousPath);
    }
  }

  void _fail(String message) {
    // Message first: listeners react to the status change straight away.
    error.value = message;
    status.value = ProfilesStatus.error;
  }

  /// Myself first, then by name.
  static int _order(UserProfile a, UserProfile b) {
    if (a.isSelf != b.isSelf) return a.isSelf ? -1 : 1;
    return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
  }
}
