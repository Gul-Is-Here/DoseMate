import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/utils/contact_links.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../data/models/user_profile.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/notification_service.dart';
import '../../../data/services/profile_service.dart';
import '../../../widgets/appearance_sheet.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../widgets/notification_settings_sheet.dart';
import '../../profile_setup/view_model/profile_setup_view_model.dart';
import '../../../widgets/app_snackbar.dart';

/// The Settings tab: the signed-in account, links to Family & Profiles and
/// Notifications, this device's alert settings, and sign out. It reads the
/// app's existing services and starts no listeners of its own.
class SettingsViewModel extends GetxController {
  final AuthService _auth = Get.find<AuthService>();

  ProfileService get profiles => _auth.profiles;

  /// Null where notifications aren't set up (the alert settings row hides).
  NotificationService? get notify => Get.isRegistered<NotificationService>()
      ? Get.find<NotificationService>()
      : null;

  /// Null where appearance isn't set up (the row hides).
  ThemeController? get appearance =>
      Get.isRegistered<ThemeController>() ? Get.find<ThemeController>() : null;

  void openAppearance() => AppearanceSheet.show();

  final signingOut = false.obs;

  // The account holder: always the Myself profile and the signed-in email,
  // whichever family profile is active.

  UserProfile? get _self => profiles.selfProfile;

  String get accountName {
    final name = _self?.fullName.trim() ?? '';
    if (name.isNotEmpty) return name;
    final user = _auth.user.value;
    return user == null ? 'Your account' : AuthService.selfNameFor(user);
  }

  String? get accountEmail => _auth.user.value?.email;

  /// The account's profile hasn't arrived yet (its name and photo).
  bool get accountLoading {
    final status = profiles.status.value;
    return _self == null &&
        (status == ProfilesStatus.idle || status == ProfilesStatus.loading);
  }

  String? get accountPhotoUrl => _self?.photoUrl;

  /// False while profiles load: the editor needs to know what it edits.
  bool get canEditProfile =>
      _self != null || profiles.status.value == ProfilesStatus.ready;

  /// The family profile the app currently shows, when it isn't the
  /// account holder's own.
  UserProfile? get managing {
    final active = profiles.activeProfile;
    return active == null || active.isSelf ? null : active;
  }

  int get profileCount => profiles.profiles.length;

  void editProfile() {
    if (_self != null) {
      Get.toNamed(
        AppRoutes.profileSetup,
        arguments: const ProfileEditorArgs.edit(UserProfile.selfId),
      );
    } else if (profiles.status.value == ProfilesStatus.ready) {
      Get.toNamed(
        AppRoutes.profileSetup,
        arguments: const ProfileEditorArgs.setup(),
      );
    }
  }

  void openFamily() => Get.toNamed(AppRoutes.family);

  void openNotifications() => Get.toNamed(AppRoutes.notifications);

  void openPrivacyPolicy() => openWebPage(AppConfig.privacyPolicyUrl);

  void openDeleteAccount() => Get.toNamed(AppRoutes.deleteAccount);

  Future<void> openAlertSettings() async {
    if (notify == null) return;
    await NotificationSettingsSheet.show();
  }

  Future<void> signOut() async {
    if (signingOut.value) return;
    final ok = await confirmAction(
      title: 'Log out?',
      message:
          'Reminders for this account stop on this device until you sign in '
          'again.',
      confirmLabel: 'Log out',
      cancelLabel: 'Cancel',
    );
    if (!ok) return;
    signingOut.value = true;
    try {
      // Sign in opens once Firebase reports the sign out.
      await _auth.signOut();
    } catch (e) {
      if (kDebugMode) debugPrint('Sign out error: ${e.runtimeType}');
      showSnack("Couldn't log out", 'Check your connection and try again.');
    } finally {
      if (!isClosed) signingOut.value = false;
    }
  }
}
