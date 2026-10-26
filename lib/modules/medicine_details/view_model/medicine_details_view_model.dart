import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/utils/care_dates.dart';
import '../../../data/models/medicine.dart';
import '../../../data/models/user_profile.dart';
import '../../../data/repositories/care_repository.dart';
import '../../../data/services/care_service.dart';
import '../../../widgets/app_snackbar.dart';

/// Which medicine to show, for which profile, and optionally which scheduled
/// dose (otherwise today's next one).
class MedicineDetailsArgs {
  const MedicineDetailsArgs({
    required this.medicineId,
    required this.profileId,
    this.day,
    this.minutes,
  });

  MedicineDetailsArgs.forDose(DoseOccurrence o, {required this.profileId})
    : medicineId = o.medicine.id,
      day = o.day,
      minutes = o.minutes;

  final String medicineId;
  final String profileId;
  final DateTime? day;
  final int? minutes;
}

enum DetailsState { loading, ready, unavailable, error }

/// Medication Details reads the shared, already-open listeners of
/// [CareService] for the active profile, so it adds no Firestore reads of
/// its own and shows edits, deletes and sync state as they happen.
class MedicineDetailsViewModel extends GetxController {
  MedicineDetailsViewModel({MedicineDetailsArgs? args})
    : args = args ?? Get.arguments as MedicineDetailsArgs;

  final MedicineDetailsArgs args;
  final care = Get.find<CareService>();

  static const noteLimit = 200;

  final note = TextEditingController();
  final hasNote = false.obs;
  final noteError = RxnString();

  Worker? _profileWorker;
  bool _closing = false;

  @override
  void onInit() {
    super.onInit();
    note.addListener(() {
      hasNote.value = note.text.isNotEmpty;
      if (note.text.length <= noteLimit) noteError.value = null;
    });
    // Another profile's data must never show here: leave instead.
    _profileWorker = ever(care.profiles.activeProfileId, (String id) {
      if (id != args.profileId) _leave('Switched profile');
    });
  }

  @override
  void onClose() {
    _profileWorker?.dispose();
    note.dispose();
    super.onClose();
  }

  void _leave(String reason) {
    if (_closing) return;
    _closing = true;
    Get.back(closeOverlays: true);
    showSnack(reason, 'Medication Details closed to keep profiles apart.');
  }

  void close() => Get.back(closeOverlays: true);

  // State.

  DetailsState get state {
    final status = care.status.value;
    if (care.profileId != null && care.profileId != args.profileId) {
      return DetailsState.unavailable;
    }
    return switch (status) {
      CareStatus.error => DetailsState.error,
      CareStatus.ready =>
        medicine == null ? DetailsState.unavailable : DetailsState.ready,
      _ => DetailsState.loading,
    };
  }

  String? get loadError => care.error.value;

  Future<void> retry() => care.retry();

  /// Reads the live list first, so anything showing it rebuilds on
  /// changes, including the medicine disappearing.
  Medicine? get medicine {
    final list = care.medicines;
    if (care.profileId != args.profileId) return null;
    return list.firstWhereOrNull((m) => m.id == args.medicineId);
  }

  UserProfile? get profile => care.profiles.byId(args.profileId);

  DateTime get today => care.today.value;

  /// The dose this screen acts on: the one it was opened for, else today's
  /// next unlogged one, else today's last (to show how it went).
  DoseOccurrence? get occurrence {
    final m = medicine;
    if (m == null) return null;
    if (args.day != null && args.minutes != null) {
      return DoseOccurrence(m, CareDates.dateOnly(args.day!), args.minutes!);
    }
    final doses = m.occurrencesOn(today);
    if (doses.isEmpty) return null;
    return doses.firstWhereOrNull(
          (o) => care.logFor(o) == null && !care.isSnoozed(o),
        ) ??
        doses.firstWhereOrNull((o) => care.logFor(o) == null) ??
        doses.last;
  }

  DoseLog? get log {
    final o = occurrence;
    return o == null ? null : care.logFor(o);
  }

  bool get isBusy {
    final o = occurrence;
    return o != null && care.busy.contains(o.logId);
  }

  /// "DUE RIGHT NOW", "TAKEN AT 8:04 PM", etc.
  String get statusLabel {
    final m = medicine;
    final o = occurrence;
    if (m == null) return '';
    if (!m.isActive) return 'Not scheduled (${m.status.name})';
    if (!m.frequency.isScheduled) return 'Take as needed';
    if (o == null) return 'No dose due today';
    final l = care.logFor(o);
    if (l?.status == DoseStatus.taken) {
      return 'Taken at ${CareDates.clockOf(l!.shownTime)}';
    }
    if (l?.status == DoseStatus.skipped) return 'Skipped';
    if (care.isSnoozed(o)) {
      return 'Snoozed until ${CareDates.clockOf(care.snoozed[o.logId]!)}';
    }
    final minutesAway = o.at.difference(care.now()).inMinutes;
    if (minutesAway <= 30) return 'Due right now';
    return CareDates.dateOnly(o.day) == today
        ? 'Upcoming today'
        : 'Upcoming ${CareDates.short(o.day)}';
  }

  /// Orange dot for due/snoozed doses, green once handled.
  bool get isAttention {
    final o = occurrence;
    return o != null && care.logFor(o) == null;
  }

  /// "8:00 PM".
  String? get reminderTime {
    final o = occurrence;
    return o == null ? null : CareDates.clock(o.minutes);
  }

  /// "(Evening Dose)".
  String? get reminderPart {
    final o = occurrence;
    return o == null ? null : '(${CareDates.partOfDay(o.minutes)} Dose)';
  }

  /// Saved on the server, or still waiting to sync from this device.
  bool get isSyncing =>
      (medicine?.isPending ?? false) || (log?.isPending ?? false);

  String get quantityLabel {
    final q = medicine?.quantity ?? 0;
    return '$q ${q == 1 ? 'dose' : 'doses'} left';
  }

  /// "Day 6 of 10", "Starts Oct 30" or "Course ended".
  String? get courseLabel {
    final m = medicine;
    if (m == null) return null;
    if (today.isBefore(m.startDate)) {
      return 'Starts ${CareDates.short(m.startDate)}';
    }
    if (today.isAfter(m.endDate)) return 'Course ended';
    return 'Day ${CareDates.daysBetween(m.startDate, today) + 1} '
        'of ${m.courseDays}';
  }

  // Actions.

  bool get canLog =>
      (medicine?.isActive ?? false) && occurrence != null && log == null;

  String? _validNote() {
    final text = note.text.trim();
    if (text.length > noteLimit) {
      noteError.value = 'Use $noteLimit characters or fewer.';
      return null;
    }
    return text;
  }

  Future<void> markTaken() => _log(DoseStatus.taken);

  Future<void> skip() => _log(DoseStatus.skipped);

  Future<void> _log(DoseStatus status, {DoseOccurrence? dose}) async {
    final o = dose ?? occurrence;
    if (o == null || state != DetailsState.ready) return;
    final text = _validNote();
    if (text == null) return;
    try {
      final result = await care.logDose(o, status, note: text);
      if (result == null) return; // already in flight or already recorded
      note.clear(); // kept when the save fails
      care.snoozed.remove(o.logId);
      final taken = status == DoseStatus.taken;
      showSnack(
        taken ? 'Marked as Taken' : 'Dose Skipped',
        result == WriteResult.pending
            ? "Saved on this device. It will sync when you're back online."
            : '${o.medicine.name} • ${CareDates.clock(o.minutes)}'
                  '${text.isEmpty ? '' : ' • “$text”'}',
      );
    } on CareFailure catch (e) {
      showSnack("Couldn't log dose", e.message);
    }
  }

  void snooze() {
    final o = occurrence;
    if (o == null || !canLog) return;
    care.snooze(o);
    showSnack('Reminder Snoozed', 'We’ll remind you again in 15 minutes.');
  }

  Future<void> undo() async {
    final l = log;
    if (l == null) return;
    try {
      await care.undoDose(l);
    } on CareFailure catch (e) {
      showSnack("Couldn't undo", e.message);
    }
  }

  /// Unlogged doses from today and yesterday that are already due, for
  /// "Log custom time".
  List<DoseOccurrence> get pastUnlogged {
    final m = medicine;
    if (m == null) return const [];
    final now = care.now();
    return [
      for (final day in [CareDates.addDays(today, -1), today])
        ...m
            .occurrencesOn(day)
            .where((o) => care.logFor(o) == null && !o.at.isAfter(now)),
    ].reversed.toList();
  }

  Future<void> logPast(DoseOccurrence o) async {
    Get.back(); // the sheet
    await _log(DoseStatus.taken, dose: o);
  }

  void editSchedule() {
    final m = medicine;
    if (m == null) return;
    if (Get.isBottomSheetOpen ?? false) Get.back();
    Get.toNamed(AppRoutes.addMedicine, arguments: m);
  }

  String doseLabel(DoseOccurrence o) =>
      '${CareDates.relative(o.day, today)} • ${CareDates.clock(o.minutes)}';
}
