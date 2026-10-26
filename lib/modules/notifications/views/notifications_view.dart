import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/user_profile.dart';
import '../../../data/services/auth_service.dart';
import '../../../widgets/app_shell.dart';
import '../../../widgets/notification_settings_sheet.dart';
import '../../../widgets/skeleton.dart';
import '../view_model/notifications_view_model.dart';

const _radius = 16.0;
const _cardShadow = [
  BoxShadow(color: Color(0x0D000000), offset: Offset(0, 1), blurRadius: 2),
];

class NotificationsView extends GetView<NotificationsViewModel> {
  const NotificationsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          const AppBackBar(title: 'Notifications & Alerts'),
          Expanded(
            child: SafeArea(
              top: false,
              child: Obx(() {
                final today = controller.visible(today: true);
                final earlier = controller.visible(today: false);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(kMargin, 16, kMargin, 36),
                  children: [
                    const _ContextBar(),
                    const SizedBox(height: 4),
                    _StatusPill(
                      count: controller.unreadCount,
                      loading: controller.loading,
                      failed: controller.loadError != null,
                    ),
                    const SizedBox(height: 4),
                    const _Tabs(),
                    if (today.isNotEmpty)
                      _Group(title: 'Today', items: today, unit: 'updates'),
                    if (today.isNotEmpty && earlier.isNotEmpty)
                      const SizedBox(height: 24),
                    if (earlier.isNotEmpty)
                      _Group(
                        title: 'Yesterday & Earlier',
                        items: earlier,
                        unit: 'items',
                      ),
                    if (today.isEmpty && earlier.isEmpty)
                      if (controller.loadError case final error?)
                        _LoadError(message: error, onRetry: controller.retry)
                      else if (controller.loading)
                        const _ListSkeleton()
                      else
                        _Empty(
                          filtered: controller.tab.value != NotificationTab.all,
                        ),
                    const SizedBox(height: 24),
                    const _PreferencesBanner(),
                    const SizedBox(height: 16),
                    const _PrivacyNote(),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextBar extends GetView<NotificationsViewModel> {
  const _ContextBar();

  @override
  Widget build(BuildContext context) {
    final profiles = Get.find<AuthService>().profiles;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(9999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Obx(() {
                      final p = profiles.activeProfile;
                      final name = p?.fullName ?? 'You';
                      return Text(
                        p?.type == ProfileType.self ? '$name (Primary)' : name,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelSm.copyWith(
                          color: AppColors.onSurface,
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Obx(
              () => TextButton.icon(
                // Nothing to mark: shown, but not tappable.
                onPressed: controller.unreadCount == 0
                    ? null
                    : controller.markAllRead,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  disabledForegroundColor: AppColors.onSurfaceVariant,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  minimumSize: const Size(48, 48),
                  shape: const StadiumBorder(),
                ),
                icon: const Icon(Icons.done_all, size: 18),
                label: Text(
                  'Mark all read',
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelSm,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.count,
    this.loading = false,
    this.failed = false,
  });

  final int count;

  /// No count yet: a placeholder line, never "all caught up".
  final bool loading;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryFixed.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.health_and_safety_outlined,
              size: 22,
              color: AppColors.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Peace of mind, sorted',
                  style: AppTextStyles.titleMd.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
                if (loading)
                  Skeleton(
                    label: 'Loading',
                    child: Bone.text(AppTextStyles.bodySm, widthFactor: 0.8),
                  )
                else
                  Text(
                    failed
                        ? 'Alerts couldn’t be loaded right now'
                        : count == 0
                        ? 'You\'re all caught up today'
                        : '$count ${count == 1 ? 'reminder needs' : 'reminders need'} '
                              'your gentle attention today',
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
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

class _Tabs extends GetView<NotificationsViewModel> {
  const _Tabs();

  static const _labels = {
    NotificationTab.all: 'All',
    NotificationTab.doses: 'Doses',
    NotificationTab.refills: 'Refills',
    NotificationTab.appointments: 'Appointments',
  };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Obx(
        () => Row(
          children: [
            for (final t in NotificationTab.values) ...[
              if (t != NotificationTab.all) const SizedBox(width: 8),
              _Chip(
                label: _labels[t]!,
                count: t == NotificationTab.all
                    ? controller.unreadCount
                    : controller.countFor(t),
                selected: controller.tab.value == t,
                badge: t == NotificationTab.appointments
                    ? AppColors.surfaceContainerHighest
                    : AppColors.secondaryContainer.withValues(alpha: 0.4),
                badgeText: t == NotificationTab.appointments
                    ? AppColors.onSurfaceVariant
                    : AppColors.onSurface,
                onTap: () => controller.tab.value = t,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.count,
    required this.selected,
    required this.badge,
    required this.badgeText,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final Color badge;
  final Color badgeText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.onPrimary : AppColors.onSurface;
    // The chip looks 40px tall (as designed); taps 4px above and below it
    // count too, for a 48dp target.
    return GestureDetector(
      key: ValueKey('chip-$label'),
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Semantics(
          selected: selected,
          button: true,
          label: '$label, $count',
          excludeSemantics: true,
          onTap: onTap,
          child: Material(
            color: selected ? AppColors.primary : AppColors.surfaceContainer,
            shape: const StadiumBorder(),
            elevation: selected ? 1 : 0,
            child: InkWell(
              onTap: onTap,
              customBorder: const StadiumBorder(),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: AppTextStyles.labelMd.copyWith(color: fg),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.onPrimary.withValues(alpha: 0.2)
                              : badge,
                          borderRadius: BorderRadius.circular(9999),
                        ),
                        child: Text(
                          '$count',
                          style: AppTextStyles.labelSm.copyWith(
                            fontSize: 12,
                            height: 1.25,
                            color: selected ? AppColors.onPrimary : badgeText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.items, required this.unit});

  final String title;
  final List<NotificationItem> items;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: AppTextStyles.labelLg.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
              ),
            ),
            Text(
              '${items.length} ${items.length == 1 ? unit.substring(0, unit.length - 1) : unit}',
              style: AppTextStyles.labelSm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        for (final n in items) ...[const SizedBox(height: 16), _Card(item: n)],
      ],
    );
  }
}

class _Card extends GetView<NotificationsViewModel> {
  const _Card({required this.item});

  final NotificationItem item;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final unread = controller.isUnread(item);
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(_radius),
          boxShadow: _cardShadow,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: item.iconBackground,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(item.icon, size: 26, color: item.iconColor),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: unread ? 16 : 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: item.label.toUpperCase(),
                                    style: AppTextStyles.labelSm.copyWith(
                                      color: item.labelColor,
                                      letterSpacing: 0.05 * 12,
                                    ),
                                  ),
                                  TextSpan(
                                    text: '  •  ${item.time}',
                                    style: AppTextStyles.bodySm.copyWith(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.title,
                              style: AppTextStyles.titleLg.copyWith(
                                color: AppColors.onSurface,
                                height: 1.375,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.body,
                              style: AppTextStyles.bodyMd.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                            if (item.action == NotificationAction.details) ...[
                              const SizedBox(height: 12),
                              _LinkButton(
                                label: 'View Dose Details',
                                icon: Icons.arrow_forward,
                                onTap: () => controller.open(item),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                ..._actions(),
              ],
            ),
            if (unread)
              Positioned(
                top: 0,
                right: 0,
                child: Semantics(
                  label: 'Unread alert',
                  child: Container(
                    key: const ValueKey('unread'),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }

  List<Widget> _actions() {
    void open() => controller.open(item);
    switch (item.action) {
      case NotificationAction.takeOrSnooze:
        return [
          const SizedBox(height: 12),
          _PillButton(
            label: 'Take Now & Log',
            icon: Icons.check_circle_outline,
            background: AppColors.primary,
            foreground: AppColors.onPrimary,
            elevated: true,
            busy: controller.isSaving(item),
            onTap: () => controller.take(item),
          ),
          const SizedBox(height: 10),
          _PillButton(
            label: 'Snooze 15m',
            icon: Icons.snooze,
            background: AppColors.surfaceContainer,
            foreground: AppColors.onSurface,
            onTap: () => controller.snooze(item),
          ),
        ];
      case NotificationAction.refill:
        return [
          const SizedBox(height: 12),
          _PillButton(
            label: 'Order Refill / Restock',
            icon: Icons.local_pharmacy_outlined,
            background: AppColors.secondaryContainer,
            foreground: AppColors.onSecondaryContainer,
            onTap: open,
          ),
        ];
      case NotificationAction.directions:
        return [
          const SizedBox(height: 12),
          _PillButton(
            label: 'View Details & Directions',
            icon: Icons.directions_outlined,
            background: AppColors.surfaceContainer,
            foreground: AppColors.onSurface,
            minHeight: 50,
            small: true,
            onTap: open,
          ),
        ];
      case NotificationAction.details:
        return const [];
    }
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.elevated = false,
    this.minHeight = 52,
    this.small = false,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;
  final bool elevated;
  final double minHeight;
  final bool small;

  /// Saving: a spinner replaces the icon and taps are ignored.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final style = small ? AppTextStyles.labelMd : AppTextStyles.labelLg;
    return Material(
      color: background,
      shape: const StadiumBorder(),
      elevation: elevated ? 1 : 0,
      child: InkWell(
        onTap: busy ? null : onTap,
        customBorder: const StadiumBorder(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foreground,
                      semanticsLabel: 'Saving',
                    ),
                  )
                else
                  Icon(icon, size: 20, color: foreground),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: style.copyWith(color: foreground),
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

class _LinkButton extends StatelessWidget {
  const _LinkButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                style: AppTextStyles.labelMd.copyWith(color: AppColors.primary),
              ),
            ),
            const SizedBox(width: 6),
            Icon(icon, size: 16, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

class _PreferencesBanner extends StatelessWidget {
  const _PreferencesBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              shape: BoxShape.circle,
              boxShadow: _cardShadow,
            ),
            child: Icon(Icons.tune, size: 22, color: AppColors.onSurface),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reminder Preferences',
                  style: AppTextStyles.titleMd.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
                Text(
                  'Turn alerts on, allow exact alarm times, or try a test '
                  'alarm.',
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                _LinkButton(
                  label: 'Customize Alert Settings',
                  icon: Icons.chevron_right,
                  onTap: NotificationSettingsSheet.show,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: Column(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.lock_outline,
              size: 18,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 384),
            child: Text(
              'Reminders are scheduled on this device. Medicine details stay '
              'hidden on a locked screen until you unlock your phone.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Alert cards while the profile's schedule loads.
class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      label: 'Loading notifications',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Bone.text(AppTextStyles.labelLg, widthFactor: 0.25),
              ),
              Bone.text(AppTextStyles.labelSm, width: 56),
            ],
          ),
          for (var i = 0; i < 3; i++) ...[
            const SizedBox(height: 16),
            SkeletonCard(
              radius: _radius,
              shadow: _cardShadow,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Bone.circle(size: 48),
                  const SizedBox(width: 16),
                  Expanded(
                    child: BoneColumn(
                      children: [
                        Bone.text(AppTextStyles.labelSm, widthFactor: 0.5),
                        const SizedBox(height: 2),
                        Bone.text(AppTextStyles.titleLg, widthFactor: 0.8),
                        const SizedBox(height: 4),
                        Bone.text(AppTextStyles.bodyMd, widthFactor: 1),
                        Bone.text(AppTextStyles.bodyMd, widthFactor: 0.6),
                      ],
                    ),
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

/// The schedule failed to load: say so, with a way to try again.
class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.cloud_off, size: 28, color: AppColors.primary),
          ),
          const SizedBox(height: 12),
          Text(
            'Couldn’t load your alerts',
            textAlign: TextAlign.center,
            style: AppTextStyles.titleMd.copyWith(color: AppColors.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_none,
              size: 28,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'You\'re all caught up',
            textAlign: TextAlign.center,
            style: AppTextStyles.titleMd.copyWith(color: AppColors.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            filtered
                ? 'Nothing in this category right now.'
                : 'Missed doses, low supplies and upcoming appointments '
                      'will show up here.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
