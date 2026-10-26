import 'dart:async';

import 'package:get/get.dart';

import '../../core/utils/care_dates.dart';
import '../../core/utils/dose_state.dart';
import '../models/medicine.dart';
import '../repositories/care_repository.dart';
import 'care_service.dart';

enum HistoryRange { daily, weekly, monthly }

enum HistoryStatus { idle, loading, ready, error }

enum PageStatus { idle, loading, error, end }

/// Counts for the summary card: what was recorded in the range, and how
/// many past scheduled doses have no record yet.
class HistorySummary {
  const HistorySummary(this.taken, this.skipped, this.unmarked);

  final int taken;
  final int skipped;
  final int unmarked;

  int get recorded => taken + skipped;
}

/// Log History for the active profile. A permanent service, so filters,
/// loaded pages and the scroll position survive tab switches.
///
/// The newest [pageSize] logs of the current query are live; older pages
/// are read once each, from a cursor after the oldest loaded log. Both feed
/// one id-keyed map, so a log never shows twice.
class HistoryService extends GetxService {
  HistoryService(this.care, {this.pageSize = 20});

  final CareService care;
  final int pageSize;

  // Filters and view state.

  final range = HistoryRange.weekly.obs;
  final medicineId = RxnString();
  final statusFilter = Rxn<DoseStatus>();
  final newestFirst = true.obs;

  /// Where the list was scrolled to, restored when the tab is reopened.
  double scrollOffset = 0;

  /// First local day of [range], and the day after its last (today).
  (DateTime, DateTime) get bounds {
    final today = care.today.value;
    final days = switch (range.value) {
      HistoryRange.daily => 1,
      HistoryRange.weekly => 7,
      HistoryRange.monthly => CareRepository.historyDays,
    };
    return (CareDates.addDays(today, 1 - days), CareDates.addDays(today, 1));
  }

  HistoryQuery get query {
    final (from, to) = bounds;
    return HistoryQuery(
      from: from,
      to: to,
      medicineId: medicineId.value,
      status: statusFilter.value,
      newestFirst: newestFirst.value,
    );
  }

  // Data.

  final status = HistoryStatus.idle.obs;
  final pageStatus = PageStatus.idle.obs;
  final error = RxnString();
  final pageError = RxnString();

  /// Loaded logs in query order.
  final entries = <DoseLog>[].obs;

  final _byId = <String, DoseLog>{};
  var _headIds = <String>{};
  StreamSubscription<List<DoseLog>>? _head;
  String? _key;
  HistoryQuery? _query;
  int _generation = 0;
  bool _active = false;
  final _workers = <Worker>[];

  @override
  void onInit() {
    super.onInit();
    _workers.addAll([
      // Profile switch, sign out, retry: drop everything at once.
      ever(care.status, (_) => _sync()),
      ever(care.today, (_) => _sync()),
      everAll([range, medicineId, statusFilter, newestFirst], (_) {
        scrollOffset = 0;
        _sync();
      }),
    ]);
  }

  @override
  void onClose() {
    for (final w in _workers) {
      w.dispose();
    }
    _cancel();
    super.onClose();
  }

  /// Called when the screen opens; listening starts on first use only.
  void activate() {
    _active = true;
    _sync();
  }

  Future<void> retry() async {
    if (care.status.value == CareStatus.error) await care.retry();
    _sync(force: true);
  }

  void _sync({bool force = false}) {
    // The active profile's data location: own, or the owner's when shared.
    final uid = care.dataUid;
    final pid = care.dataPid;
    final key =
        uid == null || pid == null || care.status.value == CareStatus.idle
        ? null
        : care.dataKey;
    if (key != _key) {
      scrollOffset = 0;
      if (medicineId.value != null) {
        // Another profile's medicine filter means nothing here. Clearing it
        // re-enters this method through the filter worker, which reloads.
        _cancel();
        entries.clear();
        _byId.clear();
        _key = key;
        medicineId.value = null;
        return;
      }
    }
    final q = query;
    if (!force && key == _key && q == _query && _head != null) return;
    _cancel();
    _key = key;
    _query = q;
    entries.clear();
    _byId.clear();
    _headIds = {};
    error.value = pageError.value = null;
    pageStatus.value = PageStatus.idle;
    if (key == null || uid == null || pid == null || !_active) {
      status.value = HistoryStatus.idle;
      return;
    }
    if (!care.canSeeChecklist) {
      // A caregiver without "View daily dose checklist" sees no dose logs.
      status.value = HistoryStatus.ready;
      pageStatus.value = PageStatus.end;
      return;
    }
    status.value = HistoryStatus.loading;
    final generation = _generation;
    _head = care.repository
        .watchHistoryHead(uid, pid, q, pageSize, shared: care.isShared)
        .listen(
          (head) {
            if (generation != _generation) return; // an older query
            _reconcileHead(head, q);
            status.value = HistoryStatus.ready;
          },
          onError: (Object e) {
            if (generation != _generation) return;
            error.value = e is CareFailure
                ? e.message
                : 'Could not load your history. Please try again.';
            status.value = HistoryStatus.error;
          },
        );
  }

  void _cancel() {
    _generation++;
    _head?.cancel();
    _head = null;
  }

  /// Applies a live snapshot of the newest logs. A log that left the head
  /// was deleted (or no longer matches) if it still sorts inside the
  /// head's range; otherwise newer logs pushed it out and it stays.
  void _reconcileHead(List<DoseLog> head, HistoryQuery q) {
    final ids = {for (final l in head) l.id};
    final full = head.length >= pageSize;
    for (final id in _headIds.difference(ids)) {
      final old = _byId[id];
      if (old == null) continue;
      if (!full || q.compare(old, head.last) <= 0) _byId.remove(id);
    }
    for (final l in head) {
      _byId[l.id] = l;
    }
    _headIds = ids;
    // A head with room to spare holds everything that matches.
    if (!full && pageStatus.value != PageStatus.loading) {
      pageStatus.value = PageStatus.end;
    }
    _publish(q);
  }

  void _publish(HistoryQuery q) =>
      entries.value = _byId.values.toList()..sort(q.compare);

  /// Loads the page after the oldest loaded log. Ignored while one is
  /// loading, at the end, or before the first page arrived.
  Future<void> loadMore() async {
    final uid = care.dataUid, pid = care.dataPid, q = _query;
    if (uid == null || pid == null || q == null) return;
    if (status.value != HistoryStatus.ready) return;
    if (pageStatus.value == PageStatus.loading ||
        pageStatus.value == PageStatus.end ||
        entries.isEmpty) {
      return;
    }
    final generation = _generation;
    pageStatus.value = PageStatus.loading;
    pageError.value = null;
    try {
      final page = await care.repository.fetchHistoryPage(
        uid,
        pid,
        q,
        after: entries.last,
        limit: pageSize,
        shared: care.isShared,
      );
      if (generation != _generation) return;
      for (final l in page.logs) {
        _byId.putIfAbsent(l.id, () => l);
      }
      _publish(q);
      // Offline, a short page may only mean the cache is incomplete.
      pageStatus.value = page.logs.length < pageSize && !page.fromCache
          ? PageStatus.end
          : PageStatus.idle;
    } on CareFailure catch (e) {
      if (generation != _generation) return;
      pageError.value = e.message;
      pageStatus.value = PageStatus.error;
    }
  }

  // Summary, from the profile's live 30-day logs (no extra reads).

  HistorySummary get summary {
    final (from, to) = bounds;
    final filter = medicineId.value;
    var taken = 0, skipped = 0, unmarked = 0;
    for (final l in care.logs.values) {
      if (l.day.isBefore(from) || !l.day.isBefore(to)) continue;
      if (filter != null && l.medicineId != filter) continue;
      l.status == DoseStatus.taken ? taken++ : skipped++;
    }
    final now = care.now();
    for (var d = from; d.isBefore(to); d = CareDates.addDays(d, 1)) {
      for (final m in care.medicines) {
        if (filter != null && m.id != filter) continue;
        for (final o in m.occurrencesOn(d)) {
          final state = DoseStates.of(o, care.logFor(o), now);
          if (state == DoseState.overdue || state == DoseState.missed) {
            unmarked++;
          }
        }
      }
    }
    return HistorySummary(taken, skipped, unmarked);
  }

  /// Logs for export: the summary's range and filters, from the live
  /// 30-day logs, oldest first.
  List<DoseLog> exportLogs() {
    final (from, to) = bounds;
    return care.logs.values
        .where(
          (l) =>
              !l.day.isBefore(from) &&
              l.day.isBefore(to) &&
              (medicineId.value == null || l.medicineId == medicineId.value) &&
              (statusFilter.value == null || l.status == statusFilter.value),
        )
        .toList()
      ..sort(HistoryQuery(from: from, to: to, newestFirst: false).compare);
  }
}
