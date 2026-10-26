import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/utils/care_dates.dart';
import '../../../core/utils/contact_links.dart';
import '../../../data/models/visit.dart';
import '../../../data/repositories/care_repository.dart';
import '../../../data/services/care_service.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../widgets/app_snackbar.dart';

/// Which visit to show, and for which profile.
class VisitDetailsArgs {
  const VisitDetailsArgs({required this.visitId, required this.profileId});

  final String visitId;
  final String profileId;
}

enum VisitDetailsState { loading, ready, unavailable, error }

/// Appointment Details reads the shared upcoming-visits listener of
/// [CareService] for the active profile, so it adds no Firestore reads of
/// its own and shows edits, cancellations and sync state as they happen.
class VisitDetailsViewModel extends GetxController {
  VisitDetailsViewModel({VisitDetailsArgs? args})
    : args = args ?? Get.arguments as VisitDetailsArgs;

  final VisitDetailsArgs args;
  final care = Get.find<CareService>();

  final busy = false.obs;

  Worker? _profileWorker;
  bool _closing = false;

  @override
  void onInit() {
    super.onInit();
    // Another profile's data must never show here: leave instead.
    _profileWorker = ever(care.profiles.activeProfileId, (String id) {
      if (id != args.profileId) _leave('Switched profile');
    });
  }

  @override
  void onClose() {
    _profileWorker?.dispose();
    super.onClose();
  }

  void _leave(String reason) {
    if (_closing) return;
    _closing = true;
    Get.back(closeOverlays: true);
    showSnack(reason, 'Appointment Details closed to keep profiles apart.');
  }

  void close() => Get.back(closeOverlays: true);

  // State.

  VisitDetailsState get state {
    final status = care.status.value;
    if (care.profileId != null && care.profileId != args.profileId) {
      return VisitDetailsState.unavailable;
    }
    return switch (status) {
      CareStatus.error => VisitDetailsState.error,
      CareStatus.ready =>
        visit == null ? VisitDetailsState.unavailable : VisitDetailsState.ready,
      _ => VisitDetailsState.loading,
    };
  }

  String? get loadError => care.error.value;

  Future<void> retry() => care.retry();

  /// Reads the live list first, so anything showing it rebuilds on
  /// changes, including the visit being cancelled or deleted.
  Visit? get visit {
    final list = care.visits;
    if (care.profileId != args.profileId) return null;
    return list.firstWhereOrNull((v) => v.id == args.visitId);
  }

  DateTime get today => care.today.value;

  /// "In 5 days", "Tomorrow", "Today".
  String get relativeLabel {
    final v = visit;
    if (v == null) return '';
    final minutesAway = v.startsAt.difference(care.now()).inMinutes;
    if (minutesAway < 0) return 'Started ${CareDates.clockOf(v.startsAt)}';
    if (minutesAway <= 60) return 'Starting soon';
    return CareDates.relative(CareDates.dateOnly(v.startsAt), today);
  }

  /// Orange within the next hour, green otherwise.
  bool get isSoon {
    final v = visit;
    return v != null && v.startsAt.difference(care.now()).inMinutes <= 60;
  }

  /// "Thursday, Oct 29".
  String get dateLabel => visit == null ? '' : CareDates.long(visit!.startsAt);

  /// "3:30 PM".
  String get timeLabel =>
      visit == null ? '' : CareDates.clockOf(visit!.startsAt);

  /// "(Afternoon)".
  String get partLabel {
    final v = visit;
    if (v == null) return '';
    return '(${CareDates.partOfDay(v.startsAt.hour * 60 + v.startsAt.minute)})';
  }

  bool get isSyncing => visit?.isPending ?? false;

  /// Clinic name and address for maps; the picked place's name first.
  String get locationName {
    final v = visit;
    if (v == null) return '';
    final name = v.place?.name ?? '';
    return name.isNotEmpty ? name : v.clinic;
  }

  bool get hasLocation =>
      locationName.isNotEmpty || (visit?.address.isNotEmpty ?? false);

  // Actions.

  Future<void> directions() async {
    final v = visit;
    if (v == null) return;
    await openDirections(
      [locationName, v.address].where((s) => s.isNotEmpty).join(', '),
    );
  }

  Future<void> call() async {
    final v = visit;
    if (v != null) await callNumber(v.phone);
  }

  void edit() {
    final v = visit;
    if (v != null) Get.toNamed(AppRoutes.addVisit, arguments: v);
  }

  Future<void> cancelVisit() async {
    final v = visit;
    if (v == null || busy.value) return;
    if (!await confirmAction(
      title: 'Cancel this visit?',
      message: 'It will be removed from the upcoming schedule.',
      confirmLabel: 'Cancel Visit',
    )) {
      return;
    }
    busy.value = true;
    try {
      final result = await care.cancelVisit(args.profileId, v.id);
      _closing = true;
      Get.back(closeOverlays: true);
      showSnack(
        'Visit cancelled',
        result == WriteResult.pending
            ? "Saved on this device. It will sync when you're back online."
            : v.title,
      );
    } on CareFailure catch (e) {
      showSnack("Couldn't update visit", e.message);
    } finally {
      busy.value = false;
    }
  }
}
