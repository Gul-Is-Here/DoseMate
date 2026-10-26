import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/care_dates.dart';
import '../../../data/models/medicine.dart';
import '../../../data/services/care_service.dart';
import '../../../widgets/app_shell.dart';
import '../../../widgets/skeleton.dart';
import '../view_model/medicines_view_model.dart';

Color get _error => AppColors.error;
const _shadowXl = [
  BoxShadow(
    color: Color(0x1A000000),
    offset: Offset(0, 20),
    blurRadius: 25,
    spreadRadius: -5,
  ),
  BoxShadow(
    color: Color(0x1A000000),
    offset: Offset(0, 8),
    blurRadius: 10,
    spreadRadius: -6,
  ),
];

TextStyle get _sectionLabel => AppTextStyles.labelSm
    .copyWith(color: AppColors.onSurfaceVariant, letterSpacing: 0.6)
    .weight(FontWeight.w600);

class MedicinesView extends GetView<MedicinesViewModel> {
  const MedicinesView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          const AppTopBar(),
          Expanded(
            child: ListView(
              // Room for the floating Add button at the end of the list.
              padding: const EdgeInsets.only(top: 8, bottom: 40 + 56 + 24),
              children: [
                const _Header(),
                const SizedBox(height: kSpaceMd),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: kMargin),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Obx(
                        () => switch (controller.care.status.value) {
                          CareStatus.error => const _ErrorCard(),
                          CareStatus.ready => const _MedicineList(),
                          _ => const _ListSkeleton(),
                        },
                      ),
                      const SizedBox(height: kSpaceMd),
                      const _CareBanner(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(right: kMargin - 16),
        child: DmPill(
          onTap: controller.add,
          color: AppColors.primaryContainer,
          minHeight: 56,
          shadow: _shadowXl,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: [
            Icon(Icons.add, size: 24, color: AppColors.onPrimary),
            const SizedBox(width: 8),
            Text(
              'Add New Medicine',
              style: AppTextStyles.labelLg
                  .copyWith(color: AppColors.onPrimary)
                  .weight(FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends GetView<MedicinesViewModel> {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.medication_outlined,
                size: 22,
                color: AppColors.primary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Medications',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.headlineLgMobile.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: DmPill(
                  tooltip: 'Switch active profile',
                  onTap: controller.isSignedIn ? controller.openProfiles : null,
                  color: AppColors.surfaceContainer,
                  shadow: kShadowSm,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  children: [
                    DmDot(size: 8, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Obx(
                        () => Text(
                          '${controller.firstName ?? 'Profile'} (Active)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.labelSm
                              .copyWith(color: AppColors.onSurface)
                              .weight(FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.tune,
                      size: 16,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const _Segments(),
        ],
      ),
    );
  }
}

class _Segments extends GetView<MedicinesViewModel> {
  const _Segments();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Obx(() {
        final selected = controller.segment.value;
        final ready = controller.care.status.value == CareStatus.ready;
        Widget segment(int index, String label, int count) => Expanded(
          child: Semantics(
            button: true,
            selected: selected == index,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => controller.selectSegment(index),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: selected == index
                    ? BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: kShadowSm,
                      )
                    : null,
                child: _SegmentLabel(
                  label: label,
                  count: ready ? count : null,
                  selected: selected == index,
                ),
              ),
            ),
          ),
        );
        return Row(
          children: [
            segment(0, 'Active', controller.active.length),
            segment(1, 'Archived / Paused', controller.inactive.length),
          ],
        );
      }),
    );
  }
}

class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel({
    required this.label,
    required this.count,
    required this.selected,
  });

  final String label;

  /// Null while loading: the badge stays, without a number.
  final int? count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelMd
                .copyWith(
                  color: selected
                      ? AppColors.onSurface
                      : AppColors.onSurfaceVariant,
                )
                .weight(selected ? FontWeight.w700 : FontWeight.w600),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary
                : AppColors.surfaceContainerHighest,
            shape: BoxShape.circle,
          ),
          child: Text(
            count == null ? '' : '$count',
            style: AppTextStyles.labelSm
                .copyWith(
                  fontSize: 11,
                  height: 1,
                  letterSpacing: 0,
                  color: selected
                      ? AppColors.onPrimary
                      : AppColors.onSurfaceVariant,
                )
                .weight(selected ? FontWeight.w700 : FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _ErrorCard extends GetView<MedicinesViewModel> {
  const _ErrorCard();

  @override
  Widget build(BuildContext context) {
    return DmCard(
      color: AppColors.surfaceContainerLowest,
      shadow: kShadowSm,
      padding: const EdgeInsets.all(kSpaceLg),
      child: Column(
        children: [
          Icon(Icons.cloud_off, size: 36, color: AppColors.secondary),
          const SizedBox(height: 12),
          Obx(
            () => Text(
              controller.care.error.value ?? 'Couldn’t load medicines.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: kSpaceMd),
          DmWideButton(
            label: 'Retry',
            icon: Icons.refresh,
            height: 48,
            onTap: controller.retry,
          ),
        ],
      ),
    );
  }
}

/// The medicine cards while the profile's medicines load.
class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      label: 'Loading medicines',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(height: kSpaceMd),
            const _TileSkeleton(),
          ],
        ],
      ),
    );
  }
}

/// A compact [_MedicineTile]: header, routine line and one chip.
class _TileSkeleton extends StatelessWidget {
  const _TileSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonCard(
      padding: const EdgeInsets.fromLTRB(
        kSpaceLg + 4,
        kSpaceLg,
        kSpaceLg,
        kSpaceLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Bone.circle(size: 48),
              const SizedBox(width: kSpaceMd),
              Expanded(
                child: BoneColumn(
                  children: [
                    Bone.text(AppTextStyles.titleLg, widthFactor: 0.65),
                    Bone.text(AppTextStyles.bodyMd, widthFactor: 0.45),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Bone.circle(size: 40),
            ],
          ),
          const SizedBox(height: kSpaceMd),
          Row(
            children: [
              const Bone.circle(size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Bone.text(AppTextStyles.bodyMd, widthFactor: 0.7),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Bone(width: 150, height: 28, radius: 999),
        ],
      ),
    );
  }
}

class _MedicineList extends GetView<MedicinesViewModel> {
  const _MedicineList();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final list = controller.shown;
      if (list.isEmpty) {
        final active = controller.segment.value == 0;
        return DmCard(
          color: AppColors.surfaceContainerLowest,
          shadow: kShadowSm,
          padding: const EdgeInsets.all(kSpaceLg),
          child: Column(
            children: [
              DmIconCircle(
                size: 56,
                icon: Icons.medication_outlined,
                iconSize: 30,
                color: AppColors.surfaceContainer,
                iconColor: AppColors.primary,
              ),
              const SizedBox(height: 12),
              Text(
                active
                    ? 'No active medicines yet'
                    : 'Nothing archived or paused',
                textAlign: TextAlign.center,
                style: AppTextStyles.titleMd.copyWith(
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                active
                    ? 'Tap Add New Medicine to start a schedule.'
                    : 'Paused, archived and draft medicines appear here.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, m) in list.indexed) ...[
            if (i > 0) const SizedBox(height: kSpaceMd),
            _MedicineTile(
              key: ValueKey(m.id),
              medicine: m,
              expanded: controller.expanded.contains(m.id),
            ),
          ],
        ],
      );
    });
  }
}

/// One saved medicine: compact by default, with the details drawer and
/// controls when expanded.
class _MedicineTile extends GetView<MedicinesViewModel> {
  const _MedicineTile({
    super.key,
    required this.medicine,
    required this.expanded,
  });

  final Medicine medicine;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final m = medicine;
    final low = m.isLowSupply;
    final care = controller.care;
    final taken = care.takenToday(m.id);
    final streak = care.streak(m);
    return _MedicineCard(
      accent: low ? AppColors.secondaryContainer : AppColors.primaryContainer,
      shadow: expanded ? kShadowMd : kShadowSm,
      children: [
        _CardHeader(
          icon: low ? Icons.medication_outlined : Icons.medication_liquid,
          iconColor: low ? AppColors.secondary : AppColors.primary,
          iconBackground: low
              ? AppColors.secondaryFixed
              : AppColors.primaryFixed,
          name: m.name,
          tag: controller.tagFor(m),
          tagColor: low
              ? AppColors.secondaryFixed
              : AppColors.surfaceContainerLow,
          tagTextColor: low
              ? AppColors.onSecondaryFixedVariant
              : AppColors.onSurface,
          subtitle: controller.subtitleFor(m),
          toggleIcon: expanded ? Icons.unfold_less : Icons.expand_more,
          toggleColor: expanded
              ? AppColors.primary
              : AppColors.onSurfaceVariant,
          toggleLabel: expanded ? 'Hide details' : 'Expand details',
          onToggle: () => controller.toggle(m),
          onOpen: () => controller.openDetails(m),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  expanded ? Icons.schedule : Icons.wb_twilight,
                  size: expanded ? 20 : 18,
                  color: expanded
                      ? AppColors.secondary
                      : AppColors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    expanded
                        ? controller.scheduleLine(m)
                        : controller.routineLine(m),
                    style: AppTextStyles.bodyMd.copyWith(
                      color: expanded
                          ? AppColors.onSurface
                          : AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (low)
                  _Chip(
                    icon: Icons.warning_amber_rounded,
                    iconColor: AppColors.secondary,
                    color: AppColors.secondaryFixed,
                    textColor: AppColors.onSecondaryFixed,
                    label: 'Low Supply: ~${m.quantity} doses left',
                  )
                else if (m.lowSupplyWarning)
                  _Chip(
                    icon: Icons.inventory_2_outlined,
                    iconColor: AppColors.onSurfaceVariant,
                    color: AppColors.surfaceContainer,
                    textColor: AppColors.onSurface,
                    label: '${m.quantity} doses remaining',
                  ),
                if (taken != null)
                  _Chip(
                    icon: Icons.check_circle,
                    iconColor: AppColors.primary,
                    color: AppColors.primaryFixed,
                    textColor: AppColors.onPrimaryFixedVariant,
                    label:
                        'Taken today at ${CareDates.clockOf(taken.shownTime)}',
                  ),
              ],
            ),
          ],
        ),
        if (m.isActive)
          Row(
            children: [
              Expanded(
                child: DmPill(
                  onTap: controller.canLog(m)
                      ? () => controller.logDose(m)
                      : null,
                  color: controller.canLog(m)
                      ? AppColors.primary
                      : AppColors.surfaceContainerHigh,
                  minHeight: 56,
                  expand: true,
                  shadow: kShadowSm,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 22,
                      color: controller.canLog(m)
                          ? AppColors.onPrimary
                          : AppColors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        controller.canLog(m) ? 'Log Dose' : 'All Logged',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelLg
                            .copyWith(
                              color: controller.canLog(m)
                                  ? AppColors.onPrimary
                                  : AppColors.onSurfaceVariant,
                            )
                            .weight(FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DmPill(
                  onTap: () => controller.toggle(m),
                  color: AppColors.surfaceContainerLow,
                  minHeight: 56,
                  expand: true,
                  children: [
                    Icon(Icons.tune, size: 22, color: AppColors.onSurface),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Details',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelLg.copyWith(
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        if (!expanded)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(Icons.history, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    streak == 0
                        ? 'No streak yet'
                        : 'Streak: $streak '
                              '${streak == 1 ? 'day' : 'days'} consecutive',
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DmPill(
                  onTap: () => controller.toggle(m),
                  color: AppColors.surfaceContainerLow,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  children: [
                    Text(
                      'View History',
                      style: AppTextStyles.labelMd.copyWith(
                        color: AppColors.onSurface,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (expanded) _Details(medicine: m),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.iconColor,
    required this.color,
    required this.textColor,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final Color color;
  final Color textColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DmPill(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: AppTextStyles.labelMd.copyWith(color: textColor),
          ),
        ),
      ],
    );
  }
}

/// White medicine card with the coloured accent strip on the left.
class _MedicineCard extends StatelessWidget {
  const _MedicineCard({
    required this.accent,
    required this.shadow,
    required this.children,
  });

  final Color accent;
  final List<BoxShadow> shadow;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(kRadiusLg),
        boxShadow: shadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 6,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(999),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              kSpaceLg + 4,
              kSpaceLg,
              kSpaceLg,
              kSpaceLg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, child) in children.indexed) ...[
                  if (i > 0) const SizedBox(height: kSpaceMd),
                  child,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.name,
    required this.tag,
    required this.tagColor,
    required this.tagTextColor,
    required this.subtitle,
    required this.toggleIcon,
    required this.toggleColor,
    required this.toggleLabel,
    required this.onToggle,
    this.onOpen,
  });

  /// Opens Medication Details.
  final VoidCallback? onOpen;

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String name;
  final String tag;
  final Color tagColor;
  final Color tagTextColor;
  final String subtitle;
  final IconData toggleIcon;
  final Color toggleColor;
  final String toggleLabel;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DmIconCircle(
          size: 48,
          icon: icon,
          iconSize: 28,
          color: iconBackground,
          iconColor: iconColor,
        ),
        const SizedBox(width: kSpaceMd),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpen,
            child: Semantics(
              button: onOpen != null,
              label: onOpen == null ? null : 'Open $name details',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.titleLg
                              .copyWith(color: AppColors.onSurface)
                              .weight(FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DmTag(
                        label: tag,
                        color: tagColor,
                        textColor: tagTextColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ],
                  ),
                  Text(
                    subtitle,
                    style: AppTextStyles.bodyMd.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: toggleLabel,
          child: Material(
            color: AppColors.surfaceContainerLow,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onToggle,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(toggleIcon, size: 22, color: toggleColor),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Rounded-16 white box used inside the details drawer.
class _Box extends StatelessWidget {
  const _Box({required this.child, this.padding = const EdgeInsets.all(12)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: kShadowSm,
      ),
      child: child,
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.children, this.gap = 4});

  final String label;
  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label.toUpperCase(), style: _sectionLabel),
        for (final child in children) ...[SizedBox(height: gap), child],
      ],
    );
  }
}

class _Details extends GetView<MedicinesViewModel> {
  const _Details({required this.medicine});

  final Medicine medicine;

  @override
  Widget build(BuildContext context) {
    final m = medicine;
    final logs = controller.care.recentLogs(m.id);
    final body = AppTextStyles.bodyMd
        .copyWith(color: AppColors.onSurface)
        .weight(FontWeight.w500);
    return Container(
      padding: const EdgeInsets.all(kSpaceMd),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Section(
            label: 'Instructions',
            children: [
              _Box(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.restaurant,
                        size: 20,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        m.notes.isEmpty ? 'No instructions added.' : m.notes,
                        style: body,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: kSpaceMd),
          _Section(
            label: 'Course Duration',
            children: [
              _Box(
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 20,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(controller.courseLabel(m), style: body),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        controller.endsLabel(m),
                        style: AppTextStyles.labelMd
                            .copyWith(color: AppColors.onSurfaceVariant)
                            .weight(FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: kSpaceMd),
          _RunOutBox(medicine: m),
          const SizedBox(height: kSpaceMd),
          _Section(
            label: 'Recent Logs',
            children: [
              if (logs.isEmpty)
                Text(
                  'No doses logged in the last 30 days.',
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              for (final log in logs)
                _LogRow(
                  day: controller.logDay(log),
                  time: controller.takenLabel(log),
                  taken: log.status == DoseStatus.taken,
                ),
            ],
          ),
          const SizedBox(height: kSpaceMd + 4),
          _ScheduleControls(medicine: m),
        ],
      ),
    );
  }
}

class _RunOutBox extends GetView<MedicinesViewModel> {
  const _RunOutBox({required this.medicine});

  final Medicine medicine;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(kSpaceMd),
      decoration: BoxDecoration(
        color: AppColors.secondaryFixed.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.event_repeat, size: 22, color: AppColors.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.runOutTitle(medicine),
                      style: AppTextStyles.labelMd
                          .copyWith(color: AppColors.onSecondaryFixed)
                          .weight(FontWeight.w700),
                    ),
                    Text(
                      controller.runOutDetail(medicine),
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.onSecondaryFixedVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DmPill(
            onTap: () => controller.markRefill(medicine),
            color: AppColors.secondary,
            minHeight: 48,
            expand: true,
            shadow: kShadowSm,
            children: [
              Icon(
                Icons.shopping_bag_outlined,
                size: 18,
                color: AppColors.onPrimary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Mark Refill Purchased',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelMd.copyWith(
                    color: AppColors.onPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.day, required this.time, required this.taken});

  final String day;
  final String time;
  final bool taken;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: _Box(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Icon(
              taken ? Icons.check_circle : Icons.cancel_outlined,
              size: 18,
              color: taken ? AppColors.success : AppColors.neutral,
            ),
            const SizedBox(width: 8),
            Flexible(
              fit: FlexFit.tight,
              child: Text(
                day,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                time,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelSm
                    .copyWith(color: AppColors.onSurfaceVariant)
                    .weight(FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleControls extends GetView<MedicinesViewModel> {
  const _ScheduleControls({required this.medicine});

  final Medicine medicine;

  @override
  Widget build(BuildContext context) {
    final m = medicine;
    final label = AppTextStyles.labelMd.copyWith(color: AppColors.onSurface);
    final paused = m.status == MedicineStatus.paused;
    final archived = m.status == MedicineStatus.archived;
    return _Section(
      label: 'Schedule Controls',
      gap: 8,
      children: [
        _ControlButton(
          icon: Icons.edit_calendar_outlined,
          label: m.status == MedicineStatus.draft
              ? 'Finish Setup'
              : 'Edit Schedule & Routine',
          color: AppColors.onSurface,
          iconColor: AppColors.onSurfaceVariant,
          onTap: () => controller.edit(m),
        ),
        if (m.isActive || paused)
          _Box(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => controller.togglePause(m),
                  child: Row(
                    children: [
                      Icon(
                        paused
                            ? Icons.play_circle_outline
                            : Icons.pause_circle_outline,
                        size: 20,
                        color: AppColors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          paused ? 'Resume Reminders' : 'Pause Reminders',
                          style: label,
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 18,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 32),
                  child: Text(
                    'Temporarily pause this item. Paused medicines leave '
                    'today’s schedule. DoseMate records your preference.',
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        _ControlButton(
          icon: archived ? Icons.unarchive_outlined : Icons.archive_outlined,
          label: archived ? 'Restore Medicine' : 'Archive Medicine',
          color: archived ? AppColors.onSurface : _error,
          iconColor: archived ? AppColors.onSurfaceVariant : _error,
          onTap: () => controller.archive(m),
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DmPill(
      onTap: onTap,
      color: AppColors.surfaceContainerLowest,
      minHeight: 48,
      expand: true,
      shadow: kShadowSm,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelMd.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _CareBanner extends GetView<MedicinesViewModel> {
  const _CareBanner();

  @override
  Widget build(BuildContext context) {
    return DmCard(
      color: AppColors.surfaceContainerLow,
      padding: const EdgeInsets.all(kSpaceMd),
      child: Row(
        children: [
          DmIconCircle(
            size: 40,
            icon: Icons.chevron_left,
            iconSize: 22,
            color: AppColors.surfaceContainerLowest,
            iconColor: AppColors.primary,
            shadow: kShadowSm,
          ),
          const SizedBox(width: kSpaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Need help organizing refills?',
                  style: AppTextStyles.labelMd.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
                Obx(() {
                  final name = controller.firstName;
                  return Text(
                    'DoseMate shares refill alerts with '
                    '${name == null ? 'the' : '$name’s'} linked caregiver '
                    'network automatically.',
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
