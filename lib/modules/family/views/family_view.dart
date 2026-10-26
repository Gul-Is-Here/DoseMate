import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/user_profile.dart';
import '../../../data/services/profile_service.dart';
import '../../../widgets/app_shell.dart';
import '../../../widgets/profile_avatar.dart';
import '../../../widgets/skeleton.dart';
import '../view_model/family_view_model.dart';

const _radius = 16.0;

class FamilyView extends GetView<FamilyViewModel> {
  const FamilyView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          const AppBackBar(title: 'Family & Profiles'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(kMargin, 8, kMargin, 40),
              children: [
                const _Banner(),
                const SizedBox(height: kSpaceLg),
                Obx(
                  () => switch (controller.status) {
                    ProfilesStatus.idle ||
                    ProfilesStatus.loading => const _Loading(),
                    ProfilesStatus.error => _ErrorState(
                      message: controller.error,
                      onRetry: controller.retry,
                    ),
                    ProfilesStatus.ready when controller.owned.isEmpty =>
                      const _NoProfiles(),
                    ProfilesStatus.ready => const _Profiles(),
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.strip});

  final Widget child;
  final Color? strip;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: kShadowSm,
      ),
      child: Stack(
        children: [
          Padding(padding: const EdgeInsets.all(kSpaceLg), child: child),
          if (strip != null)
            Positioned(
              left: 0,
              top: 12,
              bottom: 12,
              child: Container(
                width: 6,
                decoration: BoxDecoration(
                  color: strip,
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(999),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner();

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(32),
        boxShadow: kShadowSm,
      ),
      child: Stack(
        children: [
          Positioned(
            right: -16,
            bottom: -16,
            child: Opacity(
              opacity: 0.1,
              child: Icon(
                Icons.supervised_user_circle_outlined,
                size: 120,
                color: AppColors.primary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(kSpaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.health_and_safety,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'PRIVACY-FIRST PROTECTION',
                          style: AppTextStyles.labelSm.copyWith(
                            color: AppColors.primary,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Family Profiles',
                  style: AppTextStyles.headlineLgMobile.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage medications for everyone you care for, all from '
                  'your own account.',
                  style: AppTextStyles.bodyMd.copyWith(
                    color: AppColors.onSurfaceVariant,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The profile cards while the account's profiles load.
class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      label: 'Loading profiles',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Bone.text(AppTextStyles.titleLg, widthFactor: 0.5),
              ),
              const Bone(width: 80, height: 22, radius: 999),
            ],
          ),
          for (var i = 0; i < 2; i++) ...[
            const SizedBox(height: kSpaceMd),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Bone.circle(size: 56),
                      const SizedBox(width: kSpaceMd),
                      Expanded(
                        child: BoneColumn(
                          children: [
                            Bone.text(AppTextStyles.titleMd, widthFactor: 0.6),
                            Bone.text(AppTextStyles.bodySm, widthFactor: 0.75),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: kSpaceMd),
                  const Row(
                    children: [
                      Expanded(child: Bone(height: 44, radius: 999)),
                      SizedBox(width: 8),
                      Bone(width: 64, height: 44, radius: 999),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        children: [
          DmIconCircle(
            size: 56,
            icon: Icons.cloud_off,
            iconSize: 28,
            color: AppColors.surfaceContainer,
            iconColor: AppColors.primary,
          ),
          const SizedBox(height: 12),
          Text(
            message ?? 'Couldn’t load your profiles.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          DmWideButton(
            label: 'Retry',
            icon: Icons.refresh,
            height: 48,
            onTap: onRetry,
          ),
        ],
      ),
    );
  }
}

/// The account owner's profiles, the active one first in line to manage.
class _Profiles extends GetView<FamilyViewModel> {
  const _Profiles();

  @override
  Widget build(BuildContext context) => Obx(() {
    final owned = controller.owned;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.groups, size: 22, color: AppColors.primary),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'Your Profiles',
                style: AppTextStyles.titleLg.copyWith(
                  color: AppColors.onSurface,
                ),
              ),
            ),
            DmTag(
              label:
                  '${owned.length} ${owned.length == 1 ? 'Profile' : 'Profiles'}',
              color: AppColors.surfaceContainer,
              textColor: AppColors.onSurfaceVariant,
            ),
          ],
        ),
        for (final p in owned) ...[
          const SizedBox(height: kSpaceMd),
          _ProfileCard(key: ValueKey('p-${p.id}'), profile: p),
        ],
        const SizedBox(height: kSpaceLg),
        const _AddProfileCard(),
        const SizedBox(height: kSpaceMd),
        const _InfoBox(
          icon: Icons.lock_outline,
          text:
              'Only you, the account owner, can see and manage these '
              'profiles.',
        ),
      ],
    );
  });
}

class _ProfileCard extends GetView<FamilyViewModel> {
  const _ProfileCard({super.key, required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final first = p.fullName.trim().split(RegExp(r'\s+')).first;
    return Obx(() {
      final active = p.id == controller.activeId;
      return _Card(
        strip: active ? AppColors.primary : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              leading: ProfileAvatar(size: 56, url: p.photoUrl),
              title: p.fullName,
              titleExtra: p.isSelf
                  ? DmTag(
                      label: '(Self)',
                      color: AppColors.surfaceContainer,
                      textColor: AppColors.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    )
                  : null,
              subtitle: p.isSelf
                  ? 'Account owner'
                  : 'Managed by you · ${p.relationshipLabel}',
              badge: active
                  ? _Badge(
                      'Active',
                      AppColors.primaryFixed,
                      AppColors.onPrimaryFixed,
                      dot: AppColors.primary,
                    )
                  : null,
            ),
            const SizedBox(height: kSpaceMd),
            _ActionRow(
              primaryIcon: active ? Icons.check_circle : Icons.swap_horiz,
              primaryLabel: active
                  ? 'Currently managing'
                  : 'Switch to ${first.isEmpty ? 'profile' : first}',
              primaryColor: active
                  ? AppColors.onSurfaceVariant
                  : AppColors.primary,
              onPrimary: active ? null : () => controller.switchTo(p),
              secondaryLabel: 'Edit',
              secondaryColor: AppColors.primary,
              onSecondary: () => controller.edit(p),
              busy: controller.switching.value == p.id,
            ),
          ],
        ),
      );
    });
  }
}

class _AddProfileCard extends GetView<FamilyViewModel> {
  const _AddProfileCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add a Profile',
            style: AppTextStyles.titleMd.copyWith(color: AppColors.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            'Track medications for a parent, spouse or anyone else you care '
            'for.',
            style: AppTextStyles.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: kSpaceMd),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in const [
                ProfileType.parent,
                ProfileType.spouse,
                ProfileType.other,
              ])
                DmPill(
                  color: AppColors.surfaceContainerLow,
                  minHeight: 44,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  tooltip: 'Add ${type.label} profile',
                  onTap: () => controller.add(type),
                  children: [
                    Icon(Icons.add, size: 18, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      type.label,
                      style: AppTextStyles.labelMd.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoProfiles extends GetView<FamilyViewModel> {
  const _NoProfiles();

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        children: [
          DmIconCircle(
            size: 56,
            icon: Icons.person_add_alt_1_outlined,
            iconSize: 28,
            color: AppColors.surfaceContainer,
            iconColor: AppColors.primary,
          ),
          const SizedBox(height: 12),
          Text(
            "You haven't set up a profile yet.",
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          DmWideButton(
            label: 'Set up my profile',
            icon: Icons.arrow_forward,
            height: 48,
            onTap: controller.setUp,
          ),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.bg, this.fg, {this.dot});

  final String label;
  final Color bg;
  final Color fg;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[
            DmDot(size: 8, color: dot!),
            const SizedBox(width: 4),
          ],
          Text(label, style: AppTextStyles.labelSm.copyWith(color: fg)),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.leading,
    required this.title,
    required this.subtitle,
    this.badge,
    this.titleExtra,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final Widget? badge;
  final Widget? titleExtra;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        leading,
        const SizedBox(width: kSpaceMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 4,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.titleMd.copyWith(
                      color: AppColors.onSurface,
                    ),
                  ),
                  ?titleExtra,
                ],
              ),
              Text(
                subtitle,
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (badge != null) ...[const SizedBox(width: 8), badge!],
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.primaryIcon,
    required this.primaryLabel,
    required this.primaryColor,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.secondaryColor,
    required this.onSecondary,
    required this.busy,
  });

  final IconData primaryIcon;
  final String primaryLabel;
  final Color primaryColor;
  final VoidCallback? onPrimary;
  final String secondaryLabel;
  final Color secondaryColor;
  final VoidCallback onSecondary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DmPill(
            color: AppColors.surfaceContainerLow,
            minHeight: 44,
            expand: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            onTap: busy ? null : onPrimary,
            children: [
              if (busy)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
              else
                Icon(primaryIcon, size: 18, color: primaryColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  primaryLabel,
                  style: AppTextStyles.labelMd.copyWith(color: primaryColor),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: busy ? null : onSecondary,
          style: TextButton.styleFrom(
            minimumSize: const Size(64, 44),
            padding: const EdgeInsets.symmetric(horizontal: kSpaceMd),
            shape: const StadiumBorder(),
            foregroundColor: secondaryColor,
          ),
          child: Text(secondaryLabel, style: AppTextStyles.labelMd),
        ),
      ],
    );
  }
}
