import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/utils/care_dates.dart';
import '../../../core/utils/image_validator.dart';
import '../../../data/models/medicine.dart';
import '../../../data/models/user_profile.dart';
import '../../../data/repositories/care_repository.dart';
import '../../../data/services/care_service.dart';
import '../../../data/services/profile_service.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../widgets/profile_switcher_sheet.dart';

export '../../../data/models/medicine.dart' show Frequency;

/// Add or edit one medicine. Pass a [Medicine] as the route argument to
/// edit it. The profile the medicine is saved under is fixed when the form
/// opens (or when chosen with Assign to), never taken from whichever
/// profile happens to be active at save time.
class AddMedicineViewModel extends GetxController {
  AddMedicineViewModel({Medicine? editing, ImagePicker? picker})
    : editing = editing ?? Get.arguments as Medicine?,
      _picker = picker ?? ImagePicker();

  final Medicine? editing;
  final ImagePicker _picker;
  final _care = Get.find<CareService>();
  ProfileService get _profiles => _care.profiles;

  bool get isEditing => editing != null;

  /// The profile this form saves to.
  late final profileId =
      (isEditing
              ? (_care.profileId ?? UserProfile.selfId)
              : (_profiles.activeProfile?.id ?? UserProfile.selfId))
          .obs;

  /// Fixed per form, so retrying a save can never create a second medicine.
  late final String medicineId =
      editing?.id ?? _care.newMedicineId(profileId.value);

  UserProfile? get profile => _profiles.byId(profileId.value);

  /// "Eleanor Vance (Self)" for the Assign to pill.
  String get assigneeLabel {
    final p = profile;
    if (p == null) return 'Profile';
    final role = p.isSelf ? 'Self' : p.type.label;
    return '${p.fullName} ($role)';
  }

  /// Choosing a profile here assigns this medicine to it. Editing keeps the
  /// medicine with its profile.
  Future<void> openProfiles() async {
    if (isEditing || saving.value) return;
    await ProfileSwitcherSheet.show();
    final active = _profiles.activeProfile?.id;
    if (active != null) profileId.value = active;
  }

  final name = TextEditingController();
  final dosage = TextEditingController();
  final notes = TextEditingController();

  final hasName = false.obs;
  final frequency = Frequency.onceDaily.obs;

  /// Reminder times as minutes after midnight, ascending and unique.
  final doses = <int>[8 * 60].obs;

  /// ISO weekdays for Specific days.
  final days = <int>{}.obs;
  final startDate = CareDates.dateOnly(DateTime.now()).obs;
  final courseDays = 7.obs;
  final supplyExpanded = true.obs;
  final quantity = 0.obs;
  final lowSupplyWarning = true.obs;

  /// A newly picked photo, and the saved one (kept unless replaced).
  final photo = Rxn<File>();
  final photoUrl = RxnString();

  final nameError = RxnString();
  final scheduleError = RxnString();
  final saving = false.obs;

  /// Set once a create reached Firestore (even if only on this device), so
  /// a retry updates the same record instead of creating it again.
  bool _created = false;

  DateTime get endDate =>
      CareDates.addDays(startDate.value, courseDays.value - 1);

  /// "Morning • 500mg - 1 capsule" under each reminder time.
  String doseNote(int minutes) {
    final amount = dosage.text.trim();
    return '${CareDates.partOfDay(minutes)} • '
        '${amount.isEmpty ? '1 dose' : amount}';
  }

  int get _dosesPerDay => frequency.value.isScheduled ? doses.length : 0;

  /// "Alert when 4 remain (~2 days)".
  String get lowSupplyLabel {
    final n = _dosesPerDay == 0 ? 4 : _dosesPerDay * 2;
    return 'Alert when $n ${n == 1 ? 'dose remains' : 'doses remain'} '
        '(~2 days)';
  }

  @override
  void onInit() {
    super.onInit();
    final m = editing;
    if (m != null) {
      name.text = m.name;
      dosage.text = m.dosage;
      notes.text = m.notes;
      frequency.value = m.frequency;
      doses.assignAll(m.doseMinutes);
      days.assignAll(m.days);
      startDate.value = m.startDate;
      courseDays.value = m.courseDays;
      quantity.value = m.quantity;
      lowSupplyWarning.value = m.lowSupplyWarning;
      photoUrl.value = m.photoUrl;
      _created = true;
    } else {
      days.add(startDate.value.weekday);
    }
    hasName.value = name.text.trim().isNotEmpty;
    name.addListener(() {
      hasName.value = name.text.trim().isNotEmpty;
      if (hasName.value) nameError.value = null;
    });
    // Dose notes show the dosage.
    dosage.addListener(doses.refresh);
  }

  void selectFrequency(Frequency value) {
    frequency.value = value;
    scheduleError.value = null;
  }

  void removeDose(int index) => doses.removeAt(index);

  void addDose(TimeOfDay time) {
    final minutes = time.hour * 60 + time.minute;
    if (doses.contains(minutes)) return;
    doses
      ..add(minutes)
      ..sort();
    scheduleError.value = null;
  }

  void toggleDay(int weekday) {
    days.contains(weekday) ? days.remove(weekday) : days.add(weekday);
    scheduleError.value = null;
  }

  void setStartDate(DateTime date) =>
      startDate.value = CareDates.dateOnly(date);

  void setEndDate(DateTime date) {
    final length = CareDates.daysBetween(startDate.value, date) + 1;
    if (length >= 1) courseDays.value = length;
  }

  void toggleSupply() => supplyExpanded.toggle();

  void changeQuantity(int delta) {
    final next = quantity.value + delta;
    if (next >= 0 && next <= 9999) quantity.value = next;
  }

  void toggleLowSupplyWarning() => lowSupplyWarning.toggle();

  Future<void> pickPhoto() async {
    if (saving.value) return;
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked == null) return;
    final file = File(picked.path);
    final problem = ImageValidator.validate(file);
    if (problem != null) {
      Get.snackbar("Couldn't use that photo", problem);
      return;
    }
    photo.value = file;
  }

  /// Field problems for a full save, or null. Drafts only need a name.
  String? validate({bool draft = false}) {
    nameError.value = null;
    scheduleError.value = null;
    final n = name.text.trim();
    if (n.isEmpty) {
      nameError.value = 'Enter the medicine name.';
    } else if (n.length > 100) {
      nameError.value = 'Use 100 characters or fewer.';
    }
    if (!draft) {
      final count = doses.length;
      scheduleError.value = switch (frequency.value) {
        Frequency.onceDaily when count != 1 =>
          'Once daily needs exactly one reminder time.',
        Frequency.multipleDaily when count < 2 =>
          'Add at least two reminder times.',
        Frequency.specificDays when count == 0 => 'Add a reminder time.',
        Frequency.specificDays when days.isEmpty =>
          'Choose at least one day of the week.',
        _
            when courseDays.value < 1 ||
                courseDays.value > Medicine.maxCourseDays =>
          'Choose an end date within 10 years of the start date.',
        _ => null,
      };
    }
    if (dosage.text.trim().length > 100) {
      return 'Strength & dosage must be 100 characters or fewer.';
    }
    if (notes.text.trim().length > 500) {
      return 'Notes must be 500 characters or fewer.';
    }
    return nameError.value ?? scheduleError.value;
  }

  Medicine _build({required bool draft}) => Medicine(
    id: medicineId,
    name: name.text.trim(),
    dosage: dosage.text.trim(),
    notes: notes.text.trim(),
    frequency: frequency.value,
    doseMinutes: frequency.value.isScheduled ? doses.toList() : const [],
    days: frequency.value == Frequency.specificDays
        ? (days.toList()..sort())
        : const [],
    startDate: startDate.value,
    courseDays: courseDays.value.clamp(1, Medicine.maxCourseDays),
    quantity: quantity.value,
    lowSupplyWarning: lowSupplyWarning.value,
    status: draft
        ? MedicineStatus.draft
        // Editing keeps paused/archived medicines where they are.
        : editing?.status == MedicineStatus.draft || editing == null
        ? MedicineStatus.active
        : editing!.status,
    photoUrl: photoUrl.value,
    photoPath: editing?.photoPath,
  );

  /// Validates and saves; on success returns to the previous screen. The
  /// entered data stays in the form when anything fails.
  Future<void> save({bool draft = false}) async {
    if (saving.value) return;
    final problem = validate(draft: draft);
    if (problem != null) {
      Get.snackbar('Check the medicine details', problem);
      return;
    }
    saving.value = true;
    final pid = profileId.value;
    ({String url, String path})? uploaded;
    try {
      var medicine = _build(draft: draft);
      if (photo.value case final file?) {
        uploaded = await _care.uploadMedicinePhoto(pid, medicineId, file);
        medicine = medicine.copyWith(
          photoUrl: uploaded.url,
          photoPath: uploaded.path,
        );
      }
      final result = await _care.saveMedicine(pid, medicine, isNew: !_created);
      _created = true;
      if (uploaded != null) {
        photo.value = null;
        photoUrl.value = uploaded.url;
        if (editing?.photoPath case final old?) _care.deletePhoto(old).ignore();
      }
      // Plain back would only close a snackbar that is still showing.
      Get.back(closeOverlays: true);
      Get.snackbar(
        draft
            ? 'Draft saved'
            : (isEditing ? 'Medicine updated' : 'Medicine saved'),
        result == WriteResult.pending
            ? "Saved on this device. It will sync when you're back online."
            : '${medicine.name} is saved for ${profile?.fullName ?? 'this profile'}.',
      );
    } on CareFailure catch (e) {
      if (uploaded != null) await _care.deletePhoto(uploaded.path);
      Get.snackbar("Couldn't save medicine", e.message);
    } finally {
      saving.value = false;
    }
  }

  Future<void> delete() async {
    final m = editing;
    if (m == null || saving.value) return;
    final confirmed = await confirmAction(
      title: 'Delete ${m.name}?',
      message:
          'This removes the medicine and its recent dose history for '
          '${profile?.fullName ?? 'this profile'}. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    saving.value = true;
    try {
      await _care.deleteMedicine(profileId.value, m);
      // Plain back would only close a snackbar that is still showing.
      Get.back(closeOverlays: true);
      Get.snackbar('Medicine deleted', '${m.name} was removed.');
    } on CareFailure catch (e) {
      Get.snackbar("Couldn't delete medicine", e.message);
    } finally {
      saving.value = false;
    }
  }

  @override
  void onClose() {
    name.dispose();
    dosage.dispose();
    notes.dispose();
    super.onClose();
  }
}
