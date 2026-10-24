import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../app/routes/app_routes.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../data/models/user_profile.dart';
import '../data/services/auth_service.dart';
import 'profile_avatar.dart';
import 'profile_switcher_sheet.dart';

/// Shared screen chrome (top bar, bottom tabs) and building blocks for the
/// tabbed DoseMate screens.

/// Account actions used by the top bar.
class _Shell {
  const _Shell();

  AuthService get _auth => Get.find<AuthService>();

  bool get isSignedIn => _auth.isSignedIn;

  UserProfile? get activeProfile => _auth.profiles.activeProfile;

  void openProfiles() => ProfileSwitcherSheet.show();

  /// The auth listener routes to sign in once Firebase reports the logout.
  Future<void> signOut() => _auth.signOut();

  void signIn() => Get.offAllNamed(AppRoutes.login);
}

// Design tokens from the reference (Tailwind config).
const kMargin = 20.0;
const kSpaceMd = 16.0;
const kSpaceLg = 24.0;
const kRadiusLg = 32.0;
const kShadowSm = [
  BoxShadow(color: Color(0x0D000000), offset: Offset(0, 1), blurRadius: 2),
];
const kShadowMd = [
  BoxShadow(
    color: Color(0x1A000000),
    offset: Offset(0, 4),
    blurRadius: 6,
    spreadRadius: -1,
  ),
  BoxShadow(
    color: Color(0x1A000000),
    offset: Offset(0, 2),
    blurRadius: 4,
    spreadRadius: -2,
  ),
];

class AppTopBar extends StatelessWidget {
  const AppTopBar({super.key});

  static const _Shell _shell = _Shell();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.85),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A132238),
            offset: Offset(0, 1),
            blurRadius: 8,
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kMargin),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const _Logo(),
                      const SizedBox(width: 8),
                      Flexible(
                        child: DmPill(
                          tooltip: 'Switch active family profile',
                          onTap: _shell.isSignedIn ? _shell.openProfiles : null,
                          color: AppColors.surfaceContainerLow,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minHeight: 44,
                          children: [
                            const DmDot(size: 8, color: AppColors.primary),
                            const SizedBox(width: 4),
                            Flexible(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 110,
                                ),
                                child: Obx(
                                  () => Text(
                                    _shell.activeProfile?.fullName ??
                                        'DoseMate',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.labelMd.copyWith(
                                      color: AppColors.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.expand_more,
                              size: 18,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Caregiver Notifications',
                  onPressed: () {},
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                  icon: const Icon(
                    Icons.notifications_none,
                    size: 24,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                const _AccountMenu(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// DoseMate mark. Drop the brand logo at assets/logo.png to replace the
/// fallback.
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/logo.png',
      height: 32,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.medication_outlined,
          size: 20,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

/// Profile photo in the top bar; opens the switcher and sign out.
class _AccountMenu extends StatelessWidget {
  const _AccountMenu();

  _Shell get controller => const _Shell();

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Profile Settings',
      position: PopupMenuPosition.under,
      color: AppColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (value) => switch (value) {
        'switch' => controller.openProfiles(),
        'logout' => controller.signOut(),
        _ => controller.signIn(),
      },
      itemBuilder: (_) => [
        if (controller.isSignedIn) ...[
          const PopupMenuItem(value: 'switch', child: Text('Switch profile')),
          const PopupMenuItem(value: 'logout', child: Text('Log out')),
        ] else
          const PopupMenuItem(value: 'signin', child: Text('Sign in')),
      ],
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Obx(
            () => ProfileAvatar(
              size: 32,
              url: controller.activeProfile?.photoUrl,
            ),
          ),
        ),
      ),
    );
  }
}

/// Top bar for pushed screens: back, logo, title and the profile photo.
class AppBackBar extends StatelessWidget {
  const AppBackBar({super.key, required this.title});

  final String title;

  static const _Shell _shell = _Shell();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.85),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A132238),
            offset: Offset(0, 1),
            blurRadius: 8,
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.only(left: kMargin - 8, right: kMargin),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Go back',
                  onPressed: Get.back,
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                  icon: const Icon(
                    Icons.arrow_back,
                    size: 24,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(width: 4),
                Image.asset(
                  'assets/logo.png',
                  height: 32,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.medication_outlined,
                    size: 28,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.titleMd.copyWith(
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: Obx(
                      () => ProfileAvatar(
                        size: 32,
                        url: _shell.activeProfile?.photoUrl,
                      ),
                    ),
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

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.activeIndex});

  /// 0 Home, 1 Medicines; the other tabs have no screens yet.
  final int activeIndex;

  static const _items = [
    (Icons.home_outlined, 'Home'),
    (Icons.medication_outlined, 'Medicines'),
    (Icons.calendar_month_outlined, 'Calendar'),
    (Icons.fact_check_outlined, 'History'),
    (Icons.group_outlined, 'Family'),
  ];

  void _open(int index) {
    if (index == activeIndex) return;
    final route = switch (index) {
      0 => AppRoutes.home,
      1 => AppRoutes.medicines,
      _ => null,
    };
    if (route != null) Get.offAllNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.9),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F132238),
            offset: Offset(0, -2),
            blurRadius: 16,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 80,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (final (index, (icon, label)) in _items.indexed)
                  Flexible(
                    child: _NavItem(
                      icon: icon,
                      label: label,
                      active: index == activeIndex,
                      onTap: () => _open(index),
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

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.onSurfaceVariant;
    return Semantics(
      selected: active,
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 56, minHeight: 52),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 26, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelSm
                    .copyWith(color: color)
                    .weight(active ? FontWeight.w700 : FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Small building blocks.

class DmCard extends StatelessWidget {
  const DmCard({
    super.key,
    required this.color,
    required this.padding,
    required this.child,
    this.shadow,
  });

  final Color color;
  final EdgeInsets padding;
  final Widget child;
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(kRadiusLg),
        boxShadow: shadow,
      ),
      child: child,
    );
  }
}

/// Fully rounded, tappable chip/button.
class DmPill extends StatelessWidget {
  const DmPill({
    super.key,
    required this.color,
    required this.children,
    this.onTap,
    this.tooltip,
    this.padding = EdgeInsets.zero,
    this.minHeight = 0,
    this.expand = false,
    this.shadow,
  });

  final Color color;
  final List<Widget> children;
  final VoidCallback? onTap;
  final String? tooltip;
  final EdgeInsets padding;
  final double minHeight;
  final bool expand;
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(999);
    Widget pill = DecoratedBox(
      decoration: BoxDecoration(borderRadius: shape, boxShadow: shadow),
      child: Material(
        color: color,
        borderRadius: shape,
        child: InkWell(
          onTap: onTap,
          borderRadius: shape,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: padding,
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
    if (tooltip != null) pill = Tooltip(message: tooltip, child: pill);
    return pill;
  }
}

class DmWideButton extends StatelessWidget {
  const DmWideButton({
    super.key,
    required this.label,
    required this.icon,
    required this.height,
    required this.onTap,
    this.color = AppColors.primary,
  });

  final String label;
  final IconData icon;
  final double height;

  /// Null shows the button disabled (e.g. while saving).
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DmPill(
      onTap: onTap,
      color: onTap == null ? color.withValues(alpha: 0.6) : color,
      minHeight: height,
      expand: true,
      shadow: kShadowMd,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        Icon(icon, size: 22, color: AppColors.onPrimary),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelLg.copyWith(color: AppColors.onPrimary),
          ),
        ),
      ],
    );
  }
}

class DmTag extends StatelessWidget {
  const DmTag({
    super.key,
    required this.label,
    required this.color,
    required this.textColor,
    this.fontWeight = FontWeight.w700,
    this.radius = 999,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    this.maxLines = 1,
  });

  final String label;
  final Color color;
  final Color textColor;
  final FontWeight fontWeight;
  final double radius;
  final EdgeInsets padding;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.labelSm
            .copyWith(color: textColor)
            .weight(fontWeight),
      ),
    );
  }
}

class DmIconCircle extends StatelessWidget {
  const DmIconCircle({
    super.key,
    required this.size,
    required this.icon,
    required this.iconSize,
    required this.color,
    required this.iconColor,
    this.shadow,
  });

  final double size;
  final IconData icon;
  final double iconSize;
  final Color color;
  final Color iconColor;
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: shadow,
      ),
      child: Icon(icon, size: iconSize, color: iconColor),
    );
  }
}

class DmDot extends StatelessWidget {
  const DmDot({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class DmToggle extends StatelessWidget {
  const DmToggle({
    super.key,
    required this.value,
    required this.onTap,
    required this.label,
    this.activeColor = AppColors.primaryContainer,
  });

  final bool value;
  final Color activeColor;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 48,
          height: 28,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: value ? activeColor : AppColors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 150),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                shape: BoxShape.circle,
                boxShadow: kShadowSm,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
