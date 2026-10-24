import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/utils/care_dates.dart';
import '../../../core/utils/contact_links.dart';
import '../../../data/models/medicine.dart';
import '../../../data/models/user_profile.dart';
import '../../../data/models/visit.dart';
import '../../../data/repositories/care_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/care_service.dart';
import '../../../data/services/profile_service.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../widgets/profile_switcher_sheet.dart';

/// What happened to the last dose acted on from the next dose card.
enum DoseAction { taken, snoozed, skipped }

/// The last action, for its confirmation and Undo.
class DoseFeedback {
  const DoseFeedback(this.action, this.occurrence, this.at);

  final DoseAction action;
  final DoseOccurrence occurrence;
  final DateTime at;
}

class HomeViewModel extends GetxController {
  final _auth = Get.find<AuthService>();
  final care = Get.find<CareService>();

  bool get isSignedIn => _auth.isSignedIn;

  /// Live profiles; the active one updates on every save and switch.
  ProfileService get profiles => _auth.profiles;

  UserProfile? get activeProfile => profiles.activeProfile;

  /// First name of the active profile, or null before profiles load.
  String? get firstName {
    final name = activeProfile?.fullName.trim().split(' ').first;
    return name == null || name.isEmpty ? null : name;
  }

  /// "Eleanor (Self)" / "Ruth (Parent)" for the header switcher chip.
  String get profileChipLabel {
    final profile = activeProfile;
    if (profile == null) return 'Profile';
    final role = profile.isSelf ? 'Self' : profile.type.label;
    return '${firstName ?? profile.type.label} ($role)';
  }

  String greeting([DateTime? now]) {
    final hour = (now ?? care.now()).hour;
    final part = hour < 12
        ? 'morning'
        : hour < 17
        ? 'afternoon'
        : 'evening';
    final name = firstName;
    return name == null ? 'Good $part' : 'Good $part, $name';
  }

  @override
  void onInit() {
    super.onInit();
    // Feedback and dismissals belong to the profile they were made for.
    ever(care.profiles.activeProfileId, (_) {
      feedback.value = null;
      snoozed.clear();
      dismissedRefills.clear();
    });
  }

  // Schedule state.

  CareStatus get status => care.status.value;

  /// Nothing to show yet for this profile (only once loaded).
  bool get isEmpty =>
      status == CareStatus.ready &&
      care.visits.isEmpty &&
      !care.medicines.any(
        (m) =>
            m.status == MedicineStatus.active ||
            m.status == MedicineStatus.paused,
      );

  List<DoseOccurrence> get todaysDoses => care.todaysDoses;

  int get takenToday => todaysDoses
      .where((o) => care.logFor(o)?.status == DoseStatus.taken)
      .length;

  /// "1 of 2 doses taken today".
  String get progressTitle {
    final total = todaysDoses.length;
    if (total == 0) return 'No doses scheduled today';
    return '$takenToday of $total ${total == 1 ? 'dose' : 'doses'} taken today';
  }

  String get progressSubtitle {
    final taken = care
        .logsOn(care.today.value)
        .firstWhereOrNull((l) => l.status == DoseStatus.taken);
    if (taken == null) {
      return todaysDoses.isEmpty
          ? 'Add a medicine to start a daily routine'
          : 'No doses logged yet today';
    }
    final name = care.medicineById(taken.medicineId)?.name ?? 'A dose';
    return '$name logged at ${CareDates.clockOf(taken.shownTime)}';
  }

  double get progress {
    final total = todaysDoses.length;
    return total == 0 ? 0 : takenToday / total;
  }

  /// Local snoozes (occurrence id → until). Not saved; reminders don't
  /// exist yet.
  final snoozed = <String, DateTime>{}.obs;

  final feedback = Rxn<DoseFeedback>();

  /// The next dose that isn't logged or snoozed.
  DoseOccurrence? get nextDose {
    final now = care.now();
    return todaysDoses.firstWhereOrNull((o) {
      if (care.logFor(o) != null) return false;
      final until = snoozed[o.logId];
      return until == null || !until.isAfter(now);
    });
  }

  /// "Next Dose: 8:00 PM Tonight".
  String nextDoseLabel(DoseOccurrence o) {
    final part = o.minutes >= 17 * 60 ? 'Tonight' : 'Today';
    return 'Next Dose: ${CareDates.clock(o.minutes)} $part';
  }

  /// "In ~3 hrs", "In 20 min", "Now" or "Overdue".
  String countdown(DoseOccurrence o) {
    final diff = o.at.difference(care.now());
    if (diff.inMinutes < -15) return 'Overdue';
    if (diff.inMinutes <= 0) return 'Now';
    if (diff.inMinutes < 60) return 'In ${diff.inMinutes} min';
    return 'In ~${(diff.inMinutes / 60).round()} hrs';
  }

  bool isBusy(DoseOccurrence o) => care.busy.contains(o.logId);

  Future<void> recordDose(DoseOccurrence o, DoseAction action) async {
    if (action == DoseAction.snoozed) {
      snoozed[o.logId] = care.now().add(const Duration(minutes: 15));
      feedback.value = DoseFeedback(action, o, care.now());
      return;
    }
    try {
      final result = await care.logDose(
        o,
        action == DoseAction.taken ? DoseStatus.taken : DoseStatus.skipped,
      );
      if (result == null) return;
      feedback.value = DoseFeedback(action, o, care.now());
      if (result == WriteResult.pending) _savedOffline();
    } on CareFailure catch (e) {
      Get.snackbar("Couldn't log dose", e.message);
    }
  }

  Future<void> undoDose() async {
    final last = feedback.value;
    if (last == null) return;
    if (last.action == DoseAction.snoozed) {
      snoozed.remove(last.occurrence.logId);
      feedback.value = null;
      return;
    }
    final log = care.logFor(last.occurrence);
    try {
      if (log != null) await care.undoDose(log);
      feedback.value = null;
    } on CareFailure catch (e) {
      Get.snackbar("Couldn't undo", e.message);
    }
  }

  // Refills.

  final dismissedRefills = <String>{}.obs;

  Medicine? get refillDue =>
      care.lowSupply.firstWhereOrNull((m) => !dismissedRefills.contains(m.id));

  void dismissRefill(Medicine m) => dismissedRefills.add(m.id);

  /// "Amoxicillin supply will run out in ~2 days based on your schedule."
  String refillMessage(Medicine m) {
    final days = m.daysOfSupply;
    if (m.quantity == 0) return '${m.name} has no doses left on record.';
    if (days == null) return '${m.name} is running low.';
    return '${m.name} supply will run out in ~$days '
        '${days == 1 ? 'day' : 'days'} based on your schedule.';
  }

  Future<void> markRefill(Medicine m) async {
    final count = await askRefillCount(m.name);
    if (count == null) return;
    try {
      final result = await care.addSupply(m, count);
      dismissedRefills.remove(m.id);
      Get.snackbar(
        'Supply updated',
        result == WriteResult.pending
            ? "Saved on this device. It will sync when you're back online."
            : 'Added $count doses to ${m.name}.',
      );
    } on CareFailure catch (e) {
      Get.snackbar("Couldn't update supply", e.message);
    }
  }

  // Visits.

  Visit? get nextVisit => care.visits.firstOrNull;

  /// "Thursday • 3:30 PM".
  String visitWhen(Visit v) =>
      '${CareDates.weekdays[v.startsAt.weekday - 1]} • '
      '${CareDates.clockOf(v.startsAt)}';

  String visitRelative(Visit v) =>
      CareDates.relative(CareDates.dateOnly(v.startsAt), care.today.value);

  Future<void> directions(Visit v) => openDirections(
    [v.clinic, v.address].where((s) => s.isNotEmpty).join(', '),
  );

  Future<void> call(Visit v) => callNumber(v.phone);

  void editVisit(Visit v) => Get.toNamed(AppRoutes.addVisit, arguments: v);

  void addMedicine() => Get.toNamed(AppRoutes.addMedicine);

  void addVisit() => Get.toNamed(AppRoutes.addVisit);

  Future<void> retry() => care.retry();

  void _savedOffline() => Get.snackbar(
    'Saved on this device',
    "It will sync when you're back online.",
  );

  void openProfiles() => ProfileSwitcherSheet.show();

  /// The auth listener routes to sign in once Firebase reports the logout.
  Future<void> signOut() => _auth.signOut();

  void signIn() => Get.offAllNamed(AppRoutes.login);
}
