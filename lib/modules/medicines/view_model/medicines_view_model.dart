import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/utils/care_dates.dart';
import '../../../data/models/medicine.dart';
import '../../../data/models/user_profile.dart';
import '../../../data/repositories/care_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/care_service.dart';
import '../../../data/services/profile_service.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../widgets/profile_switcher_sheet.dart';

class MedicinesViewModel extends GetxController {
  final _auth = Get.find<AuthService>();
  final care = Get.find<CareService>();

  bool get isSignedIn => _auth.isSignedIn;

  ProfileService get profiles => _auth.profiles;

  UserProfile? get activeProfile => profiles.activeProfile;

  String? get firstName {
    final name = activeProfile?.fullName.trim().split(' ').first;
    return name == null || name.isEmpty ? null : name;
  }

  void openProfiles() => ProfileSwitcherSheet.show();

  @override
  void onInit() {
    super.onInit();
    ever(care.profiles.activeProfileId, (_) => expanded.clear());
  }

  /// 0: Active, 1: Archived / Paused (and drafts).
  final segment = 0.obs;

  void selectSegment(int value) => segment.value = value;

  List<Medicine> get active => care.medicines.where((m) => m.isActive).toList();

  List<Medicine> get inactive =>
      care.medicines.where((m) => !m.isActive).toList();

  List<Medicine> get shown => segment.value == 0 ? active : inactive;

  /// Cards showing their details drawer.
  final expanded = <String>{}.obs;

  void toggle(Medicine m) =>
      expanded.contains(m.id) ? expanded.remove(m.id) : expanded.add(m.id);

  /// Short tag for the card header.
  String tagFor(Medicine m) {
    if (m.isPending) return 'Syncing';
    return switch (m.status) {
      MedicineStatus.draft => 'Draft',
      MedicineStatus.paused => 'Paused',
      MedicineStatus.archived => 'Archived',
      MedicineStatus.active => switch (m.frequency) {
        Frequency.onceDaily => 'Daily',
        Frequency.multipleDaily => '${m.doseMinutes.length}× daily',
        Frequency.specificDays => 'Weekly',
        Frequency.asNeeded => 'As needed',
      },
    };
  }

  /// "500mg - 1 capsule" or the frequency when no dosage was entered.
  String subtitleFor(Medicine m) =>
      m.dosage.isEmpty ? m.frequency.label : m.dosage;

  /// The next unlogged dose today, or null.
  DoseOccurrence? nextToday(Medicine m) => m
      .occurrencesOn(care.today.value)
      .firstWhereOrNull((o) => care.logFor(o) == null);

  /// "Today at 8:00 PM (evening)", "Tomorrow at 8:00 AM (morning)", etc.
  String scheduleLine(Medicine m) {
    if (!m.isActive) return 'Not scheduled while ${tagFor(m).toLowerCase()}';
    if (!m.frequency.isScheduled) return 'Take only as needed';
    final today = care.today.value;
    final next = nextToday(m);
    if (next != null) {
      return 'Today at ${CareDates.clock(next.minutes)} '
          '(${CareDates.partOfDay(next.minutes).toLowerCase()})';
    }
    for (var i = 1; i <= 14; i++) {
      final day = CareDates.addDays(today, i);
      final doses = m.occurrencesOn(day);
      if (doses.isNotEmpty) {
        final first = doses.first.minutes;
        return '${CareDates.relative(day, today)} at ${CareDates.clock(first)} '
            '(${CareDates.partOfDay(first).toLowerCase()})';
      }
    }
    return m.endDate.isBefore(today)
        ? 'Course ended ${CareDates.short(m.endDate)}'
        : 'No doses in the next two weeks';
  }

  /// "Once daily at 9:00 AM".
  String routineLine(Medicine m) {
    if (!m.frequency.isScheduled) return m.frequency.label;
    final times = m.doseMinutes.map(CareDates.clock).join(', ');
    final days = m.frequency == Frequency.specificDays
        ? ' on ${m.days.map((d) => CareDates.weekdays[d - 1].substring(0, 3)).join(', ')}'
        : '';
    return '${m.frequency.label} at $times$days';
  }

  String courseLabel(Medicine m) => '${m.courseDays}-day course';

  String endsLabel(Medicine m) =>
      '${m.endDate.isBefore(care.today.value) ? 'Ended' : 'Ends'} '
      '${CareDates.long(m.endDate)}';

  /// "Estimated run-out: Friday evening" style summary.
  String runOutTitle(Medicine m) {
    final days = m.daysOfSupply;
    if (days == null) return '${m.quantity} doses on hand';
    final day = CareDates.addDays(care.today.value, days);
    return 'Estimated run-out: ${CareDates.relative(day, care.today.value) == 'Today' ? 'today' : CareDates.long(day)}';
  }

  String runOutDetail(Medicine m) => m.dosesPerDay == 0
      ? 'Taken as needed, so run-out can’t be estimated.'
      : 'Calculated at ${m.dosesPerDay} '
            '${m.dosesPerDay == 1 ? 'dose' : 'doses'} per day '
            'with ${m.quantity} on hand.';

  String takenLabel(DoseLog log) =>
      '${log.status == DoseStatus.taken ? 'Taken' : 'Skipped'} at '
      '${CareDates.clockOf(log.shownTime)}';

  String logDay(DoseLog log) => CareDates.relative(log.day, care.today.value);

  // Actions.

  bool canLog(Medicine m) =>
      m.isActive && (!m.frequency.isScheduled || nextToday(m) != null);

  /// Logs the next due dose today (or an as needed dose now).
  Future<void> logDose(Medicine m) async {
    try {
      final WriteResult? result;
      if (!m.frequency.isScheduled) {
        result = await care.logAsNeeded(m);
      } else {
        final next = nextToday(m);
        if (next == null) {
          Get.snackbar(
            'All caught up',
            'Every dose of ${m.name} today is logged.',
          );
          return;
        }
        result = await care.logDose(next, DoseStatus.taken);
      }
      if (result == null) return;
      Get.snackbar(
        'Dose logged',
        result == WriteResult.pending
            ? "Saved on this device. It will sync when you're back online."
            : '${m.name} marked as taken.',
      );
    } on CareFailure catch (e) {
      Get.snackbar("Couldn't log dose", e.message);
    }
  }

  void edit(Medicine m) => Get.toNamed(AppRoutes.addMedicine, arguments: m);

  void add() => Get.toNamed(AppRoutes.addMedicine);

  Future<void> togglePause(Medicine m) => _setStatus(
    m,
    m.status == MedicineStatus.paused
        ? MedicineStatus.active
        : MedicineStatus.paused,
  );

  Future<void> archive(Medicine m) async {
    if (m.status == MedicineStatus.archived) {
      return _setStatus(m, MedicineStatus.active);
    }
    final confirmed = await confirmAction(
      title: 'Archive ${m.name}?',
      message:
          'It stops appearing in today’s schedule. You can restore it from '
          'Archived / Paused.',
      confirmLabel: 'Archive',
    );
    if (confirmed) await _setStatus(m, MedicineStatus.archived);
  }

  Future<void> _setStatus(Medicine m, MedicineStatus status) async {
    try {
      await care.setMedicineStatus(m, status);
    } on CareFailure catch (e) {
      Get.snackbar("Couldn't update ${m.name}", e.message);
    }
  }

  Future<void> markRefill(Medicine m) async {
    final count = await askRefillCount(m.name);
    if (count == null) return;
    try {
      await care.addSupply(m, count);
    } on CareFailure catch (e) {
      Get.snackbar("Couldn't update supply", e.message);
    }
  }

  Future<void> retry() => care.retry();
}
