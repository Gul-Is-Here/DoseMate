import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/care_dates.dart';
import '../../../core/utils/dose_state.dart';
import '../../../data/models/visit.dart';
import '../../../data/services/calendar_service.dart';
import '../../../widgets/app_shell.dart';
import '../../../widgets/skeleton.dart';
import '../view_model/calendar_view_model.dart';

const _cardRadius = 16.0;
const _weekLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

class CalendarView extends GetView<CalendarViewModel> {
  const CalendarView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          const AppTopBar(),
          Expanded(
            child: Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.only(bottom: 104),
                  children: const [
                    _MonthHeader(),
                    _FilterChips(),
                    _DayBanner(),
                    _Timeline(),
                  ],
                ),
                Positioned(
                  left: kMargin,
                  right: kMargin,
                  bottom: 16,
                  child: Center(child: _AddButton(onTap: controller.addVisit)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Month bar and week scrubber.

class _MonthHeader extends GetView<CalendarViewModel> {
  const _MonthHeader();

  @override
  Widget build(BuildContext context) {
    final calendar = controller.calendar;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kMargin, 16, kMargin, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Obx(
                        () => Text(
                          controller.monthTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.headlineLgMobile.copyWith(
                            color: AppColors.onSurface,
                            letterSpacing: -0.6,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _RoundIcon(
                      icon: Icons.expand_more,
                      size: 32,
                      tooltip: 'Select month',
                      onTap: () => _pickMonth(context),
                    ),
                  ],
                ),
              ),
              _RoundIcon(
                icon: Icons.chevron_left,
                size: 36,
                tooltip: 'Previous week',
                onTap: () => calendar.shiftWeek(-1),
              ),
              const SizedBox(width: 4),
              Obx(
                () => Semantics(
                  button: true,
                  selected: controller.isTodaySelected,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: calendar.goToday,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryFixed.withValues(
                          alpha: controller.isTodaySelected ? 0.4 : 0.2,
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Today',
                        style: AppTextStyles.labelSm.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _RoundIcon(
                icon: Icons.chevron_right,
                size: 36,
                tooltip: 'Next week',
                onTap: () => calendar.shiftWeek(1),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _WeekStrip(),
        ],
      ),
    );
  }

  Future<void> _pickMonth(BuildContext context) => Get.bottomSheet<void>(
    const _MonthPicker(),
    backgroundColor: AppColors.surfaceContainerLowest,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
  );
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
    required this.icon,
    required this.size,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final double size;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: size / 2 + 4,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: 20, color: AppColors.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _WeekStrip extends GetView<CalendarViewModel> {
  const _WeekStrip();

  @override
  Widget build(BuildContext context) {
    final calendar = controller.calendar;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Obx(() {
        calendar.version.value; // markers follow the data
        final selected = calendar.selectedDay.value;
        final days = calendar.week;
        return Row(
          children: [
            for (final (i, day) in days.indexed) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: _DayCell(
                  day: day,
                  letter: _weekLetters[i],
                  selected: day == selected,
                  agenda: calendar.agendaFor(day),
                  onTap: () => calendar.select(day),
                ),
              ),
            ],
          ],
        );
      }),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.letter,
    required this.selected,
    required this.agenda,
    required this.onTap,
  });

  final DateTime day;
  final String letter;
  final bool selected;
  final DayAgenda agenda;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.onSelected : AppColors.onSurfaceVariant;
    Widget dot(Color c) => Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );
    final markers = selected
        ? [
            if (agenda.visits > 0) dot(AppColors.attention),
            if (agenda.doses > 0) dot(AppColors.primary),
          ]
        : [
            if (agenda.events.isNotEmpty)
              dot(AppColors.outlineVariant.withValues(alpha: 0.6)),
          ];
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${CareDates.long(day)}, ${agenda.visits} appointments, '
          '${agenda.doses} doses',
      excludeSemantics: true,
      child: AnimatedScale(
        scale: selected ? 1.03 : 1,
        duration: const Duration(milliseconds: 150),
        child: Material(
          // Selected: lavender with an indigo outline, as other selections.
          color: selected ? AppColors.selected : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(48),
            side: selected
                ? BorderSide(color: AppColors.primary, width: 1.5)
                : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(48),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: selected ? 1 : 0.75,
                      child: Text(
                        letter,
                        style: AppTextStyles.labelSm
                            .copyWith(color: fg)
                            .weight(
                              selected ? FontWeight.w700 : FontWeight.w600,
                            ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${day.day}',
                      style: AppTextStyles.titleMd
                          .copyWith(color: fg)
                          .weight(FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 6,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final (i, m) in markers.indexed) ...[
                            if (i > 0) const SizedBox(width: 2),
                            m,
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthPicker extends StatefulWidget {
  const _MonthPicker();

  @override
  State<_MonthPicker> createState() => _MonthPickerState();
}

class _MonthPickerState extends State<_MonthPicker> {
  final calendar = Get.find<CalendarService>();
  late int year = calendar.selectedDay.value.year;

  @override
  Widget build(BuildContext context) {
    final selected = calendar.selectedDay.value;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(kMargin, 12, kMargin, kMargin),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 6,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _RoundIcon(
                  icon: Icons.chevron_left,
                  size: 40,
                  tooltip: 'Previous year',
                  onTap: () => setState(() => year--),
                ),
                Expanded(
                  child: Text(
                    '$year',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.titleLg.copyWith(
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
                _RoundIcon(
                  icon: Icons.chevron_right,
                  size: 40,
                  tooltip: 'Next year',
                  onTap: () => setState(() => year++),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.4,
              children: [
                for (var m = 1; m <= 12; m++)
                  _MonthButton(
                    label: CareDates.months[m - 1],
                    selected: selected.year == year && selected.month == m,
                    onTap: () {
                      calendar.selectMonth(year, m);
                      Navigator.of(context).pop();
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthButton extends StatelessWidget {
  const _MonthButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DmPill(
      color: selected ? AppColors.primary : AppColors.surfaceContainerLow,
      onTap: onTap,
      children: [
        Text(
          label,
          style: AppTextStyles.labelMd.copyWith(
            color: selected ? AppColors.onPrimary : AppColors.onSurface,
          ),
        ),
      ],
    );
  }
}

// Filter chips and the day summary.

class _FilterChips extends GetView<CalendarViewModel> {
  const _FilterChips();

  @override
  Widget build(BuildContext context) {
    final calendar = controller.calendar;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: kMargin, vertical: 12),
      child: Obx(() {
        calendar.version.value;
        final agenda = calendar.selectedAgenda;
        final filter = calendar.filter.value;
        return Row(
          children: [
            _Chip(
              label: 'All Events',
              icon: Icons.event_note_outlined,
              active: filter == CalendarFilter.all,
              onTap: () => calendar.filter.value = CalendarFilter.all,
            ),
            const SizedBox(width: 8),
            _Chip(
              label: 'Appointments (${agenda.visits})',
              dot: AppColors.secondaryContainer,
              active: filter == CalendarFilter.appointments,
              onTap: () => calendar.filter.value = CalendarFilter.appointments,
            ),
            const SizedBox(width: 8),
            _Chip(
              label: 'Doses (${agenda.doses})',
              dot: AppColors.primary,
              active: filter == CalendarFilter.doses,
              onTap: () => calendar.filter.value = CalendarFilter.doses,
            ),
          ],
        );
      }),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
    this.dot,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final fg = active ? AppColors.onPrimary : AppColors.onSurface;
    return Semantics(
      selected: active,
      child: DmPill(
        color: active ? AppColors.primary : AppColors.surfaceContainerLow,
        shadow: active ? kShadowSm : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: onTap,
        children: [
          if (icon != null)
            Icon(icon, size: 18, color: fg)
          else if (dot != null)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.labelMd
                .copyWith(color: fg)
                .weight(active ? FontWeight.w600 : FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _DayBanner extends GetView<CalendarViewModel> {
  const _DayBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(kMargin, 4, kMargin, 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Obx(() {
          controller.calendar.version.value;
          final status = controller.calendar.status;
          final loading = status == RangeStatus.loading;
          final progress = status == RangeStatus.ready
              ? controller.progress
              : null;
          return Row(
            children: [
              DmIconCircle(
                size: 36,
                icon: Icons.favorite,
                iconSize: 20,
                color: AppColors.primaryFixed,
                iconColor: AppColors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${controller.bannerTitle} Ritual',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelMd.copyWith(
                        color: AppColors.onSurface,
                      ),
                    ),
                    if (loading)
                      Skeleton(
                        label: 'Loading this day',
                        child: Bone.text(
                          AppTextStyles.bodySm,
                          widthFactor: 0.6,
                        ),
                      )
                    else
                      Text(
                        status == RangeStatus.error
                            ? 'This day couldn’t be loaded'
                            : controller.bannerSummary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (progress != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: kShadowSm,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$progress%',
                        style: AppTextStyles.labelSm.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        }),
      ),
    );
  }
}

// Timeline.

class _Timeline extends GetView<CalendarViewModel> {
  const _Timeline();

  @override
  Widget build(BuildContext context) {
    final calendar = controller.calendar;
    return Padding(
      padding: const EdgeInsets.fromLTRB(kMargin, 4, kMargin, 0),
      child: Obx(() {
        calendar.version.value;
        return switch (calendar.status) {
          RangeStatus.loading => const _TimelineSkeleton(),
          RangeStatus.error => _Message(
            icon: Icons.cloud_off,
            title: 'Couldn’t load this week',
            body: calendar.loadError ?? 'Please try again.',
            action: 'Retry',
            onTap: calendar.retry,
          ),
          RangeStatus.ready => _rows(calendar),
        };
      }),
    );
  }

  Widget _rows(CalendarService calendar) {
    final events = calendar.visibleEvents;
    if (events.isEmpty) {
      final what = switch (calendar.filter.value) {
        CalendarFilter.all => 'Nothing scheduled',
        CalendarFilter.appointments => 'No appointments',
        CalendarFilter.doses => 'No doses',
      };
      return _Message(
        icon: Icons.event_available_outlined,
        title: '$what on this day',
        body: 'Pick another day, or add an appointment.',
      );
    }
    return Column(
      children: [
        for (final (i, e) in events.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 16),
            child: _Row(
              key: ValueKey(switch (e) {
                DoseEvent d => d.occurrence.logId,
                VisitEvent v => 'visit-${v.visit.id}',
              }),
              event: e,
              last: i == events.length - 1,
            ),
          ),
      ],
    );
  }
}

/// The day's timeline rows while the week loads.
class _TimelineSkeleton extends StatelessWidget {
  const _TimelineSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      label: 'Loading this day’s schedule',
      child: Column(
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 16, bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 64,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Bone.text(AppTextStyles.labelMd, width: 48),
                          Bone.text(AppTextStyles.labelSm, width: 40),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Bone.circle(size: 16),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SkeletonCard(
                      radius: _cardRadius,
                      child: Row(
                        children: [
                          const Bone.circle(size: 44),
                          const SizedBox(width: 12),
                          Expanded(
                            child: BoneColumn(
                              children: [
                                Bone.text(
                                  AppTextStyles.titleMd,
                                  widthFactor: 0.75,
                                ),
                                Bone.text(
                                  AppTextStyles.bodySm,
                                  widthFactor: 0.5,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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

class _Row extends GetView<CalendarViewModel> {
  const _Row({super.key, required this.event, required this.last});

  final CalendarEvent event;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final (sub, subColor, subWeight) = switch (e) {
      VisitEvent(:final visit) => (
        controller.visitDay(visit),
        AppColors.secondary,
        FontWeight.w700,
      ),
      DoseEvent() => (
        CareDates.partOfDay(e.minutes),
        AppColors.onSurfaceVariant,
        FontWeight.w500,
      ),
    };
    // The connector runs down a Stack beside the card, so rows size to
    // their card without intrinsic layout.
    return Stack(
      children: [
        Positioned(
          left: 64 + 12 + 7,
          top: 20,
          bottom: 0,
          child: Container(
            width: 2,
            decoration: BoxDecoration(
              gradient: last
                  ? LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.surfaceContainerHigh,
                        AppColors.surfaceContainerHigh.withValues(alpha: 0),
                      ],
                    )
                  : null,
              color: last ? null : AppColors.surfaceContainerHigh,
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 64,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      CareDates.clock(e.minutes),
                      textAlign: TextAlign.end,
                      style: AppTextStyles.labelMd
                          .copyWith(color: AppColors.onSurface)
                          .weight(FontWeight.w700),
                    ),
                    Text(
                      sub,
                      textAlign: TextAlign.end,
                      style: AppTextStyles.labelSm
                          .copyWith(color: subColor)
                          .weight(subWeight),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            _Indicator(event: e),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: last ? 16 : 8),
                child: switch (e) {
                  VisitEvent(:final visit) => _VisitCard(visit: visit),
                  DoseEvent() => _DoseCard(event: e),
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Indicator extends GetView<CalendarViewModel> {
  const _Indicator({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    Widget circle(Color bg, Widget child) => Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        boxShadow: kShadowSm,
      ),
      child: child,
    );
    Widget dot(double size, Color c) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );
    return switch (event) {
      VisitEvent() => circle(
        AppColors.secondaryContainer,
        dot(8, AppColors.onPrimary),
      ),
      DoseEvent e => switch (controller.doseState(e)) {
        DoseState.taken => circle(
          AppColors.success,
          Icon(Icons.done, size: 12, color: AppColors.card),
        ),
        DoseState.overdue || DoseState.missed => circle(
          AppColors.errorContainer,
          dot(6, AppColors.error),
        ),
        DoseState.skipped => circle(
          AppColors.neutralContainer,
          Icon(Icons.close, size: 10, color: AppColors.neutral),
        ),
        _ => circle(AppColors.primaryFixed, dot(6, AppColors.primary)),
      },
    };
  }
}

/// White timeline card with the colored strip on its left edge.
class _StripCard extends StatelessWidget {
  const _StripCard({
    required this.strip,
    required this.child,
    required this.onTap,
    this.shadow = kShadowSm,
  });

  final Color strip;
  final Widget child;
  final VoidCallback onTap;
  final List<BoxShadow> shadow;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_cardRadius),
        boxShadow: shadow,
      ),
      child: Material(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(_cardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Padding(padding: const EdgeInsets.all(16), child: child),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 6, color: strip),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, this.bg, this.fg, {this.weight = FontWeight.w700});

  final String label;
  final Color bg;
  final Color fg;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) {
    return DmTag(
      label: label,
      color: bg,
      textColor: fg,
      fontWeight: weight,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    );
  }
}

class _DoseCard extends GetView<CalendarViewModel> {
  const _DoseCard({required this.event});

  final DoseEvent event;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final m = e.occurrence.medicine;
    final state = controller.doseState(e);
    final taken = state == DoseState.taken;
    final strip = switch (state) {
      DoseState.taken => AppColors.success,
      DoseState.overdue || DoseState.missed => AppColors.error,
      DoseState.due => AppColors.attention,
      _ => AppColors.outlineVariant,
    };
    final overdue = state == DoseState.overdue || state == DoseState.missed;
    final status = taken
        ? Icon(
            Icons.check_circle,
            size: 22,
            color: AppColors.success,
            semanticLabel: 'Taken',
          )
        : DmTag(
            label: controller.doseChip(e),
            color: overdue
                ? AppColors.errorContainer
                : AppColors.surfaceContainerLow,
            textColor: overdue ? AppColors.error : AppColors.onSurfaceVariant,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          );
    return _StripCard(
      strip: strip,
      onTap: () => controller.openDose(e),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Narrow cards (small phones, large text) stack the status under
          // the text instead of squeezing it beside the name.
          final compact = constraints.maxWidth < 180;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!compact) ...[
                    DmIconCircle(
                      size: 44,
                      icon: taken
                          ? Icons.medication_outlined
                          : Icons.medication,
                      iconSize: 24,
                      color: AppColors.surfaceContainerLow,
                      iconColor: AppColors.primary,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              m.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.titleMd.copyWith(
                                color: AppColors.onSurface,
                              ),
                            ),
                            if (m.dosage.isNotEmpty)
                              taken
                                  ? _Tag(
                                      m.dosage,
                                      AppColors.primaryFixed.withValues(
                                        alpha: 0.5,
                                      ),
                                      AppColors.onPrimaryFixedVariant,
                                    )
                                  : _Tag(
                                      m.dosage,
                                      AppColors.surfaceContainer,
                                      AppColors.onSurfaceVariant,
                                      weight: FontWeight.w600,
                                    ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          controller.doseSubtitle(e),
                          style: AppTextStyles.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                        if (compact) ...[const SizedBox(height: 6), status],
                      ],
                    ),
                  ),
                  if (!compact) ...[const SizedBox(width: 8), status],
                ],
              ),
              if (controller.canTake(e)) ...[
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: Obx(() {
                    final busy = controller.isBusy(e);
                    return DmPill(
                      color: AppColors.surfaceContainer,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      onTap: busy ? null : () => controller.take(e),
                      children: [
                        Flexible(
                          child: Text(
                            state == DoseState.due
                                ? 'Take Early'
                                : 'Mark Taken',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.labelMd
                                .copyWith(
                                  color: busy
                                      ? AppColors.outline
                                      : AppColors.primary,
                                )
                                .weight(FontWeight.w700),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _VisitCard extends GetView<CalendarViewModel> {
  const _VisitCard({required this.visit});

  final Visit visit;

  @override
  Widget build(BuildContext context) {
    final v = visit;
    final reminder = controller.reminderLine(v);
    final location = [
      v.place?.name ?? '',
      v.address,
    ].where((s) => s.isNotEmpty).toSet().join(', ');
    return _StripCard(
      strip: AppColors.secondaryContainer,
      shadow: kShadowMd,
      onTap: () => controller.openVisit(v),
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
                  color: AppColors.secondaryFixed.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  _categoryIcon(v.category),
                  size: 26,
                  color: AppColors.onSecondaryFixed,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (v.category.isNotEmpty)
                          _Tag(
                            v.category,
                            AppColors.secondaryFixed,
                            AppColors.onSecondaryFixedVariant,
                          ),
                        _Tag(
                          controller.visitRelative(v),
                          AppColors.surfaceContainer,
                          AppColors.onSurfaceVariant,
                          weight: FontWeight.w500,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      v.title,
                      style: AppTextStyles.titleLg
                          .copyWith(
                            color: AppColors.onSurface,
                            letterSpacing: -0.3,
                          )
                          .weight(FontWeight.w700),
                    ),
                    if (v.who.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        v.who,
                        style: AppTextStyles.bodySm
                            .copyWith(color: AppColors.primary)
                            .weight(FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (location.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.inverseSurface.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 16,
                    color: AppColors.inversePrimary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelSm
                          .copyWith(color: AppColors.inverseOnSurface)
                          .weight(FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (reminder != null) ...[
            const SizedBox(height: 12),
            _Bubble(
              color: AppColors.surfaceContainerLow,
              icon: Icons.notifications_active_outlined,
              iconColor: AppColors.secondary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reminder Scheduled',
                    style: AppTextStyles.labelSm.copyWith(
                      color: AppColors.onSurface,
                    ),
                  ),
                  Text(
                    reminder,
                    style: AppTextStyles.bodySm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (v.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Bubble(
              color: AppColors.surfaceContainerHigh.withValues(alpha: 0.6),
              icon: Icons.edit_note,
              iconSize: 18,
              iconColor: AppColors.onSurfaceVariant,
              child: Text(
                '“${v.notes}”',
                style: AppTextStyles.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _CardButton(
                  icon: Icons.near_me_outlined,
                  label: 'Directions',
                  primary: true,
                  onTap: () => controller.directions(v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CardButton(
                  icon: Icons.call_outlined,
                  label: 'Call Clinic',
                  onTap: () => controller.call(v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static IconData _categoryIcon(String category) => switch (category) {
    'Dentist' => Icons.medical_services_outlined,
    'Lab Test' => Icons.biotech_outlined,
    'Telehealth' => Icons.videocam_outlined,
    'Specialist' => Icons.local_hospital_outlined,
    _ => Icons.calendar_today_outlined,
  };
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.color,
    required this.icon,
    required this.iconColor,
    required this.child,
    this.iconSize = 20,
  });

  final Color color;
  final IconData icon;
  final Color iconColor;
  final double iconSize;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 2),
            child: Icon(icon, size: iconSize, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _CardButton extends StatelessWidget {
  const _CardButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? AppColors.onPrimary : AppColors.onSurface;
    return DmPill(
      color: primary ? AppColors.primary : AppColors.surfaceContainer,
      minHeight: 44,
      expand: true,
      shadow: primary ? kShadowSm : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      onTap: onTap,
      children: [
        Icon(icon, size: 18, color: fg),
        const SizedBox(width: 8),
        // Words never break mid-word: a long one scales down instead.
        Flexible(
          child: label.contains(' ')
              ? Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelMd.copyWith(color: fg),
                )
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: AppTextStyles.labelMd.copyWith(color: fg),
                  ),
                ),
        ),
      ],
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
      padding: const EdgeInsets.symmetric(vertical: 32),
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

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DmPill(
      color: AppColors.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      shadow: const [
        BoxShadow(
          color: Color(0x29132238),
          offset: Offset(0, 12),
          blurRadius: 24,
        ),
      ],
      onTap: onTap,
      children: [
        Icon(Icons.add_circle_outline, size: 24, color: AppColors.onPrimary),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            'Add Appointment',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelLg
                .copyWith(color: AppColors.onPrimary)
                .weight(FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
