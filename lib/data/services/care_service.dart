import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';

import '../../core/utils/care_dates.dart';
import '../models/medicine.dart';
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
  String? _uid;
  String? _profileId;
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _loaded = <String>{};
  Timer? _midnight;
  final _workers = <Worker>[];

  /// Occurrence ids with a log write in flight, to ignore repeated taps.
  final busy = <String>{}.obs;

  DateTime now() => _clock();

  String? get profileId => _profileId;

  @override
  void onInit() {
    super.onInit();
    _workers.addAll([
      ever(profiles.activeProfileId, (_) => _sync()),
      ever(profiles.status, (_) => _sync()),
      ever(profiles.profiles, (_) => _sync()),
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
    final pid = profiles.isReady ? profiles.activeProfile?.id : null;
    final key = uid == null || pid == null ? null : '$uid/$pid';
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
    _uid = uid;
    _profileId = pid;
    status.value = CareStatus.loading;
    today.value = CareDates.dateOnly(_clock());
    _listenMedicines(uid, pid);
    _listenDated(uid, pid);
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
    _key = _uid = _profileId = null;
    medicines.clear();
    visits.clear();
    logs.clear();
    busy.clear();
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
    repository.watchMedicines(uid, pid),
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
      repository.watchUpcomingVisits(uid, pid, day),
      visits.assignAll,
    );
    _listen(
      'logs',
      repository.watchLogs(
        uid,
        pid,
        CareDates.addDays(day, -CareRepository.historyDays),
      ),
      (list) => logs.value = {for (final log in list) log.id: log},
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
    final uid = _uid, pid = _profileId;
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

  String newMedicineId(String pid) =>
      repository.newMedicineId(_requireUid(), pid);

  String newVisitId(String pid) => repository.newVisitId(_requireUid(), pid);

  Future<WriteResult> saveMedicine(
    String pid,
    Medicine medicine, {
    required bool isNew,
  }) => repository.saveMedicine(_requireUid(), pid, medicine, isNew: isNew);

  Future<({String url, String path})> uploadMedicinePhoto(
    String pid,
    String medicineId,
    File file,
  ) => repository.uploadMedicinePhoto(_requireUid(), pid, medicineId, file);

  Future<void> deletePhoto(String path) => repository.deletePhoto(path);

  Future<WriteResult> setMedicineStatus(Medicine m, MedicineStatus status) =>
      repository.setMedicineStatus(_requireUid(), _activePid, m.id, status);

  Future<WriteResult> addSupply(Medicine m, int count) =>
      repository.addSupply(_requireUid(), _activePid, m.id, count);

  /// Deletes [m] with its loaded logs; its photo is removed afterwards.
  Future<WriteResult> deleteMedicine(String pid, Medicine m) async {
    final result = await repository.deleteMedicine(
      _requireUid(),
      pid,
      m.id,
      logIds: pid == _profileId
          ? logs.values.where((l) => l.medicineId == m.id).map((l) => l.id)
          : const [],
    );
    if (m.photoPath case final path?) await repository.deletePhoto(path);
    return result;
  }

  /// Marks one dose taken or skipped. Ignored while the same dose is
  /// already being written, and when it already has that status.
  Future<WriteResult?> logDose(DoseOccurrence o, DoseStatus status) async {
    final previous = logFor(o);
    if (busy.contains(o.logId) || previous?.status == status) return null;
    final wasTaken = previous?.status == DoseStatus.taken;
    final isTaken = status == DoseStatus.taken;
    busy.add(o.logId);
    try {
      return await repository.logDose(
        _requireUid(),
        _activePid,
        o,
        status,
        supplyChange: wasTaken == isTaken
            ? 0
            : isTaken
            ? (o.medicine.quantity > 0 ? -1 : 0)
            : 1,
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
        supplyChange: log.status == DoseStatus.taken ? 1 : 0,
      );
    } finally {
      busy.remove(log.id);
    }
  }

  Future<WriteResult> saveVisit(
    String pid,
    Visit visit, {
    required bool isNew,
  }) => repository.saveVisit(_requireUid(), pid, visit, isNew: isNew);

  Future<WriteResult> cancelVisit(String pid, String id) =>
      repository.cancelVisit(_requireUid(), pid, id);

  Future<WriteResult> deleteVisit(String pid, String id) =>
      repository.deleteVisit(_requireUid(), pid, id);

  /// Writes from list screens act on the data shown, which is the profile
  /// the listeners belong to.
  String get _activePid {
    final pid = _profileId;
    if (pid == null) {
      throw const CareFailure('Your schedule is still loading. Try again.');
    }
    return pid;
  }
}
