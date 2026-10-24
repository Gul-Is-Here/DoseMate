import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../app/routes/app_routes.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../data/models/user_profile.dart';
import '../data/repositories/profile_repository.dart';
import '../data/services/profile_service.dart';
import '../modules/profile_setup/view_model/profile_setup_view_model.dart';
import 'profile_avatar.dart';

/// Lists the account's profiles, shows which is active, and lets the user
/// switch, edit or add one.
class ProfileSwitcherSheet extends StatelessWidget {
  const ProfileSwitcherSheet({super.key});

  static Future<void> show() => Get.bottomSheet(
    const ProfileSwitcherSheet(),
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
    ),
  );

  ProfileService get _service => Get.find<ProfileService>();

  Future<void> _switchTo(String id) async {
    Get.back();
    try {
      await _service.switchTo(id);
    } on ProfileFailure catch (e) {
      Get.snackbar(
        'Switched profile',
        "We couldn't remember this choice: ${e.message}",
      );
    }
  }

  void _edit(String id) {
    Get.back();
    Get.toNamed(AppRoutes.profileSetup, arguments: ProfileEditorArgs.edit(id));
  }

  void _add(ProfileType type) {
    Get.back();
    Get.toNamed(
      AppRoutes.profileSetup,
      arguments: ProfileEditorArgs.create(type),
    );
  }

  void _setUp() {
    Get.back();
    Get.toNamed(
      AppRoutes.profileSetup,
      arguments: const ProfileEditorArgs.setup(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.outlineVariant,
                    borderRadius: BorderRadius.circular(9999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Profiles',
                style: AppTextStyles.headlineLgMobile.copyWith(
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Switch who you are managing medications for.',
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Flexible(child: Obx(_body)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_service.status.value) {
      case ProfilesStatus.idle || ProfilesStatus.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: CircularProgressIndicator(color: AppColors.primaryContainer),
          ),
        );
      case ProfilesStatus.error:
        return _Message(
          icon: Icons.cloud_off_outlined,
          text: _service.error.value ?? 'Could not load profiles.',
          action: 'Try again',
          onAction: _service.retry,
        );
      case ProfilesStatus.ready when _service.profiles.isEmpty:
        return _Message(
          icon: Icons.person_add_alt_1_outlined,
          text: "You haven't set up a profile yet.",
          action: 'Set up my profile',
          onAction: _setUp,
        );
      case ProfilesStatus.ready:
        final activeId = _service.activeProfile?.id;
        return ListView(
          shrinkWrap: true,
          children: [
            for (final profile in _service.profiles)
              _ProfileTile(
                profile: profile,
                active: profile.id == activeId,
                onTap: () => _switchTo(profile.id),
                onEdit: () => _edit(profile.id),
              ),
            const SizedBox(height: 8),
            _AddProfile(onAdd: _add),
          ],
        );
    }
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.profile,
    required this.active,
    required this.onTap,
    required this.onEdit,
  });

  final UserProfile profile;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: active
            ? AppColors.surfaceContainerLowest
            : AppColors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: active
              ? const BorderSide(color: AppColors.primaryContainer, width: 2)
              : BorderSide.none,
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
            child: Row(
              children: [
                ProfileAvatar(size: 44, url: profile.photoUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              profile.fullName,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.titleMd.copyWith(
                                color: AppColors.onSurface,
                              ),
                            ),
                          ),
                          if (active) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryFixed,
                                borderRadius: BorderRadius.circular(9999),
                              ),
                              child: Text(
                                'Active',
                                style: AppTextStyles.labelSm.copyWith(
                                  color: AppColors.onPrimaryFixed,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        profile.relationshipLabel,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Edit ${profile.fullName}',
                  onPressed: onEdit,
                  icon: const Icon(
                    Icons.edit_outlined,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddProfile extends StatelessWidget {
  const _AddProfile({required this.onAdd});

  final ValueChanged<ProfileType> onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Add profile',
          style: AppTextStyles.labelMd.copyWith(color: AppColors.onSurface),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final type in [
              ProfileType.parent,
              ProfileType.spouse,
              ProfileType.other,
            ])
              ActionChip(
                avatar: const Icon(
                  Icons.add,
                  size: 18,
                  color: AppColors.primary,
                ),
                label: Text(type.label),
                labelStyle: AppTextStyles.labelMd.copyWith(
                  color: AppColors.primary,
                ),
                backgroundColor: AppColors.surfaceContainerLow,
                side: BorderSide.none,
                shape: const StadiumBorder(),
                onPressed: () => onAdd(type),
              ),
          ],
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    required this.action,
    required this.onAction,
  });

  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: AppColors.outline),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onAction,
            child: Text(
              action,
              style: AppTextStyles.labelLg.copyWith(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}
