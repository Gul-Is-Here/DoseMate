import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../widgets/app_shell.dart';
import '../../../widgets/skeleton.dart';
import '../view_model/visit_details_view_model.dart';

/// "label-sm uppercase tracking-wider".
TextStyle _overline(Color color) =>
    AppTextStyles.labelSm.copyWith(color: color, letterSpacing: 1.2);

class VisitDetailsView extends GetView<VisitDetailsViewModel> {
  const VisitDetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          const AppBackBar(title: 'Appointment Details'),
          Expanded(
            child: Obx(
              () => switch (controller.state) {
                VisitDetailsState.loading => const _DetailsSkeleton(),
                VisitDetailsState.error => const _Message(
                  icon: Icons.cloud_off,
                  title: 'Couldn’t load this appointment',
                  retry: true,
                ),
                VisitDetailsState.unavailable => const _Message(
                  icon: Icons.event_busy_outlined,
                  title: 'This appointment is no longer scheduled',
                  body:
                      'It may have been cancelled, deleted or belongs to '
                      'another profile.',
                ),
                VisitDetailsState.ready => const _Details(),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Details extends GetView<VisitDetailsViewModel> {
  const _Details();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: 40 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _StatusRow(),
          Padding(
            padding: const EdgeInsets.fromLTRB(kMargin, 8, kMargin, 0),
            child: Obx(() {
              final v = controller.visit;
              if (v == null) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _HeroCard(),
                  if (controller.hasLocation) ...[
                    const SizedBox(height: kSpaceMd),
                    const _LocationCard(),
                  ],
                  if (v.phone.isNotEmpty) ...[
                    const SizedBox(height: kSpaceMd),
                    const _PhoneCard(),
                  ],
                  if (v.reminders.isNotEmpty || v.departureAlerts) ...[
                    const SizedBox(height: kSpaceMd),
                    const _RemindersCard(),
                  ],
                  if (v.notes.isNotEmpty) ...[
                    const SizedBox(height: kSpaceMd),
                    const _NotesCard(),
                  ],
                  const SizedBox(height: kSpaceMd + 4),
                  const _Actions(),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends GetView<VisitDetailsViewModel> {
  const _StatusRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(kMargin, kSpaceMd, kMargin, 8),
      child: Obx(() {
        final soon = controller.isSoon;
        return Row(
          children: [
            DmDot(
              size: 12,
              color: soon
                  ? AppColors.secondaryContainer
                  : AppColors.primaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                controller.relativeLabel.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _overline(
                  soon ? AppColors.secondary : AppColors.primary,
                ),
              ),
            ),
            if (controller.isSyncing)
              DmTag(
                label: 'Waiting to sync',
                color: AppColors.surfaceContainer,
                textColor: AppColors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
              ),
          ],
        );
      }),
    );
  }
}

/// [_Details] while the appointment loads: status, hero and one section.
class _DetailsSkeleton extends StatelessWidget {
  const _DetailsSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Skeleton(
        label: 'Loading appointment',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(kMargin, kSpaceMd, kMargin, 8),
              child: Row(
                children: [
                  const Bone.circle(size: 12),
                  const SizedBox(width: 8),
                  Bone.text(_overline(AppColors.primary), width: 120),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(kMargin, 8, kMargin, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SkeletonCard(
                    padding: const EdgeInsets.all(kSpaceLg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Bone(width: 56, height: 56, radius: 20),
                            const SizedBox(width: kSpaceMd),
                            Expanded(
                              child: BoneColumn(
                                children: [
                                  Bone.text(
                                    AppTextStyles.headlineLgMobile,
                                    widthFactor: 0.75,
                                  ),
                                  Bone.text(
                                    AppTextStyles.bodyMd,
                                    widthFactor: 0.5,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: kSpaceMd),
                        const Bone(height: 72, radius: kRadiusLg),
                      ],
                    ),
                  ),
                  const SizedBox(height: kSpaceMd),
                  SkeletonCard(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        const Bone.circle(size: 44),
                        const SizedBox(width: 12),
                        Expanded(
                          child: BoneColumn(
                            children: [
                              Bone.text(
                                AppTextStyles.titleMd,
                                widthFactor: 0.5,
                              ),
                              Bone.text(AppTextStyles.bodySm, widthFactor: 0.8),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroCard extends GetView<VisitDetailsViewModel> {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final v = controller.visit;
      if (v == null) return const SizedBox.shrink();
      return DmCard(
        color: AppColors.surfaceContainerLowest,
        shadow: kShadowSm,
        padding: const EdgeInsets.all(kSpaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.calendar_today_outlined,
                    size: 28,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (v.category.isNotEmpty) ...[
                        DmTag(
                          label: v.category,
                          color: AppColors.surfaceContainer,
                          textColor: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          radius: 16,
                        ),
                        const SizedBox(height: 6),
                      ],
                      Text(
                        v.title,
                        style: AppTextStyles.titleLg
                            .copyWith(color: AppColors.onSurface)
                            .weight(FontWeight.w700),
                      ),
                      if (v.doctor.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            v.doctor,
                            style: AppTextStyles.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: kSpaceMd),
            DmCard(
              color: AppColors.surfaceContainerLow,
              radius: 24,
              padding: const EdgeInsets.all(kSpaceMd),
              child: Row(
                children: [
                  Expanded(
                    child: _InfoTile(
                      icon: Icons.event_outlined,
                      label: 'Date',
                      value: controller.dateLabel,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: AppColors.outlineVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _InfoTile(
                      icon: Icons.schedule,
                      label: 'Time',
                      value: controller.timeLabel,
                      suffix: controller.partLabel,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.suffix,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.labelSm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: AppTextStyles.labelLg.copyWith(
                  color: AppColors.onSurface,
                ),
              ),
              if (suffix != null)
                Text(
                  suffix!,
                  style: AppTextStyles.labelSm
                      .copyWith(color: AppColors.onSurfaceVariant)
                      .weight(FontWeight.w400),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Icon, overline, main text and an optional action, shared by the
/// location and phone cards.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.action,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return DmCard(
      color: AppColors.surfaceContainerLowest,
      shadow: kShadowSm,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DmIconCircle(
                size: 44,
                icon: icon,
                iconSize: 22,
                color: AppColors.surfaceContainerHigh,
                iconColor: AppColors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.toUpperCase(),
                      style: _overline(AppColors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    child,
                  ],
                ),
              ),
            ],
          ),
          if (action != null) ...[const SizedBox(height: kSpaceMd), action!],
        ],
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DmPill(
      color: AppColors.surfaceContainer,
      minHeight: 48,
      expand: true,
      onTap: onTap,
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppTextStyles.labelMd.copyWith(color: AppColors.onSurface),
        ),
      ],
    );
  }
}

class _LocationCard extends GetView<VisitDetailsViewModel> {
  const _LocationCard();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final v = controller.visit;
      if (v == null) return const SizedBox.shrink();
      final name = controller.locationName;
      return _SectionCard(
        icon: Icons.location_on_outlined,
        title: 'Location',
        action: _ActionPill(
          icon: Icons.directions_outlined,
          label: 'Directions',
          onTap: controller.directions,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (name.isNotEmpty)
              Text(
                name,
                style: AppTextStyles.titleMd.copyWith(
                  color: AppColors.onSurface,
                ),
              ),
            if (v.address.isNotEmpty && v.address != name)
              Text(
                v.address,
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _PhoneCard extends GetView<VisitDetailsViewModel> {
  const _PhoneCard();

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => _SectionCard(
        icon: Icons.call_outlined,
        title: 'Office Phone',
        action: _ActionPill(
          icon: Icons.call_outlined,
          label: 'Call Office',
          onTap: controller.call,
        ),
        child: Text(
          controller.visit?.phone ?? '',
          style: AppTextStyles.titleMd.copyWith(color: AppColors.onSurface),
        ),
      ),
    );
  }
}

class _RemindersCard extends GetView<VisitDetailsViewModel> {
  const _RemindersCard();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final v = controller.visit;
      if (v == null) return const SizedBox.shrink();
      return _SectionCard(
        icon: Icons.notifications_none,
        title: 'Reminders',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (v.reminders.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final r in v.reminders)
                      DmTag(
                        label: r,
                        color: AppColors.surfaceContainer,
                        textColor: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                      ),
                  ],
                ),
              ),
            if (v.departureAlerts)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Departure alerts on',
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _NotesCard extends GetView<VisitDetailsViewModel> {
  const _NotesCard();

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => DmCard(
        color: AppColors.surfaceContainerLow,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.sticky_note_2_outlined,
                  size: 20,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'NOTES FOR THIS VISIT',
                  style: _overline(AppColors.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              controller.visit?.notes ?? '',
              style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

class _Actions extends GetView<VisitDetailsViewModel> {
  const _Actions();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final busy = controller.busy.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DmWideButton(
            label: 'Edit Appointment',
            icon: Icons.edit_calendar_outlined,
            height: 58,
            color: AppColors.primaryContainer,
            onTap: busy ? null : controller.edit,
          ),
          const SizedBox(height: 12),
          DmPill(
            color: AppColors.surfaceContainerHigh,
            minHeight: 56,
            expand: true,
            onTap: busy ? null : controller.cancelVisit,
            children: [
              Icon(
                Icons.event_busy_outlined,
                size: 20,
                color: AppColors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                'Cancel Visit',
                style: AppTextStyles.labelMd.copyWith(
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
        ],
      );
    });
  }
}

class _Message extends GetView<VisitDetailsViewModel> {
  const _Message({
    required this.icon,
    required this.title,
    this.body,
    this.retry = false,
  });

  final IconData icon;
  final String title;
  final String? body;
  final bool retry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(kMargin),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DmIconCircle(
              size: 64,
              icon: icon,
              iconSize: 32,
              color: AppColors.surfaceContainer,
              iconColor: AppColors.primary,
            ),
            const SizedBox(height: kSpaceMd),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleMd.copyWith(color: AppColors.onSurface),
            ),
            const SizedBox(height: 4),
            if (retry)
              Obx(
                () => Text(
                  controller.loadError ?? 'Please try again.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              )
            else
              Text(
                body!,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: kSpaceLg),
            DmWideButton(
              label: retry ? 'Retry' : 'Go Back',
              icon: retry ? Icons.refresh : Icons.arrow_back,
              height: 48,
              onTap: retry ? controller.retry : controller.close,
            ),
          ],
        ),
      ),
    );
  }
}
