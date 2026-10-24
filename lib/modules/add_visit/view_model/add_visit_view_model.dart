import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/utils/care_dates.dart';
import '../../../core/utils/contact_links.dart';
import '../../../data/models/user_profile.dart';
import '../../../data/models/visit.dart';
import '../../../data/repositories/care_repository.dart';
import '../../../data/repositories/places_repository.dart';
import '../../../data/services/care_service.dart';
import '../../../widgets/confirm_dialog.dart';

enum PlaceSearch { idle, loading, results, empty, error }

/// Add or edit one visit. Pass a [Visit] as the route argument to edit it.
/// The profile is fixed when the form opens.
class AddVisitViewModel extends GetxController {
  AddVisitViewModel({Visit? editing, PlacesRepository? places})
    : editing = editing ?? Get.arguments as Visit?,
      _places = places ?? Get.find<PlacesRepository>();

  final Visit? editing;
  final PlacesRepository _places;
  final _care = Get.find<CareService>();

  bool get isEditing => editing != null;

  /// The profile this form saves to: the one shown when it was opened.
  late final String profileId = isEditing
      ? (_care.profileId ?? UserProfile.selfId)
      : (_care.profiles.activeProfile?.id ?? UserProfile.selfId);

  /// Fixed per form, so retrying a save can never create a second visit.
  late final String visitId = editing?.id ?? _care.newVisitId(profileId);

  UserProfile? get activeProfile => _care.profiles.byId(profileId);

  String? get firstName {
    final name = activeProfile?.fullName.trim().split(' ').first;
    return name == null || name.isEmpty ? null : name;
  }

  static const categories = [
    'Routine Checkup',
    'Dentist',
    'Specialist',
    'Lab Test',
    'Telehealth',
  ];
  static const reminderOptions = [
    '1 day before',
    '2 hours before',
    '1 hour before',
    '30 mins before',
  ];
  static const prepSuggestions = [
    'Fasting required',
    'Need driver home',
    'Previous X-Rays',
  ];

  final title = TextEditingController();
  final doctor = TextEditingController();
  final clinic = TextEditingController();
  final address = TextEditingController();
  final phone = TextEditingController();
  final notes = TextEditingController();

  final category = 'Routine Checkup'.obs;
  final reminders = <String>{'1 day before'}.obs;
  final departureAlerts = false.obs;
  final date = CareDates.addDays(DateTime.now(), 1).obs;
  final time = const TimeOfDay(hour: 9, minute: 0).obs;

  final titleError = RxnString();
  final whenError = RxnString();
  final phoneError = RxnString();
  final saving = false.obs;
  bool _created = false;

  // Address search.

  static const searchDelay = Duration(milliseconds: 350);

  final suggestions = <PlaceSuggestion>[].obs;
  final placeSearch = PlaceSearch.idle.obs;
  final placeError = RxnString();

  /// The place picked for the current address text; cleared as soon as the
  /// text is edited, so stale coordinates are never saved.
  final selectedPlace = Rxn<VisitPlace>();

  Timer? _debounce;
  int _request = 0;
  String? _sessionToken;
  String _lastAddress = '';
  bool _applyingPlace = false;

  DateTime get startsAt => DateTime(
    date.value.year,
    date.value.month,
    date.value.day,
    time.value.hour,
    time.value.minute,
  );

  @override
  void onInit() {
    super.onInit();
    if (editing case final v?) _prefill(v);
    _lastAddress = address.text;
    // Attached after prefilling, so an edited visit keeps its place.
    address.addListener(_onAddressChanged);
  }

  void _prefill(Visit v) {
    title.text = v.title;
    doctor.text = v.doctor;
    clinic.text = v.clinic;
    address.text = v.address;
    phone.text = v.phone;
    notes.text = v.notes;
    if (v.category.isNotEmpty) category.value = v.category;
    reminders.assignAll(v.reminders);
    departureAlerts.value = v.departureAlerts;
    date.value = CareDates.dateOnly(v.startsAt);
    time.value = TimeOfDay.fromDateTime(v.startsAt);
    selectedPlace.value = v.place;
    _created = true;
  }

  void _onAddressChanged() {
    final text = address.text;
    // The controller also notifies on cursor moves; only react to edits.
    if (text == _lastAddress) return;
    _lastAddress = text;
    if (_applyingPlace) return;
    selectedPlace.value = null;
    _debounce?.cancel();
    _request++; // Any response still on its way is now outdated.
    if (text.trim().length < 3) {
      suggestions.clear();
      placeSearch.value = PlaceSearch.idle;
      return;
    }
    _debounce = Timer(searchDelay, _search);
  }

  Future<void> _search() async {
    final query = address.text.trim();
    final request = ++_request;
    _sessionToken ??= PlacesRepository.newSessionToken();
    placeSearch.value = PlaceSearch.loading;
    placeError.value = null;
    try {
      final results = await _places.autocomplete(
        query,
        sessionToken: _sessionToken!,
      );
      if (request != _request) return;
      suggestions.assignAll(results);
      placeSearch.value = results.isEmpty
          ? PlaceSearch.empty
          : PlaceSearch.results;
    } on PlacesFailure catch (e) {
      if (request != _request) return;
      suggestions.clear();
      placeError.value = e.message;
      placeSearch.value = PlaceSearch.error;
    }
  }

  void retryPlaceSearch() {
    _debounce?.cancel();
    _search();
  }

  /// Fetches the place's details (ending the billing session) and fills the
  /// address with it.
  Future<void> selectPlace(PlaceSuggestion suggestion) async {
    _debounce?.cancel();
    final request = ++_request;
    placeSearch.value = PlaceSearch.loading;
    placeError.value = null;
    try {
      final details = await _places.details(
        suggestion.placeId,
        sessionToken: _sessionToken ?? PlacesRepository.newSessionToken(),
      );
      if (request != _request) return;
      _sessionToken = null; // The next search starts a new session.
      _applyingPlace = true;
      address.text = details.address.isEmpty
          ? suggestion.address
          : details.address;
      _applyingPlace = false;
      selectedPlace.value = VisitPlace(
        placeId: details.placeId,
        name: details.name,
        latitude: details.latitude,
        longitude: details.longitude,
      );
      suggestions.clear();
      placeSearch.value = PlaceSearch.idle;
    } on PlacesFailure catch (e) {
      if (request != _request) return;
      placeError.value = e.message;
      placeSearch.value = PlaceSearch.error;
    }
  }

  void selectCategory(String value) => category.value = value;

  void setDate(DateTime value) {
    date.value = CareDates.dateOnly(value);
    whenError.value = null;
  }

  void setTime(TimeOfDay value) {
    time.value = value;
    whenError.value = null;
  }

  void toggleReminder(String value) => reminders.contains(value)
      ? reminders.remove(value)
      : reminders.add(value);

  void toggleDepartureAlerts() => departureAlerts.toggle();

  /// Appends a suggestion to the notes unless it is already there.
  void addPrep(String text) {
    final current = notes.text.trim();
    if (current.contains(text)) return;
    notes.text = current.isEmpty ? text : '$current, $text';
  }

  Future<void> callClinic() => callNumber(phone.text);

  static final _phonePattern = RegExp(r'^[0-9+()\-.\s]{7,30}$');

  /// The first field problem, or null.
  String? validate() {
    titleError.value = whenError.value = phoneError.value = null;
    final t = title.text.trim();
    if (t.isEmpty) {
      titleError.value = 'Enter what the appointment is for.';
    } else if (t.length > 120) {
      titleError.value = 'Use 120 characters or fewer.';
    }
    // New visits must be in the future; an edited one may keep its time.
    final unchangedTime = editing?.startsAt == startsAt;
    if (!unchangedTime && !startsAt.isAfter(_care.now())) {
      whenError.value = 'Choose a date and time in the future.';
    }
    final p = phone.text.trim();
    if (p.isNotEmpty && !_phonePattern.hasMatch(p)) {
      phoneError.value = 'Enter a valid phone number.';
    }
    for (final (c, max) in [
      (doctor, 100),
      (clinic, 100),
      (address, 200),
      (notes, 1000),
    ]) {
      if (c.text.trim().length > max) {
        return 'Some details are too long. Shorten them and try again.';
      }
    }
    return titleError.value ?? whenError.value ?? phoneError.value;
  }

  Visit _build() => Visit(
    id: visitId,
    title: title.text.trim(),
    category: category.value,
    startsAt: startsAt,
    doctor: doctor.text.trim(),
    clinic: clinic.text.trim(),
    address: address.text.trim(),
    phone: phone.text.trim(),
    notes: notes.text.trim(),
    reminders: [
      for (final r in reminderOptions)
        if (reminders.contains(r)) r,
    ],
    departureAlerts: departureAlerts.value,
    place: selectedPlace.value,
  );

  /// Validates and saves, then returns; entered data stays on failure.
  Future<void> save() async {
    if (saving.value) return;
    final problem = validate();
    if (problem != null) {
      Get.snackbar('Check the visit details', problem);
      return;
    }
    saving.value = true;
    try {
      final visit = _build();
      final result = await _care.saveVisit(profileId, visit, isNew: !_created);
      _created = true;
      // Plain back would only close a snackbar that is still showing.
      Get.back(closeOverlays: true);
      Get.snackbar(
        isEditing ? 'Visit updated' : 'Visit saved',
        result == WriteResult.pending
            ? "Saved on this device. It will sync when you're back online."
            : '${visit.title} is on ${firstName ?? 'the'} schedule for '
                  '${CareDates.long(visit.startsAt)}.',
      );
    } on CareFailure catch (e) {
      Get.snackbar("Couldn't save visit", e.message);
    } finally {
      saving.value = false;
    }
  }

  Future<void> cancelVisit() => _remove(
    confirmTitle: 'Cancel this visit?',
    message: 'It will be removed from the upcoming schedule.',
    label: 'Cancel Visit',
    done: 'Visit cancelled',
    action: () => _care.cancelVisit(profileId, visitId),
  );

  Future<void> deleteVisit() => _remove(
    confirmTitle: 'Delete this visit?',
    message: 'This permanently removes the visit. This cannot be undone.',
    label: 'Delete',
    done: 'Visit deleted',
    action: () => _care.deleteVisit(profileId, visitId),
  );

  Future<void> _remove({
    required String confirmTitle,
    required String message,
    required String label,
    required String done,
    required Future<WriteResult> Function() action,
  }) async {
    if (!isEditing || saving.value) return;
    if (!await confirmAction(
      title: confirmTitle,
      message: message,
      confirmLabel: label,
    )) {
      return;
    }
    saving.value = true;
    try {
      await action();
      // Plain back would only close a snackbar that is still showing.
      Get.back(closeOverlays: true);
      Get.snackbar(done, editing!.title);
    } on CareFailure catch (e) {
      Get.snackbar("Couldn't update visit", e.message);
    } finally {
      saving.value = false;
    }
  }

  @override
  void onClose() {
    _debounce?.cancel();
    _request++;
    for (final c in [title, doctor, clinic, address, phone, notes]) {
      c.dispose();
    }
    super.onClose();
  }
}
