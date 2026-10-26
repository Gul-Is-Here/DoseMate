import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../app/routes/app_routes.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../data/models/user_profile.dart';
import '../data/services/auth_service.dart';
import 'profile_avatar.dart';
import 'profile_switcher_sheet.dart';
import 'app_logo.dart';

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
                            DmDot(size: 8, color: AppColors.primary),
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
                            Icon(
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
                const _AccountMenu(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The DoseMate mark in the top bar.
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return const AppLogo();
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
                  icon: Icon(
                    Icons.arrow_back,
                    size: 24,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(width: 4),
                const AppLogo(size: 28),
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

/// The main tab bar. Selecting a tab only reports it through [onSelect];
/// the shell switches content in place.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.activeIndex,
    required this.onSelect,
  });

  /// 0 Home, 1 Medicines, 2 Calendar, 3 History, 4 Settings.
  final int activeIndex;
  final ValueChanged<int> onSelect;

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.medication_outlined, Icons.medication_rounded, 'Medicines'),
    (Icons.calendar_month_outlined, Icons.calendar_month_rounded, 'Calendar'),
    (Icons.fact_check_outlined, Icons.fact_check_rounded, 'History'),
    (Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
  ];

  /// Tabs with a screen.
  static const _enabledTabs = 5;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14132238),
            offset: Offset(0, -4),
            blurRadius: 24,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 4),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: Row(
            children: [
              for (final (index, (icon, activeIcon, label)) in _items.indexed)
                Expanded(
                  child: _NavItem(
                    icon: icon,
                    activeIcon: activeIcon,
                    label: label,
                    active: index == activeIndex,
                    enabled: index < _enabledTabs,
                    onTap: () => onSelect(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  static const _duration = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    final color = active
        ? AppColors.primary
        : enabled
        ? AppColors.onSurfaceVariant
        : AppColors.outline;
    return Semantics(
      selected: active,
      button: true,
      enabled: enabled,
      label: enabled ? label : '$label, coming soon',
      excludeSemantics: true,
      child: Tooltip(
        message: enabled ? label : '$label is coming soon',
        excludeFromSemantics: true,
        child: InkResponse(
          onTap: enabled ? onTap : null,
          containedInkWell: true,
          highlightShape: BoxShape.rectangle,
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: _duration,
                  curve: Curves.easeOutCubic,
                  width: active ? 56 : 40,
                  height: 32,
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.primaryFixed.withValues(alpha: 0.55)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: AnimatedSwitcher(
                    duration: _duration,
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: Tween(begin: 0.85, end: 1.0).animate(animation),
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: Icon(
                      active ? activeIcon : icon,
                      key: ValueKey(active),
                      size: 24,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // Long labels shrink instead of wrapping or overflowing on
                // narrow phones and with large text.
                SizedBox(
                  height: 16,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: AnimatedDefaultTextStyle(
                      duration: _duration,
                      style: AppTextStyles.labelSm
                          .copyWith(color: color)
                          .weight(active ? FontWeight.w700 : FontWeight.w500),
                      child: Text(
                        label,
                        maxLines: 1,
                        textScaler: _labelScaler(context),
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

  /// Large text grows labels a little, then the fit above takes over.
  static TextScaler _labelScaler(BuildContext context) =>
      MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
}

// Small building blocks.

class DmCard extends StatelessWidget {
  const DmCard({
    super.key,
    required this.color,
    required this.padding,
    required this.child,
    this.shadow,
    this.radius = kRadiusLg,
  });

  final Color color;
  final EdgeInsets padding;
  final Widget child;
  final List<BoxShadow>? shadow;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
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

/// A bar pinned under a form that keeps its main actions on screen,
/// above the keyboard and the home indicator.
class DmActionBar extends StatelessWidget {
  const DmActionBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border(top: BorderSide(color: AppColors.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(kMargin, 12, kMargin, 0),
          child: child,
        ),
      ),
    );
  }
}

class DmWideButton extends StatelessWidget {
  const DmWideButton({
    super.key,
    required this.label,
    required this.icon,
    required this.height,
    required this.onTap,
    this.color,
    this.compact = false,
  });

  final String label;
  final IconData icon;
  final double height;

  /// Smaller icon and label, for a pinned action bar.
  final bool compact;

  /// Null shows the button disabled (e.g. while saving).
  final VoidCallback? onTap;

  /// Defaults to the primary colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    // Disabled: a muted surface with readable text, in either theme.
    final fg = enabled ? AppColors.onPrimary : AppColors.onSurfaceVariant;
    return DmPill(
      onTap: onTap,
      color: enabled ? color ?? AppColors.primary : AppColors.divider,
      minHeight: height,
      expand: true,
      shadow: enabled ? kShadowMd : null,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        Icon(icon, size: compact ? 18 : 22, color: fg),
        SizedBox(width: compact ? 6 : 8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: compact
                ? AppTextStyles.labelMd.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  )
                : AppTextStyles.labelLg.copyWith(color: fg),
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
    this.activeColor,
  });

  final bool value;

  /// Defaults to the primary colour.
  final Color? activeColor;
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
            color: value
                ? activeColor ?? AppColors.primaryContainer
                : AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(999),
            // Off: an outlined track, so it reads on any surface.
            border: Border.all(
              color: value
                  ? activeColor ?? AppColors.primaryContainer
                  : AppColors.outline,
            ),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 150),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: value ? AppColors.onPrimary : AppColors.outline,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
