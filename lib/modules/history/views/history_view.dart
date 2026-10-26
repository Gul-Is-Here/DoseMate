import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/care_dates.dart';
import '../../../data/models/medicine.dart';
import '../../../data/services/care_service.dart';
import '../../../data/services/history_service.dart';
import '../../../widgets/app_shell.dart';
import '../../../widgets/skeleton.dart';
import '../view_model/history_view_model.dart';

const _radius = 32.0;

/// "label-sm uppercase tracking-wider".
TextStyle _overline(Color color) =>
    AppTextStyles.labelSm.copyWith(color: color, letterSpacing: 1.2);

class HistoryView extends StatefulWidget {
  const HistoryView({super.key});

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  final controller = Get.find<HistoryViewModel>();
  late final ScrollController _scroll;

  HistoryService get history => controller.history;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController(initialScrollOffset: history.scrollOffset);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    history.scrollOffset = n.metrics.pixels;
    if (n.metrics.extentAfter < 600) history.loadMore();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          const AppTopBar(),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: CustomScrollView(
                controller: _scroll,
                slivers: const [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(kMargin, 8, kMargin, 0),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate.fixed([
                        _TitleRow(),
                        SizedBox(height: kSpaceMd),
                        _RangeTabs(),
                        SizedBox(height: kSpaceMd),
                        _SummaryCard(),
                        SizedBox(height: kSpaceMd + 4),
                        _FilterRow(),
                        SizedBox(height: kSpaceMd + 4),
                      ]),
                    ),
                  ),
                  _LogList(),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(kMargin, 0, kMargin, 40),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate.fixed([
                        _PageFooter(),
                        SizedBox(height: 8),
                        _ShareCard(),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Header.

class _TitleRow extends GetView<HistoryViewModel> {
  const _TitleRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'HEALTH JOURNAL',
                style: _overline(AppColors.onSurfaceVariant),
              ),
              Text(
                'Log History & Reports',
                style: AppTextStyles.headlineLgMobile.copyWith(
                  color: AppColors.onSurface,
                  letterSpacing: -0.6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(999),
              boxShadow: kShadowSm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DmDot(size: 8, color: AppColors.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Obx(
                    () => Text(
                      controller.profileName,
                      style: AppTextStyles.labelSm
                          .copyWith(color: AppColors.onSurface)
                          .weight(FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RangeTabs extends GetView<HistoryViewModel> {
  const _RangeTabs();

  static const _labels = {
    HistoryRange.daily: 'Daily',
    HistoryRange.weekly: 'Weekly Summary',
    HistoryRange.monthly: 'Monthly',
  };

  @override
  Widget build(BuildContext context) {
    final range = controller.history.range;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Obx(
        () => Row(
          children: [
            for (final MapEntry(key: r, value: label) in _labels.entries)
              Expanded(
                child: Semantics(
                  selected: range.value == r,
                  button: true,
                  child: Material(
                    color: range.value == r
                        ? AppColors.surfaceContainerLowest
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    elevation: range.value == r ? 1 : 0,
                    shadowColor: const Color(0x14132238),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => range.value = r,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.labelMd
                              .copyWith(
                                color: range.value == r
                                    ? AppColors.primary
                                    : AppColors.onSurfaceVariant,
                              )
                              .weight(
                                range.value == r
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Summary card.

class _SummaryCard extends GetView<HistoryViewModel> {
  const _SummaryCard();

  @override
  Widget build(BuildContext context) {
    return DmCard(
      color: AppColors.surfaceContainerLowest,
      radius: _radius,
      shadow: kShadowSm,
      padding: const EdgeInsets.all(kSpaceLg),
      child: Obx(() {
        final s = controller.history.summary;
        final recorded = s.recorded;
        // The totals come from the profile's logs: no numbers until then.
        final care = controller.history.care.status.value;
        final loading = care == CareStatus.loading || care == CareStatus.idle;
        final card = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ACTIVITY RECORD',
                        style: _overline(AppColors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 2),
                      if (loading)
                        Bone.text(AppTextStyles.titleLg, widthFactor: 0.7)
                      else
                        Text(
                          controller.summaryTitle,
                          style: AppTextStyles.titleLg
                              .copyWith(color: AppColors.onSurface)
                              .weight(FontWeight.w700),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                DmIconCircle(
                  size: 40,
                  icon: Icons.event_available_outlined,
                  iconSize: 22,
                  color: AppColors.primaryFixed.withValues(alpha: 0.4),
                  iconColor: AppColors.primary,
                ),
              ],
            ),
            const SizedBox(height: kSpaceMd),
            if (loading)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final w in const [170.0, 100.0, 110.0])
                    Bone(
                      width: w,
                      height: MediaQuery.textScalerOf(context).scale(18) + 12,
                      radius: 999,
                    ),
                ],
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetricPill(
                    label:
                        '${s.taken} Marked Taken (${controller.takenPercent}%)',
                    bg: AppColors.successContainer,
                    fg: AppColors.success,
                    dot: AppColors.success,
                  ),
                  _MetricPill(
                    label: '${s.skipped} Skipped',
                    bg: AppColors.neutralContainer,
                    fg: AppColors.neutral,
                    dot: AppColors.neutral,
                  ),
                  _MetricPill(
                    label: '${s.unmarked} Unmarked',
                    bg: AppColors.surfaceContainer,
                    fg: AppColors.onSurfaceVariant,
                    dot: AppColors.outline,
                    weight: FontWeight.w500,
                  ),
                ],
              ),
            const SizedBox(height: kSpaceMd + 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 10,
                child: ColoredBox(
                  color: AppColors.surfaceContainer,
                  child: recorded == 0
                      ? const SizedBox.expand()
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (s.taken > 0)
                              Expanded(
                                flex: s.taken,
                                child: ColoredBox(color: AppColors.success),
                              ),
                            if (s.skipped > 0)
                              Expanded(
                                flex: s.skipped,
                                child: ColoredBox(color: AppColors.outline),
                              ),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  controller.rangeLabel,
                  style: AppTextStyles.labelSm.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Goal: Consistent tracking',
                    textAlign: TextAlign.end,
                    style: AppTextStyles.labelSm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: kSpaceMd),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Records reflect entries logged by user or caregiver.',
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
        return loading
            ? Skeleton(label: 'Loading activity summary', child: card)
            : card;
      }),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.label,
    required this.bg,
    required this.fg,
    required this.dot,
    this.weight = FontWeight.w600,
  });

  final String label;
  final Color bg;
  final Color fg;
  final Color dot;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DmDot(size: 8, color: dot),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: AppTextStyles.labelMd.copyWith(color: fg).weight(weight),
            ),
          ),
        ],
      ),
    );
  }
}

// Filters.

class _FilterRow extends GetView<HistoryViewModel> {
  const _FilterRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Obx(
            () => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FilterButton(
                  leading: Icon(
                    Icons.filter_list,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  label: controller.medicineLabel,
                  onTap: () => _pickMedicine(context),
                ),
                _FilterButton(
                  label: controller.statusLabel,
                  onTap: () => _pickStatus(context),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Obx(
          () => Tooltip(
            message: controller.history.newestFirst.value
                ? 'Sort timeline: newest first'
                : 'Sort timeline: oldest first',
            child: Material(
              color: AppColors.surfaceContainerLowest,
              shape: const CircleBorder(),
              elevation: 1,
              shadowColor: const Color(0x14132238),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: controller.toggleSort,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: RotatedBox(
                    quarterTurns: controller.history.newestFirst.value ? 0 : 2,
                    child: Icon(
                      Icons.sort,
                      size: 20,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _pickMedicine(BuildContext context) {
    final history = controller.history;
    _choices<String?>(
      context,
      title: 'Show medicine',
      selected: history.medicineId.value,
      options: [
        (null, 'All Medicines'),
        for (final m in controller.medicineChoices) (m.id, m.name),
      ],
      onPick: (id) => history.medicineId.value = id,
    );
  }

  void _pickStatus(BuildContext context) {
    final history = controller.history;
    _choices<DoseStatus?>(
      context,
      title: 'Show status',
      selected: history.statusFilter.value,
      options: const [
        (null, 'All'),
        (DoseStatus.taken, 'Taken'),
        (DoseStatus.skipped, 'Skipped'),
      ],
      onPick: (s) => history.statusFilter.value = s,
    );
  }

  void _choices<T>(
    BuildContext context, {
    required String title,
    required T selected,
    required List<(T, String)> options,
    required void Function(T) onPick,
  }) {
    Get.bottomSheet<void>(
      SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(kMargin, 16, kMargin, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: AppTextStyles.titleMd.copyWith(
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              for (final (value, label) in options)
                Builder(
                  builder: (context) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(label),
                    trailing: value == selected
                        ? Icon(Icons.check, color: AppColors.primary)
                        : null,
                    onTap: () {
                      Navigator.of(context).pop();
                      onPick(value);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
      backgroundColor: AppColors.surfaceContainerLowest,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.label, required this.onTap, this.leading});

  final String label;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return DmPill(
      color: AppColors.surfaceContainerLowest,
      shadow: kShadowSm,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      onTap: onTap,
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 6)],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelMd.copyWith(color: AppColors.onSurface),
          ),
        ),
        const SizedBox(width: 6),
        Icon(Icons.expand_more, size: 18, color: AppColors.onSurfaceVariant),
      ],
    );
  }
}

// The log list, grouped by local day.

sealed class _Item {
  const _Item();
}

class _DayItem extends _Item {
  const _DayItem(this.day);
  final DateTime day;
}

class _LogItem extends _Item {
  const _LogItem(this.log);
  final DoseLog log;
}

class _LogList extends GetView<HistoryViewModel> {
  const _LogList();

  @override
  Widget build(BuildContext context) {
    final history = controller.history;
    return Obx(() {
      final status = history.status.value;
      // The schedule itself failed: History has nothing to wait for.
      final careFailed =
          status != HistoryStatus.ready &&
          history.care.status.value == CareStatus.error;
      if (careFailed) {
        return SliverToBoxAdapter(
          child: _Message(
            icon: Icons.cloud_off,
            title: 'Couldn’t load your history',
            body: history.care.error.value ?? 'Please try again.',
            action: 'Retry',
            onTap: history.retry,
          ),
        );
      }
      if (status == HistoryStatus.error) {
        return SliverToBoxAdapter(
          child: _Message(
            icon: Icons.cloud_off,
            title: 'Couldn’t load your history',
            body: history.error.value ?? 'Please try again.',
            action: 'Retry',
            onTap: history.retry,
          ),
        );
      }
      if (status != HistoryStatus.ready) {
        return const SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: kMargin),
          sliver: SliverToBoxAdapter(child: _LogsSkeleton(dayHeader: true)),
        );
      }
      final logs = history.entries;
      if (logs.isEmpty) {
        final filtered =
            history.medicineId.value != null ||
            history.statusFilter.value != null;
        return SliverToBoxAdapter(
          child: _Message(
            icon: Icons.history,
            title: filtered ? 'No matching records' : 'No history yet',
            body: filtered
                ? 'Try another medicine or status, or a longer period.'
                : 'Doses you mark as taken or skipped will appear here.',
          ),
        );
      }
      final items = <_Item>[];
      DateTime? day;
      for (final l in logs) {
        if (l.day != day) items.add(_DayItem(day = l.day));
        items.add(_LogItem(l));
      }
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: kMargin),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => switch (items[i]) {
              _DayItem(:final day) => Padding(
                key: ValueKey('day-$day'),
                padding: EdgeInsets.only(top: i == 0 ? 0 : 8, bottom: 8),
                child: _DayHeader(day: day),
              ),
              _LogItem(:final log) => Padding(
                key: ValueKey(log.id),
                padding: const EdgeInsets.only(bottom: 8),
                child: _LogCard(log: log),
              ),
            },
            childCount: items.length,
            findChildIndexCallback: (key) {
              final id = (key as ValueKey<String>).value;
              final i = items.indexWhere(
                (it) => switch (it) {
                  _DayItem(:final day) => 'day-$day' == id,
                  _LogItem(:final log) => log.id == id,
                },
              );
              return i < 0 ? null : i;
            },
          ),
        ),
      );
    });
  }
}

class _DayHeader extends GetView<HistoryViewModel> {
  const _DayHeader({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final suffix = controller.daySuffix(day);
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            DmDot(
              size: 6,
              color: suffix == 'Today' ? AppColors.primary : AppColors.outline,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                controller.dayTitle(day),
                style: AppTextStyles.labelLg
                    .copyWith(color: AppColors.onSurface)
                    .weight(FontWeight.w700),
              ),
            ),
            if (suffix != null) ...[
              const SizedBox(width: 8),
              Text(
                suffix,
                style: AppTextStyles.labelSm
                    .copyWith(color: AppColors.onSurfaceVariant)
                    .weight(FontWeight.w400),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LogCard extends GetView<HistoryViewModel> {
  const _LogCard({required this.log});

  final DoseLog log;

  @override
  Widget build(BuildContext context) {
    final taken = log.status == DoseStatus.taken;
    final accent = taken ? AppColors.success : AppColors.neutral;
    final dosage = controller.dosageOf(log);
    final note = log.note;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: kShadowSm,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: ColoredBox(
          color: AppColors.surfaceContainerLowest,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(kSpaceMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        // Narrow cards put the schedule chip under the
                        // status instead of squeezing the name.
                        final compact = constraints.maxWidth < 300;
                        final sched = DmTag(
                          label: 'Sched ${CareDates.clock(log.minutes)}',
                          color: AppColors.surfaceContainer,
                          textColor: AppColors.onSurfaceVariant,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                        );
                        return Row(
                          children: [
                            DmIconCircle(
                              size: 48,
                              icon: Icons.medication_outlined,
                              iconSize: 24,
                              color: taken
                                  ? AppColors.successContainer
                                  : AppColors.neutralContainer,
                              iconColor: accent,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    controller.nameOf(log),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.titleMd
                                        .copyWith(color: AppColors.onSurface)
                                        .weight(FontWeight.w700),
                                  ),
                                  if (dosage.isNotEmpty)
                                    Text(
                                      dosage,
                                      style: AppTextStyles.bodySm.copyWith(
                                        color: AppColors.onSurfaceVariant,
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        taken
                                            ? Icons.check_circle_outline
                                            : Icons.do_not_disturb_on_outlined,
                                        size: 16,
                                        color: accent,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          controller.statusLine(log),
                                          style: AppTextStyles.labelSm
                                              .copyWith(color: accent)
                                              .weight(FontWeight.w600),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (compact) ...[
                                    const SizedBox(height: 6),
                                    sched,
                                  ],
                                ],
                              ),
                            ),
                            if (!compact) ...[const SizedBox(width: 8), sched],
                          ],
                        );
                      },
                    ),
                    if (note != null && note.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(
                                Icons.sticky_note_2_outlined,
                                size: 16,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Note: “$note”',
                                style: AppTextStyles.bodySm.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 6,
                  color: taken ? AppColors.success : AppColors.neutral,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [_LogCard]s while records load: the whole list at first (under a day
/// header), or a couple of rows below the loaded ones for an older page.
class _LogsSkeleton extends StatelessWidget {
  const _LogsSkeleton({this.count = 3, this.dayHeader = false});

  final int count;
  final bool dayHeader;

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      label: dayHeader ? 'Loading history' : 'Loading older records',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (dayHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Row(
                children: [
                  const Bone.circle(size: 6),
                  const SizedBox(width: 8),
                  Bone.text(AppTextStyles.labelLg, width: 140),
                ],
              ),
            ),
          for (var i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SkeletonCard(
                radius: _radius,
                child: Row(
                  children: [
                    const Bone.circle(size: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: BoneColumn(
                        children: [
                          Bone.text(AppTextStyles.titleMd, widthFactor: 0.65),
                          Bone.text(AppTextStyles.bodySm, widthFactor: 0.35),
                          const SizedBox(height: 4),
                          Bone.text(AppTextStyles.labelSm, widthFactor: 0.55),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Bone(width: 84, height: 26, radius: 999),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Loading, failure and end of the older pages, below the loaded logs.
class _PageFooter extends GetView<HistoryViewModel> {
  const _PageFooter();

  @override
  Widget build(BuildContext context) {
    final history = controller.history;
    return Obx(() {
      if (history.status.value != HistoryStatus.ready ||
          history.entries.isEmpty) {
        return const SizedBox(height: 8);
      }
      return switch (history.pageStatus.value) {
        // Older records load below the ones shown, which stay as they are.
        PageStatus.loading => const _LogsSkeleton(count: 2),
        PageStatus.error => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Text(
                history.pageError.value ?? 'Couldn’t load older records.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              DmPill(
                color: AppColors.surfaceContainer,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                onTap: history.loadMore,
                children: [
                  Icon(Icons.refresh, size: 18, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Load older records',
                    style: AppTextStyles.labelMd.copyWith(
                      color: AppColors.onSurface,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        PageStatus.idle => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: TextButton(
              onPressed: history.loadMore,
              child: const Text('Load older records'),
            ),
          ),
        ),
        PageStatus.end => const SizedBox(height: 8),
      };
    });
  }
}

// Share card and export confirmation.

class _ShareCard extends GetView<HistoryViewModel> {
  const _ShareCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(kSpaceLg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: kShadowSm,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.surfaceContainerLowest,
            AppColors.surfaceContainerLow,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DmIconCircle(
                size: 48,
                icon: Icons.assignment_turned_in_outlined,
                iconSize: 26,
                color: AppColors.primary,
                iconColor: AppColors.onPrimary,
                shadow: kShadowSm,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Share Summary with Doctor or Caregiver',
                      style: AppTextStyles.titleLg
                          .copyWith(color: AppColors.onSurface, height: 1.25)
                          .weight(FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Export a complete 7-day or 30-day medication log '
                      'formatted for clinical appointments or family care '
                      'updates.',
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: kSpaceMd),
          Row(
            children: [
              Expanded(
                child: _ExportButton(
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'Preview PDF',
                  onTap: () => _confirm(ExportFormat.pdf),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ExportButton(
                  icon: Icons.table_view_outlined,
                  label: 'Export CSV',
                  onTap: () => _confirm(ExportFormat.csv),
                ),
              ),
            ],
          ),
          const SizedBox(height: kSpaceMd),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: 20, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Requires your permission before generating document or '
                    'sending.',
                    style: AppTextStyles.labelSm
                        .copyWith(
                          color: AppColors.onSurfaceVariant,
                          height: 1.5,
                        )
                        .weight(FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirm(ExportFormat format) async {
    final ok = await Get.dialog<bool>(_ExportDialog(format: format));
    if (ok == true) await controller.export(format);
  }
}

class _ExportButton extends GetView<HistoryViewModel> {
  const _ExportButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => DmPill(
        color: AppColors.surfaceContainerLowest,
        minHeight: 52,
        expand: true,
        shadow: kShadowSm,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        onTap: controller.exporting.value ? null : onTap,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: AppTextStyles.labelMd
                  .copyWith(color: AppColors.onSurface)
                  .weight(FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportDialog extends GetView<HistoryViewModel> {
  const _ExportDialog({required this.format});

  final ExportFormat format;

  @override
  Widget build(BuildContext context) {
    final name = format == ExportFormat.pdf ? 'PDF' : 'CSV';
    Widget check(String text) => Row(
      children: [
        Icon(Icons.check, size: 16, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.labelSm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
    return Dialog(
      backgroundColor: AppColors.surfaceContainerLowest,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(48)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 384),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(kSpaceLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  DmIconCircle(
                    size: 40,
                    icon: Icons.verified_user_outlined,
                    iconSize: 22,
                    color: AppColors.primaryFixed.withValues(alpha: 0.4),
                    iconColor: AppColors.primary,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close dialog',
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: Icon(
                      Icons.close,
                      size: 20,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: kSpaceMd),
              Text(
                'Confirm Report Export',
                style: AppTextStyles.titleLg
                    .copyWith(color: AppColors.onSurface)
                    .weight(FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  style: AppTextStyles.bodyMd.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                  children: [
                    const TextSpan(text: 'You are preparing a '),
                    TextSpan(
                      text: name,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const TextSpan(text: ' summary for '),
                    TextSpan(
                      text: controller.profileName,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                    TextSpan(text: ' (${controller.rangeLabel}).'),
                  ],
                ),
              ),
              const SizedBox(height: kSpaceMd),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    check('Includes dosages and logged intake times'),
                    const SizedBox(height: 6),
                    check('Includes personal symptom notes'),
                  ],
                ),
              ),
              const SizedBox(height: kSpaceMd + 4),
              DmWideButton(
                label: 'Authorize & Download',
                icon: Icons.share_outlined,
                height: 54,
                color: AppColors.primaryContainer,
                onTap: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  'Cancel',
                  style: AppTextStyles.labelMd.copyWith(
                    color: AppColors.onSurfaceVariant,
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

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(kMargin, 24, kMargin, 24),
      child: Column(
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
          Text(
            body,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: kSpaceLg),
            DmWideButton(
              label: action!,
              icon: Icons.refresh,
              height: 48,
              onTap: onTap,
            ),
          ],
        ],
      ),
    );
  }
}
