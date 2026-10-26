import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/utils/image_validator.dart';
import '../../../core/utils/validators.dart';
import '../../../data/models/user_profile.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/profile_service.dart';
import '../../../widgets/app_snackbar.dart';

/// What Profile Setup edits. Passed as the route argument.
class ProfileEditorArgs {
  /// First-run setup; [preselect] comes from the sign-up screen.
  const ProfileEditorArgs.setup([this.preselect])
    : profileId = null,
      newType = null;

  /// Edit one existing profile.
  const ProfileEditorArgs.edit(String this.profileId)
    : newType = null,
      preselect = null;

  /// Add a new Parent, Spouse or Other profile.
  const ProfileEditorArgs.create(ProfileType this.newType)
    : profileId = null,
      preselect = null;

  final String? profileId;
  final ProfileType? newType;
  final AccountFor? preselect;
}

enum EditorMode { setup, edit, create }

class ProfileSetupViewModel extends GetxController {
  ProfileSetupViewModel({ImagePicker? picker, ProfileEditorArgs? args})
    : _picker = picker ?? ImagePicker(),
      _args = args;

  final ImagePicker _picker;

  /// Overrides the route argument (used by tests).
  final ProfileEditorArgs? _args;

  static const relationships = [
    'Mother / Senior Parent',
    'Father / Senior Parent',
    'Spouse or Partner',
    'Grandparent',
    'Child / Dependent',
    'Home Care Client',
  ];

  final _auth = Get.find<AuthService>();
  ProfileService get _profiles => _auth.profiles;

  final nameController = TextEditingController();
  final contactNameController = TextEditingController();
  final contactPhoneController = TextEditingController();

  /// Starts from the choice made on the sign-up screen, when there was one.
  final profileFor = AccountFor.myself.obs;
  final relationship = relationships.first.obs;
  final dateOfBirth = Rxn<DateTime>();

  /// Picked but not uploaded yet; uploaded as part of Save & Continue.
  final pendingPhoto = Rxn<File>();
  final isLoading = false.obs;
  final isSaving = false.obs;

  /// Set when the saved profile couldn't be loaded. Saving is blocked until a
  /// retry succeeds, so a blank form can never overwrite saved data.
  final loadError = RxnString();

  /// 0–1 while a new photo uploads during save.
  final uploadProgress = RxnDouble();

  /// The saved photo, kept live from the shared profile.
  String? get savedPhotoUrl => _profiles.byId(targetId)?.photoUrl;

  /// False right after sign in, when the auth screens were cleared from the stack.
  bool get canGoBack => Get.key.currentState?.canPop() ?? false;

  late final EditorMode mode;
  String? _editId;
  ProfileType? _createType;

  /// Reserved once, so retries after a failed save update the same new
  /// profile instead of creating duplicates.
  String? _reservedId;

  /// The selector is only a real choice during first-run setup.
  bool get canChangeOwner => mode == EditorMode.setup;

  /// The profile this form reads from and saves to. Fixed for the life of
  /// the screen (in setup it follows the owner choice), so switching the
  /// active profile elsewhere can never redirect a save.
  String get targetId => switch (mode) {
    EditorMode.edit => _editId!,
    EditorMode.setup when profileFor.value == AccountFor.myself =>
      UserProfile.selfId,
    _ => _reservedId ??= _profiles.newProfileId(),
  };

  ProfileType get _targetType => switch (mode) {
    EditorMode.edit => _profiles.byId(_editId!)?.type ?? ProfileType.other,
    EditorMode.create => _createType!,
    EditorMode.setup =>
      profileFor.value == AccountFor.myself
          ? ProfileType.self
          : ProfileType.fromRelationship(relationship.value),
  };

  @override
  void onInit() {
    super.onInit();
    final args =
        _args ??
        switch (Get.arguments) {
          final ProfileEditorArgs args => args,
          final AccountFor preselect => ProfileEditorArgs.setup(preselect),
          _ => const ProfileEditorArgs.setup(),
        };
    if (args.profileId != null) {
      mode = EditorMode.edit;
      _editId = args.profileId;
    } else if (args.newType != null) {
      mode = EditorMode.create;
      _createType = args.newType;
      profileFor.value = AccountFor.caregiver;
      relationship.value = args.newType!.defaultRelationship;
    } else {
      mode = EditorMode.setup;
      if (args.preselect != null) profileFor.value = args.preselect!;
    }
    _loadExisting();
  }

  /// Waits for the shared profiles to be ready, then fills the form from the
  /// target profile. A profile that doesn't exist yet gets editable defaults.
  /// The form is locked while loading so nothing typed is overwritten.
  Future<void> _loadExisting() async {
    final user = _auth.user.value;
    if (user == null) return;
    isLoading.value = true;
    loadError.value = null;
    try {
      if (_profiles.status.value == ProfilesStatus.idle) {
        await _profiles.start(
          user.uid,
          selfName: AuthService.selfNameFor(user),
        );
      } else if (_profiles.status.value == ProfilesStatus.loading) {
        await _profiles.status.stream.firstWhere(
          (s) => s != ProfilesStatus.loading,
        );
      }
      if (isClosed) return;
      if (_profiles.status.value == ProfilesStatus.error) {
        loadError.value = _profiles.error.value;
        return;
      }
      if (mode == EditorMode.edit && _profiles.byId(_editId!) == null) {
        loadError.value = 'This profile is no longer available.';
        return;
      }
      _fillForTarget();
    } finally {
      if (!isClosed) isLoading.value = false;
    }
  }

  Future<void> retryLoad() async {
    if (isLoading.value) return;
    await _profiles.retry();
    await _loadExisting();
  }

  /// Fills from the target profile, or resets to defaults when it doesn't
  /// exist yet. Never carries one profile's values into another.
  void _fillForTarget() {
    pendingPhoto.value = null;
    final profile = _profiles.byId(targetId);
    if (profile == null) {
      final isSelf = targetId == UserProfile.selfId;
      nameController.text = isSelf ? (_auth.user.value?.displayName ?? '') : '';
      dateOfBirth.value = null;
      contactNameController.text = '';
      contactPhoneController.text = '';
      if (mode == EditorMode.setup && !isSelf) {
        relationship.value = relationships.first;
      }
      return;
    }
    profileFor.value = profile.type.accountFor;
    nameController.text = profile.fullName;
    if (relationships.contains(profile.relationship)) {
      relationship.value = profile.relationship!;
    }
    dateOfBirth.value = profile.dateOfBirth;
    contactNameController.text = profile.emergencyContactName ?? '';
    contactPhoneController.text = profile.emergencyContactPhone ?? '';
  }

  void selectProfileFor(AccountFor value) {
    if (!canChangeOwner || isSaving.value || profileFor.value == value) return;
    profileFor.value = value;
    _fillForTarget();
  }

  void selectRelationship(String? value) {
    if (value != null) relationship.value = value;
  }

  void selectDateOfBirth(DateTime? value) {
    if (value != null) dateOfBirth.value = value;
  }

  /// Picks, validates and previews a photo. It is only uploaded on save, so
  /// the saved photo stays until the new one is fully saved.
  Future<void> choosePhoto(ImageSource source) async {
    if (isSaving.value) return;
    final XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
        requestFullMetadata: false,
      );
    } on PlatformException catch (e) {
      final (title, message) = switch (e.code) {
        'camera_access_denied' => (
          'Camera access is off',
          'Allow camera access for DoseMate in Settings, or choose from your gallery.',
        ),
        'photo_access_denied' => (
          'Photo access is off',
          'Allow photo access for DoseMate in Settings, or take a photo instead.',
        ),
        'no_available_camera' => (
          'No camera available',
          'This device has no camera. Choose a photo from your gallery instead.',
        ),
        'invalid_image' => (
          "Couldn't use that photo",
          'Choose a different photo.',
        ),
        _ => ("Couldn't open the picker", 'Please try again.'),
      };
      showSnack(title, message);
      return;
    }
    if (picked == null) return; // Cancelled.

    final file = File(picked.path);
    final problem = ImageValidator.validate(file);
    if (problem != null) {
      showSnack("Couldn't use that photo", problem);
      return;
    }
    pendingPhoto.value = file;
  }

  void back() => Get.back();

  /// Leaves the profile as it is; an incomplete one is offered again on the
  /// next sign in.
  void skip() {
    if (isSaving.value) return;
    _goHome();
  }

  Future<void> saveAndContinue() async {
    if (isSaving.value || isLoading.value) return;
    if (_auth.user.value == null) return;
    if (loadError.value != null) {
      showSnack(
        'Profile not loaded',
        'Tap "Try again" to load your saved profile before saving changes.',
      );
      return;
    }

    final name = nameController.text.trim();
    final contactName = contactNameController.text.trim();
    final contactPhone = contactPhoneController.text.trim();
    final error =
        Validators.name(name) ?? Validators.optionalPhone(contactPhone);
    if (error != null) {
      showSnack('Check your profile', error);
      return;
    }

    isSaving.value = true;
    try {
      final id = targetId;
      await _profiles.save(
        UserProfile(
          id: id,
          type: _targetType,
          fullName: name,
          relationship: relationship.value,
          dateOfBirth: dateOfBirth.value,
          emergencyContactName: contactName.isEmpty ? null : contactName,
          emergencyContactPhone: contactPhone.isEmpty ? null : contactPhone,
        ),
        newPhoto: pendingPhoto.value,
        markSetupComplete: mode == EditorMode.setup || id == UserProfile.selfId,
        onUploadProgress: (value) => uploadProgress.value = value,
      );
      pendingPhoto.value = null;
      // Edits return to where they were opened (Settings, Family); first
      // setup continues to Home.
      if (mode != EditorMode.setup && canGoBack) {
        Get.back();
      } else {
        _goHome();
      }
      showSnack('Profile saved', 'Your changes are saved.');
    } on ProfileFailure catch (e) {
      // Fields and the picked photo stay as entered so the user can retry.
      showSnack("Couldn't save profile", e.message);
    } finally {
      if (!isClosed) {
        isSaving.value = false;
        uploadProgress.value = null;
      }
    }
  }

  /// Home itself sends unverified email accounts to verification.
  void _goHome() => Get.offAllNamed(AppRoutes.home);

  @override
  void onClose() {
    nameController.dispose();
    contactNameController.dispose();
    contactPhoneController.dispose();
    super.onClose();
  }
}
