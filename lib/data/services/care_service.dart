import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';

import '../../core/utils/care_dates.dart';
import '../models/medicine.dart';
import '../models/user_profile.dart';
import '../models/visit.dart';
import '../repositories/care_repository.dart';
import 'profile_service.dart';

enum CareStatus { idle, loading, ready, error }

/// The active profile's medicines, upcoming visits and recent dose logs,
/// shared by every screen. One set of listeners exists at a time; it is
/// replaced whenever the account or active profile changes, and cleared on
/// sign out, so one profile's data never shows under another.
class CareService extends GetxService {
  CareService(
    this.repository,
    this.profiles, {
    DateTime Function()? clock,
    this.autoRollOver = true,
  }) : _clock = clock ?? DateTime.now;

  /// Off in tests, which call [rollOver] themselves.
  final bool autoRollOver;

  final CareRepository repository;
  final ProfileService profiles;
  final DateTime Function() _clock;

  final medicines = <Medicine>[].obs;
  final visits = <Visit>[].obs;
  final logs = <String, DoseLog>{}.obs;
  final status = CareStatus.idle.obs;
  final error = RxnString();

  /// The local day everything is derived for; moves on at midnight.
  late final today = CareDates.dateOnly(_clock()).obs;

  /// Account and profile the current data belongs to ("uid/profileId").
  String? _key;
  String? _profileId;

  /// Where the active profile's records live: the signed-in account's own,
  /// or the owner's for a profile shared with it.
  String? _dataUid;
  String? _dataPid;
  SharedAccess? _share;
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _loaded = <String>{};
  Timer? _midnight;
  final _workers = <Worker>[];

  /// Last known revision of each loaded log, undone ones included.
  final _revs = <String, int>{};

  DoseTap _action(String logId) =>
      DoseTap.at(_clock(), previousRev: _revs[logId]);

  /// Occurrence ids with a log write in flight, to ignore repeated taps.
  final busy = <String>{}.obs;

  /// Snoozes (occurrence id → until), shared by Home, Medication Details
  /// and Notifications. Kept in memory; listeners in [onSnooze] re-arm the
  /// dose's alarm and hold off the server's follow-up.
  final snoozed = <String, DateTime>{}.obs;

  static const snoozeFor = Duration(minutes: 15);

  /// Told of each snooze of an owned profile's dose (see AlarmService).
  final onSnooze =
      <void Function(DoseOccurrence o, String pid, DateTime until)>[];

  void snooze(DoseOccurrence o) {
    final until = _clock().add(snoozeFor);
    snoozed[o.logId] = until;
    final pid = _profileId;
    if (pid == null || isShared) return;
    for (final f in List.of(onSnooze)) {
      f(o, pid, until);
    }
  }

  bool isSnoozed(DoseOccurrence o) =>
      snoozed[o.logId]?.isAfter(_clock()) ?? false;

  DateTime now() => _clock();

  String? get profileId => _profileId;

  /// Account and profile ids the active profile's records are stored under.
  String? get dataUid => _dataUid;
  String? get dataPid => _dataPid;

  /// Identifies the current data (account, profile and shared access), so
  /// other services can tell when to reload.
  String? get dataKey => _key;

  /// The active profile belongs to another account (read through the
  /// caregiver-safe copies and the permissions granted).
  bool get isShared => _share != null;

  CarePermissions? get permissions => _share?.permissions;

  bool get canSeeChecklist => _share?.permissions.checklist ?? true;
  bool get canManageVisits => _share?.permissions.appointments ?? true;

  @override
  void onInit() {
    super.onInit();
    _workers.addAll([
      ever(profiles.activeProfileId, (_) => _sync()),
      ever(profiles.status, (_) => _sync()),
      ever(profiles.profiles, (_) => _sync()),
      // Access granted, changed or revoked by a profile's owner.
      ever(profiles.shared, (_) => _sync()),
    ]);
    _sync();
  }

  @override
  void onClose() {
    for (final w in _workers) {
      w.dispose();
    }
    _stop();
    super.onClose();
  }

  /// Starts listening for the signed-in account's active profile, or stops
  /// everything when there is none.
  void _sync({bool force = false}) {
    final uid = profiles.uid;
    final active = profiles.isReady ? profiles.activeProfile : null;
    final pid = active?.id;
    final share = active?.share;
    final access = share?.permissions;
    final key = uid == null || pid == null
        ? null
        : share == null
        ? '$uid/$pid'
        : '$uid/$pid/${access!.checklist}${access.appointments}';
    if (uid != null && pid == null) {
      // Signed in but no profile to hold records yet. Never just wait:
      // create Myself (the profile listener then brings us back here), or
      // report why there is nothing to show.
      _stop();
      if (profiles.status.value == ProfilesStatus.error) {
        error.value =
            profiles.error.value ??
            'Your profile isn’t ready yet. Check your connection and retry.';
        status.value = CareStatus.error;
      } else if (profiles.isReady && profiles.selfProfile == null) {
        status.value = CareStatus.loading;
        profiles.ensureSelf();
      } else if (profiles.isReady) {
        error.value =
            'Your profile isn’t ready yet. Check your connection and retry.';
        status.value = CareStatus.error;
      } else {
        status.value = CareStatus.loading;
      }
      return;
    }
    if (!force && key == _key && status.value != CareStatus.error) return;
    _stop();
    if (uid == null || pid == null) return;
    _key = key;
    _profileId = pid;
    _share = share;
    _dataUid = share?.ownerUid ?? uid;
    _dataPid = share?.profileId ?? pid;
    status.value = CareStatus.loading;
    today.value = CareDates.dateOnly(_clock());
    _listenMedicines(_dataUid!, _dataPid!);
    _listenDated(_dataUid!, _dataPid!);
    _scheduleMidnight();
  }

  void _stop() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
    _loaded.clear();
    _midnight?.cancel();
    _midnight = null;
    _key = _profileId = _dataUid = _dataPid = null;
    _share = null;
    medicines.clear();
    visits.clear();
    logs.clear();
    _revs.clear();
    busy.clear();
    snoozed.clear();
    error.value = null;
    status.value = CareStatus.idle;
  }

  Future<void> retry() async {
    if (profiles.uid != null &&
        (!profiles.isReady || profiles.activeProfile == null)) {
      await profiles.retry();
    }
    _sync(force: true);
  }

  void _listenMedicines(String uid, String pid) => _listen(
    'medicines',
    canSeeChecklist
        ? repository.watchMedicines(uid, pid, shared: isShared)
        : Stream.value(<Medicine>[]),
    (list) => medicines.assignAll(
      list
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
    ),
  );

  /// Visits from today and logs of the last [CareRepository.historyDays]
  /// days; re-run at midnight so the windows follow the local day.
  void _listenDated(String uid, String pid) {
    final day = today.value;
    _listen(
      'visits',
      canManageVisits
          ? repository.watchUpcomingVisits(uid, pid, day)
          : Stream.value(<Visit>[]),
      visits.assignAll,
    );
    _listen(
      'logs',
      canSeeChecklist
          ? repository.watchLogs(
              uid,
              pid,
              CareDates.addDays(day, -CareRepository.historyDays),
              shared: isShared,
              includeCleared: !isShared,
            )
          : Stream.value(<DoseLog>[]),
      (list) {
        _revs
          ..clear()
          ..addAll({for (final log in list) log.id: log.rev});
        logs.value = {
          for (final log in list)
            if (!log.isUndone) log.id: log,
        };
      },
    );
  }

  void _listen<T>(String name, Stream<T> stream, void Function(T) onData) {
    final key = _key;
    late final StreamSubscription<T> subscription;
    subscription = stream.listen(
      (data) {
        if (_key != key) return;
        onData(data);
        _loaded.add(name);
        if (_loaded.length == 3 && status.value != CareStatus.error) {
          status.value = CareStatus.ready;
        }
      },
      onError: (Object e) {
        if (_key != key) return;
        error.value = e is CareFailure
            ? e.message
            : 'Could not load your schedule. Please try again.';
        status.value = CareStatus.error;
      },
    );
    _subscriptions.add(subscription);
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    if (!autoRollOver) return;
    final now = _clock();
    final next = CareDates.addDays(CareDates.dateOnly(now), 1);
    _midnight = Timer(
      next.difference(now) + const Duration(seconds: 1),
      rollOver,
    );
  }

  /// Moves to the new local day: re-queries the dated windows.
  void rollOver() {
    final uid = _dataUid, pid = _dataPid;
    if (uid == null || pid == null) return;
    final day = CareDates.dateOnly(_clock());
    if (day != today.value) {
      today.value = day;
      // Medicines don't depend on the day; only re-query the dated streams.
      for (final s in _subscriptions.skip(1)) {
        s.cancel();
      }
      _subscriptions.removeRange(1, _subscriptions.length);
      _loaded
        ..remove('visits')
        ..remove('logs');
      _listenDated(uid, pid);
    }
    _scheduleMidnight();
  }

  // Derived data.

  Medicine? medicineById(String id) =>
      medicines.firstWhereOrNull((m) => m.id == id);

  /// Scheduled doses on [day] for active medicines, earliest first.
  List<DoseOccurrence> occurrencesOn(DateTime day) =>
      [for (final m in medicines) ...m.occurrencesOn(day)]
        ..sort((a, b) => a.minutes.compareTo(b.minutes));

  List<DoseOccurrence> get todaysDoses => occurrencesOn(today.value);

  DoseLog? logFor(DoseOccurrence o) => logs[o.logId];

  /// The first of today's doses not yet taken or skipped (overdue ones
  /// first, since they are earlier).
  DoseOccurrence? get nextDose =>
      todaysDoses.firstWhereOrNull((o) => logFor(o) == null);

  /// Today's logs, including as needed doses, most recent first.
  List<DoseLog> logsOn(DateTime day) =>
      logs.values.where((l) => l.day == day).toList()
        ..sort((a, b) => b.shownTime.compareTo(a.shownTime));

  List<DoseLog> recentLogs(String medicineId, {int limit = 2}) =>
      (logs.values.where((l) => l.medicineId == medicineId).toList()
            ..sort((a, b) => b.shownTime.compareTo(a.shownTime)))
          .take(limit)
          .toList();

  DoseLog? takenToday(String medicineId) => logsOn(today.value)
      .firstWhereOrNull(
        (l) => l.medicineId == medicineId && l.status == DoseStatus.taken,
      );

  /// Consecutive days, ending today (if complete) or yesterday, on which
  /// every scheduled dose of [m] was taken. Limited to the loaded history.
  int streak(Medicine m) {
    var count = 0;
    var day = today.value;
    final todays = m.occurrencesOn(day);
    if (todays.isEmpty || !todays.every(_taken)) {
      day = CareDates.addDays(day, -1);
    }
    for (var i = 0; i < CareRepository.historyDays; i++) {
      if (day.isBefore(m.startDate)) break;
      final doses = m.occurrencesOn(day);
      if (doses.isNotEmpty) {
        if (!doses.every(_taken)) break;
        count++;
      }
      day = CareDates.addDays(day, -1);
    }
    return count;
  }

  bool _taken(DoseOccurrence o) => logFor(o)?.status == DoseStatus.taken;

  /// Medicines that need a refill soon, lowest supply first.
  List<Medicine> get lowSupply =>
      medicines.where((m) => m.isLowSupply).toList()
        ..sort((a, b) => a.quantity.compareTo(b.quantity));

  // Writes. Each takes the profile explicitly so a form saves to the
  // profile it was opened for, even if the active profile changes.

  String _requireUid() {
    final uid = profiles.uid;
    if (uid == null) {
      throw const CareFailure('You are signed out. Sign in and try again.');
    }
    return uid;
  }

  static const _viewOnly = CareFailure(
    'This profile is shared with you. You can view it, but only its owner '
    'can make this change.',
  );

  /// The stored location of [pid]'s records, for a write. Shared profiles
  /// allow only what their owner granted ([visits]: appointment changes).
  (String, String) _target(String pid, {bool visits = false}) {
    final share = profiles.byId(pid)?.share;
    if (share == null) return (_requireUid(), pid);
    if (!visits || !share.permissions.appointments) throw _viewOnly;
    return (share.ownerUid, share.profileId);
  }

  String newMedicineId(String pid) {
    final (uid, id) = _target(pid);
    return repository.newMedicineId(uid, id);
  }

  String newVisitId(String pid) {
    final (uid, id) = _target(pid, visits: true);
    return repository.newVisitId(uid, id);
  }

  /// Saves [medicine]. Pass the saved version as [previous] when editing,
  /// so a schedule or status change only applies from today.
  Future<WriteResult> saveMedicine(
    String pid,
    Medicine medicine, {
    required bool isNew,
    Medicine? previous,
  }) {
    final (uid, id) = _target(pid);
    return repository.saveMedicine(
      uid,
      id,
      previous == null
          ? medicine
          : medicine.withHistoryFrom(previous, today.value),
      isNew: isNew,
    );
  }

  Future<({String url, String path})> uploadMedicinePhoto(
    String pid,
    String medicineId,
    File file,
  ) {
    final (uid, id) = _target(pid);
    return repository.uploadMedicinePhoto(uid, id, medicineId, file);
  }

  Future<void> deletePhoto(String path) => repository.deletePhoto(path);

  Future<WriteResult> setMedicineStatus(Medicine m, MedicineStatus status) =>
      repository.setMedicineStatus(
        _requireUid(),
        _activePid,
        m.withStatus(status, today.value),
      );

  Future<WriteResult> addSupply(Medicine m, int count) =>
      repository.addSupply(_requireUid(), _activePid, m.id, count);

  /// Deletes [m] with all its dose logs; its photo is removed afterwards.
  Future<WriteResult> deleteMedicine(String pid, Medicine m) async {
    final (uid, id) = _target(pid);
    final result = await repository.deleteMedicine(
      uid,
      id,
      m.id,
      // Undone logs too (known by their revisions); the repository also
      // finds those not loaded.
      logIds: pid == _profileId
          ? {
              ...logs.values
                  .where((l) => l.medicineId == m.id)
                  .map((l) => l.id),
              ..._revs.keys.where((id) => id.startsWith('${m.id}_')),
            }
          : const <String>{},
    );
    if (m.photoPath case final path?) await repository.deletePhoto(path);
    return result;
  }

  /// Marks one dose taken or skipped. Ignored while the same dose is
  /// already being written, and when it already has that status.
  Future<WriteResult?> logDose(
    DoseOccurrence o,
    DoseStatus status, {
    String? note,
  }) async {
    final previous = logFor(o);
    if (busy.contains(o.logId)) return null;
    if (previous?.status == status &&
        (note == null || note == previous?.note)) {
      return null;
    }
    busy.add(o.logId);
    try {
      return await repository.logDose(
        _requireUid(),
        _activePid,
        o,
        status,
        action: _action(o.logId),
        note: note,
        replacesLegacyTaken: previous?.isLegacyTaken ?? false,
      );
    } finally {
      busy.remove(o.logId);
    }
  }

  /// Logs an as needed dose now (or the first free minute after it).
  Future<WriteResult?> logAsNeeded(Medicine m) {
    final now = _clock();
    var minutes = now.hour * 60 + now.minute;
    while (minutes < 1439 &&
        logs.containsKey(DoseLog.idFor(m.id, today.value, minutes))) {
      minutes++;
    }
    return logDose(DoseOccurrence(m, today.value, minutes), DoseStatus.taken);
  }

  Future<WriteResult?> undoDose(DoseLog log) async {
    if (busy.contains(log.id)) return null;
    busy.add(log.id);
    try {
      return await repository.undoDose(
        _requireUid(),
        _activePid,
        log,
        action: _action(log.id),
      );
    } finally {
      busy.remove(log.id);
    }
  }

  Future<WriteResult> saveVisit(
    String pid,
    Visit visit, {
    required bool isNew,
  }) {
    final (uid, id) = _target(pid, visits: true);
    return repository.saveVisit(uid, id, visit, isNew: isNew);
  }

  Future<WriteResult> cancelVisit(String pid, String id) {
    final (uid, profile) = _target(pid, visits: true);
    return repository.cancelVisit(uid, profile, id);
  }

  /// Only owners delete visits; caregivers can cancel them.
  Future<WriteResult> deleteVisit(String pid, String id) {
    final (uid, profile) = _target(pid);
    return repository.deleteVisit(uid, profile, id);
  }

  /// Writes from list screens act on the data shown, which is the profile
  /// the listeners belong to.
  String get _activePid {
    final pid = _profileId;
    if (isShared) throw _viewOnly;
    if (pid == null) {
      throw const CareFailure('Your schedule is still loading. Try again.');
    }
    return pid;
  }
}
