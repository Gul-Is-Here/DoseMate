import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/care_dates.dart';
import '../../../data/models/medicine.dart';
import '../../../data/models/visit.dart';
import '../../../data/services/care_service.dart';
import '../../../widgets/app_shell.dart';
import '../../../widgets/profile_avatar.dart';
import '../view_model/home_view_model.dart';

class HomeView extends GetView<HomeViewModel> {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          const AppTopBar(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(kMargin, 10, kMargin, 36),
              children: [
                const _GreetingHeader(),
                const SizedBox(height: kSpaceMd),
                const _ProgressRibbon(),
                const SizedBox(height: kSpaceMd),
                Obx(
                  () => switch (controller.status) {
                    CareStatus.error => const _ErrorState(),
                    CareStatus.ready when controller.isEmpty =>
                      const _EmptyState(),
                    CareStatus.ready => const _PopulatedFeed(),
                    _ => const _LoadingState(),
                  },
                ),
                const SizedBox(height: kSpaceMd + 8),
                const _QuickActions(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(activeIndex: 0),
    );
  }
}

class _GreetingHeader extends GetView<HomeViewModel> {
  const _GreetingHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: kShadowSm,
              ),
              child: Obx(
                () => ProfileAvatar(
                  size: 48,
                  url: controller.activeProfile?.photoUrl,
                ),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 2),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hello there,',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              Obx(
                () => Text(
                  controller.greeting(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.headlineLgMobile.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        DmPill(
          tooltip: 'Switch active profile',
          onTap: controller.isSignedIn ? controller.openProfiles : null,
          color: AppColors.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shadow: kShadowSm,
          children: [
            const Icon(
              Icons.person_outline,
              size: 16,
              color: AppColors.primary,
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 100),
              child: Obx(
                () => Text(
                  controller.profileChipLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelSm.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: AppColors.onSurfaceVariant,
            ),
          ],
        ),
      ],
    );
  }
}

class _ProgressRibbon extends GetView<HomeViewModel> {
  const _ProgressRibbon();

  @override
  Widget build(BuildContext context) {
    return DmCard(
      color: AppColors.surfaceContainerLow,
      padding: const EdgeInsets.all(kSpaceMd),
      child: Obx(() {
        final ready = controller.status == CareStatus.ready;
        final total = ready ? controller.todaysDoses.length : 0;
        final taken = ready ? controller.takenToday : 0;
        return Row(
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 31,
                    height: 31,
                    child: CircularProgressIndicator(
                      value: ready ? controller.progress : null,
                      strokeWidth: 3.5,
                      strokeCap: StrokeCap.round,
                      color: AppColors.primary,
                      backgroundColor: AppColors.surfaceContainerHighest,
                    ),
                  ),
                  if (ready)
                    Text(
                      '$taken/$total',
                      style: AppTextStyles.labelSm.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ready ? controller.progressTitle : 'Loading today’s doses',
                    style: AppTextStyles.titleMd.copyWith(
                      color: AppColors.onSurface,
                    ),
                  ),
                  if (ready)
                    Text(
                      controller.progressSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const DmCard(
      color: AppColors.surfaceContainerLowest,
      shadow: kShadowSm,
      padding: EdgeInsets.all(36),
      child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
    );
  }
}

class _ErrorState extends GetView<HomeViewModel> {
  const _ErrorState();

  @override
  Widget build(BuildContext context) {
    return DmCard(
      color: AppColors.surfaceContainerLowest,
      shadow: kShadowSm,
      padding: const EdgeInsets.all(kSpaceLg),
      child: Column(
        children: [
          const Icon(Icons.cloud_off, size: 36, color: AppColors.secondary),
          const SizedBox(height: 12),
          Text(
            'Couldn’t load the schedule',
            textAlign: TextAlign.center,
            style: AppTextStyles.titleMd.copyWith(color: AppColors.onSurface),
          ),
          const SizedBox(height: 4),
          Obx(
            () => Text(
              controller.care.error.value ?? 'Please try again.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySm.copyWith(
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

class _EmptyState extends GetView<HomeViewModel> {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final name = controller.firstName;
    return DmCard(
      color: AppColors.surfaceContainerLowest,
      shadow: kShadowSm,
      padding: const EdgeInsets.all(36),
      child: Column(
        children: [
          const DmIconCircle(
            size: 64,
            icon: Icons.wb_sunny_outlined,
            iconSize: 36,
            color: AppColors.surfaceContainer,
            iconColor: AppColors.primary,
          ),
          const SizedBox(height: 20),
          Text(
            'No schedules created yet',
            textAlign: TextAlign.center,
            style: AppTextStyles.titleLg.copyWith(color: AppColors.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            'Set up ${name == null ? 'the' : '$name’s'} first medication '
            'routine or doctor appointment to activate automatic daily care '
            'checklists.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          DmWideButton(
            label: 'Add First Medicine',
            icon: Icons.add,
            height: 56,
            onTap: controller.addMedicine,
          ),
          const SizedBox(height: 8),
          DmPill(
            onTap: controller.addVisit,
            color: AppColors.surfaceContainer,
            padding: const EdgeInsets.symmetric(vertical: 10),
            expand: true,
            children: [
              Flexible(
                child: Text(
                  'Schedule a Doctor Visit',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelMd.copyWith(
                    color: AppColors.onSurface,
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

class _PopulatedFeed extends GetView<HomeViewModel> {
  const _PopulatedFeed();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Obx(() {
          final medicine = controller.refillDue;
          return medicine == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: kSpaceMd),
                  child: _RefillBanner(medicine: medicine),
                );
        }),
        Obx(() {
          final next = controller.nextDose;
          final feedback = controller.feedback.value;
          if (next == null && feedback == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: kSpaceMd + 4),
            child: _NextDoseCard(occurrence: next, feedback: feedback),
          );
        }),
        Obx(() {
          final doses = controller.todaysDoses;
          final count = doses.length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Today’s Care Timeline',
                          style: AppTextStyles.titleLg
                              .copyWith(color: AppColors.onSurface)
                              .weight(FontWeight.w700),
                        ),
                        Text(
                          '${CareDates.long(controller.care.today.value)} • '
                          'Scheduled routines',
                          style: AppTextStyles.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  DmTag(
                    label: '$count ${count == 1 ? 'Event' : 'Events'}',
                    color: AppColors.surfaceContainer,
                    textColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: kSpaceMd),
              if (doses.isEmpty)
                Text(
                  'No doses are scheduled for today.',
                  style: AppTextStyles.bodyMd.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              for (final (i, o) in doses.indexed) ...[
                if (i > 0) const SizedBox(height: 8),
                _TimelineItem.of(o, controller),
              ],
            ],
          );
        }),
        Obx(() {
          final visit = controller.nextVisit;
          return visit == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: kSpaceMd + 4),
                  child: _AppointmentSection(visit: visit),
                );
        }),
      ],
    );
  }
}

class _RefillBanner extends GetView<HomeViewModel> {
  const _RefillBanner({required this.medicine});

  final Medicine medicine;

  @override
  Widget build(BuildContext context) {
    return DmCard(
      color: AppColors.secondaryFixed,
      shadow: kShadowSm,
      padding: const EdgeInsets.all(kSpaceMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: DmIconCircle(
              size: 36,
              icon: Icons.inventory_2_outlined,
              iconSize: 20,
              color: AppColors.secondaryContainer,
              iconColor: AppColors.onPrimary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Refill Reminder',
                      style: AppTextStyles.titleMd
                          .copyWith(color: AppColors.onSecondaryFixed)
                          .weight(FontWeight.w700),
                    ),
                    DmTag(
                      label:
                          '${medicine.quantity} '
                          '${medicine.quantity == 1 ? 'dose' : 'doses'} left',
                      color: AppColors.onSecondaryFixed,
                      textColor: AppColors.secondaryFixed,
                      fontWeight: FontWeight.w600,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  controller.refillMessage(medicine),
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.onSecondaryFixedVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Flexible(
                      child: DmPill(
                        onTap: () => controller.markRefill(medicine),
                        color: AppColors.secondary,
                        shadow: kShadowSm,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        children: [
                          Flexible(
                            child: Text(
                              'Refill Details & Mark Purchased',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.labelMd.copyWith(
                                color: AppColors.onPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Dismiss alert',
                      onPressed: () => controller.dismissRefill(medicine),
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.close,
                        size: 18,
                        color: AppColors.onSecondaryFixed,
                      ),
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
}

/// The next dose to act on, or (once all are logged) just the last action
/// with its Undo.
class _NextDoseCard extends GetView<HomeViewModel> {
  const _NextDoseCard({required this.occurrence, required this.feedback});

  final DoseOccurrence? occurrence;
  final DoseFeedback? feedback;

  @override
  Widget build(BuildContext context) {
    final o = occurrence;
    final m = o?.medicine;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(kRadiusLg),
        boxShadow: kShadowMd,
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 8, color: AppColors.secondaryContainer),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  kSpaceLg,
                  kSpaceLg,
                  kSpaceLg,
                  kSpaceLg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (o != null && m != null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: DmPill(
                                color: AppColors.secondaryFixed,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                children: [
                                  const DmDot(
                                    size: 8,
                                    color: AppColors.secondaryContainer,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      controller.nextDoseLabel(o),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTextStyles.labelSm.copyWith(
                                        color: AppColors.onSecondaryFixed,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.hourglass_top,
                            size: 16,
                            color: AppColors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            controller.countdown(o),
                            style: AppTextStyles.labelSm
                                .copyWith(color: AppColors.onSurfaceVariant)
                                .weight(FontWeight.w500),
                          ),
                        ],
                      ),
                      const SizedBox(height: kSpaceMd),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.name,
                                  style: AppTextStyles.headlineLgMobile
                                      .copyWith(
                                        color: AppColors.onSurface,
                                        letterSpacing: -0.6,
                                      ),
                                ),
                                if (m.dosage.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    m.dosage,
                                    style: AppTextStyles.titleMd.copyWith(
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                                if (m.notes.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Padding(
                                        padding: EdgeInsets.only(top: 1),
                                        child: Icon(
                                          Icons.restaurant,
                                          size: 18,
                                          color: AppColors.secondary,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          'User note: ${m.notes}',
                                          style: AppTextStyles.bodySm.copyWith(
                                            color: AppColors.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const DmIconCircle(
                            size: 56,
                            icon: Icons.medication_outlined,
                            iconSize: 32,
                            color: AppColors.surfaceContainerHigh,
                            iconColor: AppColors.primary,
                            shadow: kShadowSm,
                          ),
                        ],
                      ),
                      const SizedBox(height: kSpaceMd),
                      _DoseButtons(occurrence: o),
                    ] else
                      Text(
                        'All of today’s doses are logged.',
                        style: AppTextStyles.titleMd.copyWith(
                          color: AppColors.onSurface,
                        ),
                      ),
                    if (feedback case final f?) ...[
                      const SizedBox(height: kSpaceMd),
                      _DoseFeedback(feedback: f),
                    ],
                    const SizedBox(height: kSpaceMd),
                    Text(
                      'User-entered schedule. DoseMate records your '
                      'log and does not provide clinical guidance.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.labelSm.copyWith(
                        color: AppColors.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoseButtons extends GetView<HomeViewModel> {
  const _DoseButtons({required this.occurrence});

  final DoseOccurrence occurrence;

  @override
  Widget build(BuildContext context) => Obx(() {
    final busy = controller.isBusy(occurrence);
    void record(DoseAction a) => controller.recordDose(occurrence, a);
    return Column(
      children: [
        const SizedBox(height: 4),
        DmWideButton(
          label: '✓ Mark as Taken',
          icon: Icons.done_all,
          height: 56,
          color: AppColors.primaryContainer,
          onTap: busy ? null : () => record(DoseAction.taken),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DmPill(
                onTap: busy ? null : () => record(DoseAction.snoozed),
                color: AppColors.surfaceContainerHigh,
                minHeight: 48,
                expand: true,
                children: [
                  const Icon(
                    Icons.schedule,
                    size: 18,
                    color: AppColors.secondary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Snooze (15m)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelMd.copyWith(
                        color: AppColors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DmPill(
                onTap: busy ? null : () => record(DoseAction.skipped),
                color: AppColors.surfaceContainerLow,
                minHeight: 48,
                expand: true,
                children: [
                  const Icon(
                    Icons.close,
                    size: 18,
                    color: AppColors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Skip Dose',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelMd.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  });
}

class _DoseFeedback extends GetView<HomeViewModel> {
  const _DoseFeedback({required this.feedback});

  final DoseFeedback feedback;

  @override
  Widget build(BuildContext context) {
    final name = feedback.occurrence.medicine.name;
    final time = CareDates.clock(feedback.occurrence.minutes);
    final (icon, message) = switch (feedback.action) {
      DoseAction.taken => (
        Icons.check_circle_outline,
        'Marked $name taken at ${CareDates.clockOf(feedback.at)}',
      ),
      DoseAction.snoozed => (
        Icons.snooze,
        '$name ($time) snoozed for 15 minutes.',
      ),
      DoseAction.skipped => (
        Icons.cancel_outlined,
        '$name ($time) marked as skipped.',
      ),
    };
    final style = AppTextStyles.labelMd.copyWith(color: AppColors.primary);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: style)),
          TextButton(
            onPressed: controller.undoDose,
            child: Text(
              'Undo',
              style: AppTextStyles.labelSm.copyWith(
                color: AppColors.onSurfaceVariant,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.name,
    required this.tag,
    required this.tagColor,
    required this.tagTextColor,
    required this.detail,
    required this.time,
  });

  /// One of today's doses, tagged with what happened to it.
  factory _TimelineItem.of(DoseOccurrence o, HomeViewModel vm) {
    final m = o.medicine;
    final log = vm.care.logFor(o);
    final overdue = o.at.isBefore(
      vm.care.now().subtract(const Duration(minutes: 15)),
    );
    final (icon, iconColor, iconBg, tag, tagColor, tagText) = switch (log) {
      DoseLog(status: DoseStatus.taken) => (
        Icons.check_circle_outline,
        AppColors.primary,
        AppColors.surfaceContainerLow,
        '${CareDates.clockOf(log.shownTime)} ✓',
        AppColors.surfaceContainer,
        AppColors.primary,
      ),
      DoseLog(status: DoseStatus.skipped) => (
        Icons.cancel_outlined,
        AppColors.onSurfaceVariant,
        AppColors.surfaceContainerLow,
        'Skipped',
        AppColors.surfaceContainerHigh,
        AppColors.onSurfaceVariant,
      ),
      _ => (
        Icons.medication_outlined,
        AppColors.secondary,
        AppColors.secondaryFixed,
        overdue
            ? 'Overdue'
            : o.minutes >= 17 * 60
            ? 'Due tonight'
            : 'Due today',
        AppColors.secondaryFixed,
        AppColors.onSecondaryFixed,
      ),
    };
    return _TimelineItem(
      icon: icon,
      iconColor: iconColor,
      iconBackground: iconBg,
      name: m.name,
      tag: tag,
      tagColor: tagColor,
      tagTextColor: tagText,
      detail: [
        if (m.dosage.isNotEmpty) m.dosage,
        CareDates.partOfDay(o.minutes),
      ].join(' • '),
      time: CareDates.clock(o.minutes),
    );
  }

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String name;
  final String tag;
  final Color tagColor;
  final Color tagTextColor;
  final String detail;
  final String time;

  @override
  Widget build(BuildContext context) {
    return DmCard(
      color: AppColors.surfaceContainerLowest,
      shadow: kShadowSm,
      padding: const EdgeInsets.all(kSpaceMd),
      child: Row(
        children: [
          DmIconCircle(
            size: 44,
            icon: icon,
            iconSize: 22,
            color: iconBackground,
            iconColor: iconColor,
          ),
          const SizedBox(width: kSpaceMd),
          Expanded(
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
                        style: AppTextStyles.titleMd.copyWith(
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 88),
                      child: DmTag(
                        label: tag,
                        color: tagColor,
                        textColor: tagTextColor,
                        fontWeight: FontWeight.w600,
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
                Text(
                  detail,
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Scheduled',
                style: AppTextStyles.labelSm
                    .copyWith(color: AppColors.onSurfaceVariant)
                    .weight(FontWeight.w500),
              ),
              Text(
                time,
                style: AppTextStyles.labelMd
                    .copyWith(color: AppColors.onSurface)
                    .weight(FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AppointmentSection extends GetView<HomeViewModel> {
  const _AppointmentSection({required this.visit});

  final Visit visit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Next Appointment',
                style: AppTextStyles.titleLg
                    .copyWith(color: AppColors.onSurface)
                    .weight(FontWeight.w700),
              ),
            ),
            Text(
              controller.visitRelative(visit),
              style: AppTextStyles.labelSm
                  .copyWith(color: AppColors.onSurfaceVariant)
                  .weight(FontWeight.w500),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DmCard(
          color: AppColors.surfaceContainerLowest,
          shadow: kShadowSm,
          padding: const EdgeInsets.all(kSpaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainer,
                      borderRadius: BorderRadius.circular(kRadiusLg),
                    ),
                    child: const Icon(
                      Icons.calendar_today_outlined,
                      size: 26,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DmTag(
                          label: controller.visitWhen(visit),
                          color: AppColors.surfaceContainer,
                          textColor: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          radius: 16,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          visit.title,
                          style: AppTextStyles.titleMd
                              .copyWith(color: AppColors.onSurface)
                              .weight(FontWeight.w700),
                        ),
                        if (visit.who.isNotEmpty)
                          Text(
                            visit.who,
                            style: AppTextStyles.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _ContactButton(
                      icon: Icons.directions_outlined,
                      label: 'Directions',
                      onTap: () => controller.directions(visit),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ContactButton(
                      icon: Icons.call_outlined,
                      label: 'Call Office',
                      onTap: () => controller.call(visit),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Appointment notes',
                    child: DmPill(
                      onTap: () => controller.editVisit(visit),
                      color: AppColors.surfaceContainerLow,
                      minHeight: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: const [
                        Icon(
                          Icons.edit_note,
                          size: 20,
                          color: AppColors.onSurface,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ContactButton extends StatelessWidget {
  const _ContactButton({
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
      onTap: onTap,
      color: AppColors.surfaceContainerLow,
      minHeight: 44,
      expand: true,
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelMd.copyWith(color: AppColors.onSurface),
          ),
        ),
      ],
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DmWideButton(
            label: 'Add Medicine',
            icon: Icons.add,
            height: 56,
            onTap: () => Get.toNamed(AppRoutes.addMedicine),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DmPill(
            onTap: () => Get.toNamed(AppRoutes.addVisit),
            color: AppColors.surfaceContainer,
            minHeight: 56,
            expand: true,
            shadow: kShadowSm,
            children: [
              const Icon(
                Icons.event_outlined,
                size: 22,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Add Visit',
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
    );
  }
}
