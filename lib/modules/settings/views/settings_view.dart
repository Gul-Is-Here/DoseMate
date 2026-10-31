import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/services/notification_service.dart';
import '../../../widgets/app_shell.dart';
import '../../../widgets/appearance_sheet.dart';
import '../../../widgets/profile_avatar.dart';
import '../../../widgets/skeleton.dart';
import '../view_model/settings_view_model.dart';

const _radius = 24.0;
Color get _error => AppColors.error;
Color get _errorContainer => AppColors.errorContainer;

class SettingsView extends GetView<SettingsViewModel> {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          const AppTopBar(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(kMargin, 8, kMargin, 40),
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Settings',
                    style: AppTextStyles.headlineLgMobile.copyWith(
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your account, family profiles and alerts.',
                  style: AppTextStyles.bodyMd.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: kSpaceLg),
                const _AccountCard(),
                const SizedBox(height: kSpaceLg),
                const _SectionLabel('Family'),
                _Group(
                  children: [
                    Obx(() {
                      final managing = controller.managing;
                      final count = controller.profileCount;
                      return _Row(
                        key: const ValueKey('settings-family'),
                        icon: Icons.group_outlined,
                        title: 'Family & Profiles',
                        subtitle: managing != null
                            ? 'Now managing ${managing.fullName}'
                            : count > 1
                            ? '$count profiles · switch, edit or add'
                            : 'Add and manage the people you care for',
                        onTap: controller.openFamily,
                      );
                    }),
                  ],
                ),
                const SizedBox(height: kSpaceLg),
                const _SectionLabel('Notifications'),
                _Group(
                  children: [
                    _Row(
                      key: const ValueKey('settings-notifications'),
                      icon: Icons.notifications_none,
                      title: 'Notifications',
                      subtitle: 'Doses due, refills and appointments',
                      onTap: controller.openNotifications,
                    ),
                    if (controller.notify case final notify?)
                      Obx(
                        () => _Row(
                          key: const ValueKey('settings-alerts'),
                          icon: Icons.tune,
                          title: 'Alert settings',
                          subtitle: _alertStatus(notify),
                          onTap: controller.openAlertSettings,
                        ),
                      ),
                  ],
                ),
                if (controller.appearance case final appearance?) ...[
                  const SizedBox(height: kSpaceLg),
                  const _SectionLabel('Display'),
                  _Group(
                    children: [
                      Obx(
                        () => _Row(
                          key: const ValueKey('settings-appearance'),
                          icon: AppearanceSheet.icon(appearance.mode.value),
                          title: 'Appearance',
                          subtitle: AppearanceSheet.label(
                            appearance.mode.value,
                          ),
                          onTap: controller.openAppearance,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: kSpaceLg),
                const _SectionLabel('Privacy'),
                _Group(
                  children: [
                    _Row(
                      key: const ValueKey('settings-privacy'),
                      icon: Icons.privacy_tip_outlined,
                      title: 'Privacy Policy',
                      subtitle: 'What DoseMate collects and why',
                      trailing: Icons.open_in_new,
                      onTap: controller.openPrivacyPolicy,
                    ),
                    if (controller.ads case final ads?)
                      Obx(
                        () => ads.privacyOptionsRequired.value
                            ? _Row(
                                key: const ValueKey('settings-ad-privacy'),
                                icon: Icons.ads_click_outlined,
                                title: 'Ad privacy choices',
                                subtitle: 'Change your ad consent',
                                onTap: ads.showPrivacyOptions,
                              )
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
                const SizedBox(height: kSpaceLg),
                const _SectionLabel('Account'),
                _Group(
                  children: [
                    Obx(
                      () => _Row(
                        key: const ValueKey('settings-logout'),
                        icon: Icons.logout,
                        title: 'Log out',
                        destructive: true,
                        busy: controller.signingOut.value,
                        onTap: controller.signOut,
                      ),
                    ),
                    _Row(
                      key: const ValueKey('settings-delete-account'),
                      icon: Icons.delete_forever_outlined,
                      title: 'Delete Account',
                      subtitle: 'Permanently delete your account and data',
                      destructive: true,
                      onTap: controller.openDeleteAccount,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _alertStatus(NotificationService notify) {
    if (!notify.ready) return 'Unavailable on this device';
    return switch (notify.permission.value) {
      NotifyPermission.granted => 'On for this device',
      NotifyPermission.denied => 'Off · tap to turn on',
      NotifyPermission.unknown => 'Alerts on this device',
    };
  }
}

/// The signed-in account holder. Stays the same whichever family profile
/// is active (that one shows in the top bar).
class _AccountCard extends GetView<SettingsViewModel> {
  const _AccountCard();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final email = controller.accountEmail;
      final stacked = MediaQuery.textScalerOf(context).scale(16) > 24;
      final avatar = Align(
        alignment: Alignment.centerLeft,
        child: ProfileAvatar(size: 64, url: controller.accountPhotoUrl),
      );
      final details = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A DmTag, but wrapping instead of cut short at large text.
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Text(
                'ACCOUNT HOLDER',
                style: AppTextStyles.labelSm.copyWith(color: AppColors.primary),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            controller.accountName,
            style: AppTextStyles.titleLg.copyWith(color: AppColors.onSurface),
          ),
          if (email != null && email.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              email,
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      );
      return DmCard(
        color: AppColors.surfaceContainerLowest,
        padding: const EdgeInsets.all(20),
        radius: _radius,
        shadow: kShadowSm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (controller.accountLoading)
              Skeleton(
                label: 'Loading your account',
                child: Row(
                  children: [
                    const Bone.circle(size: 64),
                    const SizedBox(width: kSpaceMd),
                    Expanded(
                      child: BoneColumn(
                        children: [
                          const Bone(width: 110, height: 20, radius: 12),
                          const SizedBox(height: 6),
                          Bone.text(AppTextStyles.titleLg, widthFactor: 0.7),
                          const SizedBox(height: 2),
                          Bone.text(AppTextStyles.bodySm, widthFactor: 0.85),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            // Large text stacks the photo above the name, so the name and
            // email keep the card's full width.
            else if (stacked) ...[
              avatar,
              const SizedBox(height: 12),
              details,
            ] else
              Row(
                children: [
                  avatar,
                  const SizedBox(width: kSpaceMd),
                  Expanded(child: details),
                ],
              ),
            const SizedBox(height: kSpaceMd),
            DmPill(
              key: const ValueKey('settings-edit-profile'),
              color: AppColors.surfaceContainerLow,
              minHeight: 48,
              expand: true,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              onTap: controller.canEditProfile ? controller.editProfile : null,
              children: [
                Icon(
                  Icons.edit_outlined,
                  size: 20,
                  color: controller.canEditProfile
                      ? AppColors.primary
                      : AppColors.outline,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Edit profile',
                    style: AppTextStyles.labelLg.copyWith(
                      color: controller.canEditProfile
                          ? AppColors.primary
                          : AppColors.outline,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Semantics(
        header: true,
        child: Text(
          text.toUpperCase(),
          style: AppTextStyles.labelSm.copyWith(
            color: AppColors.onSurfaceVariant,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

/// Rows on one card, divided by hairlines.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: kShadowSm,
      ),
      child: Material(
        type: MaterialType.transparency,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(_radius),
        child: Column(
          children: [
            for (final (i, child) in children.indexed) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: 72,
                  color: AppColors.surfaceContainer,
                ),
              child,
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
    this.busy = false,
    this.trailing = Icons.chevron_right,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool destructive;

  /// The icon at the end, for rows that aren't destructive.
  final IconData trailing;

  /// Shows progress and ignores taps.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? _error : AppColors.onSurface;
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: !busy,
        child: InkWell(
          onTap: busy ? null : onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  DmIconCircle(
                    size: 40,
                    icon: icon,
                    iconSize: 22,
                    color: destructive
                        ? _errorContainer
                        : AppColors.surfaceContainerLow,
                    iconColor: destructive ? _error : AppColors.primary,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppTextStyles.labelLg.copyWith(color: color),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: AppTextStyles.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (busy)
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _error,
                        semanticsLabel: 'Working',
                      ),
                    )
                  else if (!destructive)
                    Icon(trailing, color: AppColors.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
