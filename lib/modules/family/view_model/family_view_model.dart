import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../data/models/user_profile.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/services/care_service.dart';
import '../../../data/services/profile_service.dart';
import '../../profile_setup/view_model/profile_setup_view_model.dart';
import '../../../widgets/app_snackbar.dart';

/// Family Profiles: the profiles the account owner manages (Myself, Parent,
/// Spouse, Other). Only the owner sees them, switches between them, edits
/// them or adds new ones.
class FamilyViewModel extends GetxController {
  final ProfileService profiles = Get.find<CareService>().profiles;

  /// The profile being switched to, while the choice is saved.
  final switching = RxnString();

  /// The account's own profiles, Myself first.
  List<UserProfile> get owned => profiles.profiles;

  String? get activeId => profiles.activeProfile?.id;

  ProfilesStatus get status => profiles.status.value;

  String? get error => profiles.error.value;

  void retry() => profiles.retry();

  Future<void> switchTo(UserProfile p) async {
    if (switching.value != null || p.id == activeId) return;
    switching.value = p.id;
    try {
      await profiles.switchTo(p.id);
    } on ProfileFailure catch (e) {
      showSnack(
        'Switched profile',
        "We couldn't remember this choice: ${e.message}",
      );
    } finally {
      switching.value = null;
    }
  }

  void edit(UserProfile p) => Get.toNamed(
    AppRoutes.profileSetup,
    arguments: ProfileEditorArgs.edit(p.id),
  );

  void add(ProfileType type) => Get.toNamed(
    AppRoutes.profileSetup,
    arguments: ProfileEditorArgs.create(type),
  );

  void setUp() => Get.toNamed(
    AppRoutes.profileSetup,
    arguments: const ProfileEditorArgs.setup(),
  );
}
