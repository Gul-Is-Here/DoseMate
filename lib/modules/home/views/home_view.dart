import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/care_dates.dart';
import '../../../core/utils/dose_state.dart';
import '../../../data/models/medicine.dart';
import '../../../data/models/visit.dart';
import '../../../data/services/care_service.dart';
import '../../../widgets/app_shell.dart';
import '../../../widgets/skeleton.dart';
import '../view_model/home_view_model.dart';
import '../widgets/home_motion.dart';

/// Home's card corner radius.
const _kPanelRadius = 28.0;

/// Section headings inside Home's cards ("Today’s timeline").
TextStyle get _sectionTitle => AppTextStyles.titleMd.copyWith(
  color: AppColors.textPrimary,
  fontWeight: FontWeight.w800,
  letterSpacing: -0.2,
);

TextStyle get _caption =>
    AppTextStyles.bodySm.copyWith(color: AppColors.textSecondary, fontSize: 13);

class HomeView extends GetView<HomeViewModel> {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const AppTopBar(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(kMargin, 8, kMargin, 32),
              children: [
                const Reveal(child: _TodayCard()),
                const SizedBox(height: kSpaceMd),
                Obx(
                  () => switch (controller.status) {
                    CareStatus.error => const Reveal(
                      order: 1,
                      child: _ErrorState(),
                    ),
                    CareStatus.ready when controller.isEmpty => const Reveal(
                      order: 1,
                      child: _EmptyState(),
                    ),
                    // A new profile gets a fresh feed: nothing of the last
                    // one fades out on screen.
                    CareStatus.ready => _PopulatedFeed(
                      key: ValueKey(controller.care.profileId),
                    ),
                    _ => const _LoadingState(),
                  },
                ),
                const SizedBox(height: kSpaceMd),
                const Reveal(order: 5, child: _QuickActions()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Home's white card: hairline edge, no shadow.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.edge,
    this.edgeWidth = 1,
  });

  final Widget child;
  final EdgeInsets padding;

  /// Defaults to the divider colour.
  final Color? edge;
  final double edgeWidth;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(_kPanelRadius),
        border: Border.all(color: edge ?? AppColors.divider, width: edgeWidth),
      ),
      child: child,
    );
  }
}

/// Today at a glance: a ring that fills as doses are taken, and the counts
/// behind it.
class _TodayCard extends GetView<HomeViewModel> {
  const _TodayCard();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Obx(() {
        final status = controller.status;
        final ready = status == CareStatus.ready;
        if (!ready && status != CareStatus.error) {
          return Skeleton(
            label: 'Loading today’s doses',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Bone.circle(size: 100),
                    const SizedBox(width: 18),
                    Expanded(
                      child: BoneColumn(
                        gap: 4,
                        children: [
                          Bone.text(AppTextStyles.labelSm, widthFactor: 0.5),
                          Bone.text(AppTextStyles.titleLg, widthFactor: 0.9),
                          Bone.text(AppTextStyles.bodySm, widthFactor: 0.7),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: kSpaceMd),
                const Row(
                  children: [
                    Expanded(child: Bone(height: 58, radius: 14)),
                    SizedBox(width: 8),
                    Expanded(child: Bone(height: 58, radius: 14)),
                    SizedBox(width: 8),
                    Expanded(child: Bone(height: 58, radius: 14)),
                  ],
                ),
              ],
            ),
          );
        }
        final total = ready ? controller.todaysDoses.length : 0;
        final taken = ready ? controller.takenToday : 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Semantics(
                  label: ready ? '$taken of $total doses taken' : null,
                  child: ProgressRing(
                    // Never spins: loading shows bones, a failure an empty
                    // ring.
                    value: ready ? controller.progress : 0,
                    color: AppColors.primary,
                    track: AppColors.elevated,
                    child: ExcludeSemantics(
                      child: ready
                          ? _RingLabel(taken: taken, total: total)
                          : Icon(
                              Icons.cloud_off,
                              size: 28,
                              color: AppColors.textSecondary,
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        CareDates.long(controller.care.today.value)
                            .toUpperCase(),
                        style: AppTextStyles.labelSm.copyWith(
                          color: AppColors.onSelected,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ready
                            ? controller.progressTitle
                            : 'Today’s doses aren’t available',
                        style: AppTextStyles.titleLg.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          height: 1.25,
                        ),
                      ),
                      if (ready) ...[
                        const SizedBox(height: 4),
                        Text(
                          controller.progressSubtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _caption,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (ready && total > 0) ...[
              const SizedBox(height: kSpaceMd),
              Row(
                children: [
                  _Stat(
                    count: taken,
                    label: 'Taken',
                    color: AppColors.success,
                    background: AppColors.successContainer,
                  ),
                  const SizedBox(width: 8),
                  _Stat(
                    count: controller.remainingToday,
                    label: 'Remaining',
                    color: AppColors.attention,
                    background: AppColors.attentionContainer,
                  ),
                  const SizedBox(width: 8),
                  _Stat(
                    count: controller.skippedToday,
                    label: 'Skipped',
                    color: AppColors.neutral,
                    background: AppColors.neutralContainer,
                  ),
                ],
              ),
            ],
          ],
        );
      }),
    );
  }
}

/// "1/3 taken" in the middle of the ring.
class _RingLabel extends StatelessWidget {
  const _RingLabel({required this.taken, required this.total});

  final int taken;
  final int total;

  @override
  Widget build(BuildContext context) {
    final big = AppTextStyles.headlineLgMobile.copyWith(
      color: AppColors.textPrimary,
      fontSize: 26,
      height: 1,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Counter(
          value: taken,
          style: big,
          suffix: TextSpan(
            text: '/$total',
            style: big.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'taken',
          style: AppTextStyles.labelSm.copyWith(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// A number that pops when it changes.
class _Counter extends StatelessWidget {
  const _Counter({required this.value, required this.style, this.suffix});

  final int value;
  final TextStyle style;
  final InlineSpan? suffix;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return AnimatedSwitcher(
      duration: still ? Duration.zero : const Duration(milliseconds: 280),
      transitionBuilder: (child, t) => FadeTransition(
        opacity: t,
        child: ScaleTransition(
          scale: Tween(
            begin: 0.6,
            end: 1.0,
          ).animate(CurvedAnimation(parent: t, curve: Curves.easeOutBack)),
          child: child,
        ),
      ),
      child: Text.rich(
        key: ValueKey(value),
        TextSpan(text: '$value', children: [?suffix]),
        style: style,
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.count,
    required this.label,
    required this.color,
    required this.background,
  });

  final int count;
  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: MergeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Counter(
                value: count,
                style: AppTextStyles.titleMd.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  style: AppTextStyles.labelSm.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Today's feed while the profile's schedule loads: the next-dose card and
/// timeline rows, in their real sizes.
class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      label: 'Loading today’s schedule',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Bone(width: 150, height: 28, radius: 999),
                    Spacer(),
                    Bone(width: 64, height: 16, radius: 8),
                  ],
                ),
                const SizedBox(height: kSpaceMd),
                Row(
                  children: [
                    Expanded(
                      child: BoneColumn(
                        gap: 4,
                        children: [
                          Bone.text(
                            AppTextStyles.headlineLgMobile,
                            widthFactor: 0.7,
                          ),
                          Bone.text(AppTextStyles.bodyMd, widthFactor: 0.4),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Bone(width: 64, height: 64, radius: 20),
                  ],
                ),
                const SizedBox(height: kSpaceMd),
                const Bone(height: 52, radius: 999),
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Expanded(child: Bone(height: 44, radius: 999)),
                    SizedBox(width: 8),
                    Expanded(child: Bone(height: 44, radius: 999)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: kSpaceMd),
          _TimelineBox(
            header: BoneColumn(
              children: [
                Bone.text(AppTextStyles.titleMd, widthFactor: 0.55),
                Bone.text(AppTextStyles.bodySm, widthFactor: 0.4),
              ],
            ),
            children: [
              for (var i = 0; i < 3; i++)
                _TimelineRowSkeleton(first: i == 0, last: i == 2),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends GetView<HomeViewModel> {
  const _ErrorState();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(kSpaceLg),
      child: Column(
        children: [
          DmIconCircle(
            size: 56,
            icon: Icons.cloud_off,
            iconSize: 28,
            color: AppColors.errorContainer,
            iconColor: AppColors.error,
          ),
          const SizedBox(height: 12),
          Text(
            'Couldn’t load the schedule',
            textAlign: TextAlign.center,
            style: _sectionTitle,
          ),
          const SizedBox(height: 4),
          Obx(
            () => Text(
              controller.care.error.value ?? 'Please try again.',
              textAlign: TextAlign.center,
              style: _caption,
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
    return _Panel(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          DmIconCircle(
            size: 64,
            icon: Icons.wb_sunny_outlined,
            iconSize: 34,
            color: AppColors.selected,
            iconColor: AppColors.onSelected,
          ),
          const SizedBox(height: 20),
          Text(
            'No schedules created yet',
            textAlign: TextAlign.center,
            style: _sectionTitle.copyWith(fontSize: 20),
          ),
          const SizedBox(height: 6),
          Text(
            'Set up ${name == null ? 'the' : '$name’s'} first medication '
            'routine or doctor appointment to activate automatic daily care '
            'checklists.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          DmWideButton(
            label: 'Add First Medicine',
            icon: Icons.add,
            height: 52,
            onTap: controller.addMedicine,
          ),
          const SizedBox(height: 8),
          DmPill(
            onTap: controller.addVisit,
            color: AppColors.elevated,
            minHeight: 44,
            expand: true,
            children: [
              Flexible(
                child: Text(
                  'Schedule a Doctor Visit',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelMd.copyWith(
                    color: AppColors.textPrimary,
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
  const _PopulatedFeed({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Obx(() {
          final medicine = controller.refillDue;
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: medicine == null
                ? const SizedBox.shrink()
                : Padding(
                    key: ValueKey(medicine.id),
                    padding: const EdgeInsets.only(bottom: kSpaceMd),
                    child: Reveal(
                      order: 1,
                      child: _RefillBanner(medicine: medicine),
                    ),
                  ),
          );
        }),
        Obx(() {
          final next = controller.nextDose;
          final feedback = controller.feedback.value;
          if (next == null && feedback == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: kSpaceMd),
            child: Reveal(
              order: 2,
              child: _NextDoseCard(occurrence: next, feedback: feedback),
            ),
          );
        }),
        Obx(() {
          final doses = controller.todaysDoses;
          final nextId = controller.nextDose?.logId;
          final count = doses.length;
          return Reveal(
            order: 3,
            child: _TimelineBox(
              header: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Today’s timeline', style: _sectionTitle),
                        const SizedBox(height: 2),
                        Text(
                          '$count scheduled ${count == 1 ? 'dose' : 'doses'}',
                          style: _caption.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: controller.openHistory,
                    child: Text(
                      'See all',
                      style: AppTextStyles.labelMd.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              children: [
                if (doses.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'No doses are scheduled for today.',
                      style: AppTextStyles.bodyMd.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                for (final (i, o) in doses.indexed)
                  Reveal(
                    key: ValueKey(o.logId),
                    order: 4 + i,
                    from: const Offset(-10, 0),
                    child: _TimelineRow.of(
                      o,
                      controller,
                      next: o.logId == nextId,
                      first: i == 0,
                      last: i == doses.length - 1,
                    ),
                  ),
              ],
            ),
          );
        }),
        Obx(() {
          final visit = controller.nextVisit;
          return visit == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: kSpaceMd),
                  child: Reveal(
                    order: 4,
                    child: _AppointmentCard(visit: visit),
                  ),
                );
        }),
      ],
    );
  }
}

/// One line about a medicine that is running out.
class _RefillBanner extends GetView<HomeViewModel> {
  const _RefillBanner({required this.medicine});

  final Medicine medicine;

  @override
  Widget build(BuildContext context) {
    final fg = AppColors.attention;
    final bg = AppColors.attentionContainer;
    final left = medicine.quantity;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: fg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.inventory_2_outlined, size: 20, color: bg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  medicine.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelMd.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$left ${left == 1 ? 'dose' : 'doses'} left · '
                  '${controller.refillShort(medicine)}',
                  style: AppTextStyles.bodySm.copyWith(color: fg, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PressScale(
            child: DmPill(
              tooltip: 'Refill details and mark purchased',
              onTap: () => controller.markRefill(medicine),
              color: fg,
              minHeight: 40,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                Text(
                  'Refill',
                  style: AppTextStyles.labelMd.copyWith(
                    color: bg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Dismiss alert',
            onPressed: () => controller.dismissRefill(medicine),
            icon: Icon(Icons.close, size: 18, color: fg),
          ),
        ],
      ),
    );
  }
}

/// The next dose to act on, with the last action and its Undo on top.
class _NextDoseCard extends GetView<HomeViewModel> {
  const _NextDoseCard({required this.occurrence, required this.feedback});

  final DoseOccurrence? occurrence;
  final DoseFeedback? feedback;

  @override
  Widget build(BuildContext context) {
    final o = occurrence;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final swap = still ? Duration.zero : const Duration(milliseconds: 320);
    return _Panel(
      edge: o == null ? null : AppColors.selected,
      edgeWidth: o == null ? 1 : 1.5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSize(
            duration: swap,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: feedback == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: EdgeInsets.only(bottom: o == null ? 0 : 16),
                    child: _DoseFeedback(feedback: feedback!),
                  ),
          ),
          AnimatedSwitcher(
            duration: swap,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, t) => FadeTransition(
              opacity: t,
              child: SizeTransition(
                sizeFactor: t,
                alignment: Alignment.topCenter,
                child: child,
              ),
            ),
            child: o == null
                ? (feedback == null
                      ? const _AllLogged(key: ValueKey('done'))
                      : const SizedBox(
                          key: ValueKey('none'),
                          width: double.infinity,
                        ))
                : _NextDoseBody(key: ValueKey(o.logId), occurrence: o),
          ),
          const SizedBox(height: 14),
          Text(
            'User-entered schedule. DoseMate records your log and does not '
            'provide clinical guidance.',
            textAlign: TextAlign.center,
            style: AppTextStyles.labelSm.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _AllLogged extends StatelessWidget {
  const _AllLogged({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _PopIcon(
          icon: Icons.check_rounded,
          color: AppColors.success,
          background: AppColors.successContainer,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'All of today’s doses are logged.',
            style: _sectionTitle.copyWith(fontSize: 16),
          ),
        ),
      ],
    );
  }
}

class _NextDoseBody extends GetView<HomeViewModel> {
  const _NextDoseBody({super.key, required this.occurrence});

  final DoseOccurrence occurrence;

  @override
  Widget build(BuildContext context) {
    final o = occurrence;
    final m = o.medicine;
    final countdown = controller.countdown(o);
    final overdue = DoseStates.isOverdue(o, controller.care.now());
    final dueColor = overdue ? AppColors.error : AppColors.textSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
                  decoration: BoxDecoration(
                    color: AppColors.selected,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PulseDot(color: AppColors.primary),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          controller.nextDoseLabel(o),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.labelSm.copyWith(
                            color: AppColors.onSelected,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              overdue ? Icons.error_outline : Icons.schedule,
              size: 15,
              color: dueColor,
            ),
            const SizedBox(width: 4),
            Text(
              countdown,
              style: AppTextStyles.labelSm.copyWith(
                color: dueColor,
                fontWeight: FontWeight.w600,
              ),
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
                  Semantics(
                    button: true,
                    label: 'Open ${m.name} details',
                    excludeSemantics: true,
                    child: GestureDetector(
                      onTap: () => controller.openDetails(o),
                      child: Text(
                        m.name,
                        style: AppTextStyles.headlineLgMobile.copyWith(
                          color: AppColors.textPrimary,
                          fontSize: 28,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                        ),
                      ),
                    ),
                  ),
                  if (m.dosage.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      m.dosage,
                      style: AppTextStyles.bodyMd.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 15,
                      ),
                    ),
                  ],
                  if (m.notes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.restaurant,
                            size: 15,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('User note: ${m.notes}', style: _caption),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.selected,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.medication_outlined,
                size: 30,
                color: AppColors.onSelected,
              ),
            ),
          ],
        ),
        const SizedBox(height: kSpaceMd),
        _DoseButtons(occurrence: o),
      ],
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PressScale(
          child: FilledButton.icon(
            onPressed: busy ? null : () => record(DoseAction.taken),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              textStyle: AppTextStyles.labelLg.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            icon: busy
                ? SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textSecondary,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 22),
            label: const Text('Mark as Taken'),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _SoftButton(
                icon: Icons.snooze,
                label: 'Snooze 15m',
                onTap: busy ? null : () => record(DoseAction.snoozed),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SoftButton(
                icon: Icons.close,
                label: 'Skip Dose',
                onTap: busy ? null : () => record(DoseAction.skipped),
              ),
            ),
          ],
        ),
      ],
    );
  });
}

/// A grey pill for secondary actions.
class _SoftButton extends StatelessWidget {
  const _SoftButton({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: DmPill(
        onTap: onTap,
        color: AppColors.elevated,
        minHeight: 44,
        expand: true,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: [
          Icon(icon, size: 17, color: AppColors.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelMd.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An icon in a circle that pops in when it first shows.
class _PopIcon extends StatelessWidget {
  const _PopIcon({
    required this.icon,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: still ? 1 : 0.4, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutBack,
      builder: (_, s, child) => Transform.scale(scale: s, child: child),
      child: DmIconCircle(
        size: 44,
        icon: icon,
        iconSize: 24,
        color: background,
        iconColor: color,
      ),
    );
  }
}

class _DoseFeedback extends GetView<HomeViewModel> {
  const _DoseFeedback({required this.feedback});

  final DoseFeedback feedback;

  @override
  Widget build(BuildContext context) {
    final name = feedback.occurrence.medicine.name;
    final time = CareDates.clock(feedback.occurrence.minutes);
    final (icon, color, background, message) = switch (feedback.action) {
      DoseAction.taken => (
        Icons.check_rounded,
        AppColors.success,
        AppColors.successContainer,
        'Marked $name taken at ${CareDates.clockOf(feedback.at)}',
      ),
      DoseAction.snoozed => (
        Icons.snooze,
        AppColors.onSelected,
        AppColors.selected,
        '$name ($time) snoozed for 15 minutes.',
      ),
      DoseAction.skipped => (
        Icons.close_rounded,
        AppColors.neutral,
        AppColors.neutralContainer,
        '$name ($time) marked as skipped.',
      ),
    };
    return Row(
      key: ValueKey(feedback.at),
      children: [
        _PopIcon(icon: icon, color: color, background: background),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            message,
            style: AppTextStyles.bodySm.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        PressScale(
          child: DmPill(
            onTap: controller.undoDose,
            color: AppColors.selected,
            minHeight: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              Text(
                'Undo',
                style: AppTextStyles.labelMd.copyWith(
                  color: AppColors.onSelected,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Today's timeline in one card. Its rows scroll inside the card, so a long
/// day doesn't push the appointment and quick actions far down the page.
class _TimelineBox extends StatefulWidget {
  const _TimelineBox({required this.header, required this.children});

  final Widget header;
  final List<Widget> children;

  /// About three and a half rows, so a cut-off row hints at more below.
  static const maxListHeight = 296.0;

  @override
  State<_TimelineBox> createState() => _TimelineBoxState();
}

class _TimelineBoxState extends State<_TimelineBox> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.children;
    return _Panel(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: widget.header,
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: BoxConstraints(
              // Grows with the text size so rows stay legible.
              maxHeight: MediaQuery.textScalerOf(context)
                  .scale(_TimelineBox.maxListHeight),
            ),
            child: Scrollbar(
              controller: _scroll,
              child: ListView.builder(
                controller: _scroll,
                primary: false,
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: rows.length,
                itemBuilder: (_, i) => rows[i],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The time column and the line with a dot for one timeline row.
class _Rail extends StatelessWidget {
  const _Rail({
    required this.time,
    required this.dot,
    required this.first,
    required this.last,
  });

  final Widget time;
  final Widget dot;
  final bool first;
  final bool last;

  /// Where the dot's centre sits from the top of the row.
  static const _dotCentre = 26.0;

  @override
  Widget build(BuildContext context) {
    final timeWidth = MediaQuery.textScalerOf(context).scale(58);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: timeWidth,
          child: Padding(
            padding: const EdgeInsets.only(top: 18, right: 6),
            child: Align(alignment: Alignment.topRight, child: time),
          ),
        ),
        SizedBox(
          width: 24,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              if (!(first && last))
                Positioned(
                  top: first ? _dotCentre : 0,
                  bottom: last ? null : 0,
                  height: last ? _dotCentre : null,
                  child: Container(width: 2, color: AppColors.divider),
                ),
              Padding(
                padding: const EdgeInsets.only(top: _dotCentre - 10),
                child: dot,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.time,
    required this.name,
    required this.detail,
    required this.tag,
    required this.color,
    required this.background,
    required this.next,
    required this.first,
    required this.last,
    this.onTap,
  });

  /// One of today's doses, tagged with what happened to it.
  factory _TimelineRow.of(
    DoseOccurrence o,
    HomeViewModel vm, {
    required bool next,
    required bool first,
    required bool last,
  }) {
    final m = o.medicine;
    final log = vm.care.logFor(o);
    final overdue = DoseStates.isOverdue(o, vm.care.now());
    // Status colours always come with a label.
    final (tag, color, background) = switch (log) {
      DoseLog(status: DoseStatus.taken) => (
        'Taken ${CareDates.clockOf(log.shownTime)}',
        AppColors.success,
        AppColors.successContainer,
      ),
      DoseLog(status: DoseStatus.skipped) => (
        'Skipped',
        AppColors.neutral,
        AppColors.neutralContainer,
      ),
      _ when overdue => ('Overdue', AppColors.error, AppColors.errorContainer),
      _ => (
        o.minutes >= 17 * 60 ? 'Due tonight' : 'Due today',
        AppColors.attention,
        AppColors.attentionContainer,
      ),
    };
    return _TimelineRow(
      time: CareDates.clock(o.minutes),
      name: m.name,
      detail: [
        if (m.dosage.isNotEmpty) m.dosage,
        CareDates.partOfDay(o.minutes),
      ].join(' · '),
      tag: tag,
      color: color,
      background: background,
      next: next,
      first: first,
      last: last,
      onTap: () => vm.openDetails(o),
    );
  }

  final String time;
  final String name;
  final String detail;
  final String tag;

  /// The status colour pair, for the dot and the tag.
  final Color color;
  final Color background;

  /// The next dose to take: its tile is highlighted.
  final bool next;
  final bool first;
  final bool last;

  /// Opens Medication Details for this dose.
  final VoidCallback? onTap;

  static const _fade = Duration(milliseconds: 400);

  @override
  Widget build(BuildContext context) {
    final tile = AnimatedContainer(
      duration: _fade,
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: next ? AppColors.selected : AppColors.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelLg.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: _caption.copyWith(fontSize: 12, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 112),
            child: AnimatedContainer(
              duration: _fade,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                tag,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTextStyles.labelSm.copyWith(
                  color: color,
                  fontSize: 11,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: onTap != null,
      label: onTap == null ? null : 'Open $name details',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Rail(
                first: first,
                last: last,
                time: Text(
                  time,
                  style: AppTextStyles.labelSm.copyWith(
                    color: AppColors.textSecondary,
                    letterSpacing: 0,
                  ),
                ),
                dot: AnimatedContainer(
                  duration: _fade,
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: next ? AppColors.primary : color,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.card, width: 3),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 5, 0, 5),
                  child: tile,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineRowSkeleton extends StatelessWidget {
  const _TimelineRowSkeleton({required this.first, required this.last});

  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Rail(
            first: first,
            last: last,
            time: Bone.text(AppTextStyles.labelSm, width: 44),
            dot: const Bone.circle(size: 20),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 5, 0, 5),
              child: SkeletonCard(
                color: AppColors.background,
                radius: 16,
                shadow: null,
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: BoneColumn(
                        children: [
                          Bone.text(AppTextStyles.labelLg, widthFactor: 0.7),
                          Bone.text(_caption, widthFactor: 0.5),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Bone(width: 64, height: 24, radius: 999),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentCard extends GetView<HomeViewModel> {
  const _AppointmentCard({required this.visit});

  final Visit visit;

  @override
  Widget build(BuildContext context) {
    final on = AppColors.onSelected;
    return _Panel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Next Appointment', style: _sectionTitle)),
              DmTag(
                label: controller.visitRelative(visit),
                color: AppColors.selected,
                textColor: on,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Semantics(
            button: true,
            label: 'Open ${visit.title} details',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => controller.openVisit(visit),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.selected,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: ExcludeSemantics(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            CareDates.months[visit.startsAt.month - 1]
                                .toUpperCase(),
                            style: AppTextStyles.labelSm.copyWith(
                              color: on,
                              fontSize: 11,
                              letterSpacing: 0.8,
                            ),
                          ),
                          Text(
                            '${visit.startsAt.day}',
                            style: AppTextStyles.headlineLgMobile.copyWith(
                              color: on,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          visit.title,
                          style: AppTextStyles.labelLg.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(controller.visitWhen(visit), style: _caption),
                        if (visit.who.isNotEmpty)
                          Text(visit.who, style: _caption),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _SoftButton(
                  icon: Icons.directions_outlined,
                  label: 'Directions',
                  onTap: () => controller.directions(visit),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SoftButton(
                  icon: Icons.call_outlined,
                  label: 'Call',
                  onTap: () => controller.call(visit),
                ),
              ),
              const SizedBox(width: 8),
              PressScale(
                child: DmPill(
                  tooltip: 'Appointment notes',
                  onTap: () => controller.editVisit(visit),
                  color: AppColors.elevated,
                  minHeight: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    Icon(Icons.notes, size: 20, color: AppColors.primary),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends GetView<HomeViewModel> {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionTile(
            icon: Icons.add_rounded,
            label: 'Add Medicine',
            color: AppColors.primary,
            foreground: AppColors.onPrimary,
            onTap: controller.addMedicine,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionTile(
            icon: Icons.event_outlined,
            label: 'Add Visit',
            color: AppColors.card,
            foreground: AppColors.textPrimary,
            iconColor: AppColors.primary,
            edge: AppColors.divider,
            onTap: controller.addVisit,
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.foreground,
    required this.onTap,
    this.iconColor,
    this.edge,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color foreground;
  final Color? iconColor;
  final Color? edge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: Material(
        color: color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: edge == null ? BorderSide.none : BorderSide(color: edge!),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 22, color: iconColor ?? foreground),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelLg.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
