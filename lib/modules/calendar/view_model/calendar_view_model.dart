import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/utils/care_dates.dart';
import '../../../core/utils/contact_links.dart';
import '../../../core/utils/dose_state.dart';
import '../../../data/models/medicine.dart';
import '../../../data/models/visit.dart';
import '../../../data/repositories/care_repository.dart';
import '../../../data/services/calendar_service.dart';
import '../../../data/services/care_service.dart';
import '../../medicine_details/view_model/medicine_details_view_model.dart';
import '../../visit_details/view_model/visit_details_view_model.dart';
import '../../../widgets/app_snackbar.dart';

/// Thin screen layer over the permanent [CalendarService] (selection and
/// data) and [CareService] (dose writes and their in-flight state).
class CalendarViewModel extends GetxController {
  final calendar = Get.find<CalendarService>();
  final care = Get.find<CareService>();

  DateTime get today => care.today.value;

  bool get isTodaySelected => calendar.selectedDay.value == today;

  /// "October 2026", for the selected day's month.
  String get monthTitle {
    final d = calendar.selectedDay.value;
    return '${_monthNames[d.month - 1]} ${d.year}';
  }

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June', //
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static List<String> get monthNames => _monthNames;

  /// "Saturday, Oct 24".
  String get bannerTitle => CareDates.long(calendar.selectedDay.value);

  /// "1 appointment • 1 dose remaining".
  String get bannerSummary {
    final a = calendar.selectedAgenda;
    if (a.events.isEmpty) return 'Nothing scheduled';
    String n(int c, String one) => '$c $one${c == 1 ? '' : 's'}';
    final day = calendar.selectedDay.value;
    final doses = day.isAfter(today)
        ? n(a.doses, 'dose')
        : '${n(a.remaining, 'dose')} remaining';
    return [
      if (a.visits > 0) n(a.visits, 'appointment'),
      if (a.doses > 0) doses,
    ].join(' • ');
  }

  /// Share of the day's doses taken, or null when none are scheduled.
  int? get progress {
    final a = calendar.selectedAgenda;
    return a.doses == 0 ? null : (a.taken * 100 / a.doses).round();
  }

  DoseState doseState(DoseEvent e) =>
      DoseStates.of(e.occurrence, e.log, care.now());

  /// "Due tonight", "Overdue", "Missed", "Skipped".
  String doseChip(DoseEvent e) => switch (doseState(e)) {
    DoseState.taken => 'Taken',
    DoseState.skipped => 'Skipped',
    DoseState.overdue => 'Overdue',
    DoseState.missed => 'Missed',
    DoseState.scheduled => 'Scheduled',
    DoseState.due => switch (CareDates.partOfDay(e.minutes)) {
      'Morning' => 'Due this morning',
      'Afternoon' => 'Due this afternoon',
      _ => 'Due tonight',
    },
  };

  /// "Take with food • Day 4 of 7".
  String doseSubtitle(DoseEvent e) {
    final m = e.occurrence.medicine;
    final day = CareDates.daysBetween(m.startDate, e.occurrence.day) + 1;
    return [
      if (m.notes.isNotEmpty) m.notes,
      'Day $day of ${m.courseDays}',
    ].join(' • ');
  }

  bool isBusy(DoseEvent e) => care.busy.contains(e.occurrence.logId);

  /// "Today", "Tomorrow", "In 3 days", for the timeline's time column.
  String visitDay(Visit v) =>
      CareDates.relative(CareDates.dateOnly(v.startsAt), today);

  /// "In 2 hours", "In 25 mins", "Now", "Tomorrow".
  String visitRelative(Visit v) {
    final day = CareDates.dateOnly(v.startsAt);
    if (day != today) return CareDates.relative(day, today);
    final mins = v.startsAt.difference(care.now()).inMinutes;
    if (mins < -60) return 'Earlier today';
    if (mins <= 0) return 'Now';
    if (mins < 60) return 'In $mins min${mins == 1 ? '' : 's'}';
    final hours = (mins / 60).round();
    return 'In $hours hour${hours == 1 ? '' : 's'}';
  }

  /// "Alert 1 hour before (2:30 PM) & departure traffic alert".
  String? reminderLine(Visit v) {
    if (v.reminders.isEmpty && !v.departureAlerts) return null;
    final parts = [for (final r in v.reminders) _reminder(v, r)];
    final alerts = parts.isEmpty ? '' : 'Alert ${parts.join(', ')}';
    if (!v.departureAlerts) return alerts;
    return alerts.isEmpty
        ? 'Departure traffic alert'
        : '$alerts & departure traffic alert';
  }

  String _reminder(Visit v, String r) {
    // Same-day reminders also say when they fire: "1 hour before (2:30 PM)".
    final match = RegExp(r'^(\d+) (hour|min)').firstMatch(r);
    if (match == null) return r;
    final n = int.parse(match[1]!);
    final at = v.startsAt.subtract(
      match[2] == 'hour' ? Duration(hours: n) : Duration(minutes: n),
    );
    return '$r (${CareDates.clockOf(at)})';
  }

  // Actions.

  String? get _pid => care.profileId;

  void openDose(DoseEvent e) {
    final pid = _pid;
    if (pid == null) return;
    Get.toNamed(
      AppRoutes.medicineDetails,
      arguments: MedicineDetailsArgs.forDose(e.occurrence, profileId: pid),
    );
  }

  void openVisit(Visit v) {
    final pid = _pid;
    if (pid == null) return;
    Get.toNamed(
      AppRoutes.visitDetails,
      arguments: VisitDetailsArgs(visitId: v.id, profileId: pid),
    );
  }

  /// Only today's doses can be logged here: older days may be outside the
  /// loaded history, and future ones aren't due.
  bool canTake(DoseEvent e) =>
      e.log == null &&
      e.occurrence.day == today &&
      e.occurrence.medicine.isActive;

  Future<void> take(DoseEvent e) async {
    if (!canTake(e)) return;
    try {
      final result = await care.logDose(e.occurrence, DoseStatus.taken);
      if (result == null) return; // already in flight or recorded
      showSnack(
        'Marked as Taken',
        result == WriteResult.pending
            ? "Saved on this device. It will sync when you're back online."
            : '${e.occurrence.medicine.name} • '
                  '${CareDates.clock(e.occurrence.minutes)}',
      );
    } on CareFailure catch (err) {
      showSnack("Couldn't log dose", err.message);
    }
  }

  Future<void> directions(Visit v) => openDirections(
    [
      v.place?.name ?? v.clinic,
      v.address,
    ].where((s) => s.isNotEmpty).join(', '),
  );

  Future<void> call(Visit v) => callNumber(v.phone);

  void addVisit() => Get.toNamed(AppRoutes.addVisit);
}
