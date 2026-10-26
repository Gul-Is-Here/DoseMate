import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/utils/care_dates.dart';
import '../models/medicine.dart';
import '../models/visit.dart';
import '../repositories/care_repository.dart';
import 'care_service.dart';

enum CalendarFilter { all, appointments, doses }

/// One row of a day's timeline: a scheduled dose or a visit.
sealed class CalendarEvent {
  const CalendarEvent();

  /// Minutes after local midnight, for ordering.
  int get minutes;
}

class DoseEvent extends CalendarEvent {
  const DoseEvent(this.occurrence, this.log);

  final DoseOccurrence occurrence;
  final DoseLog? log;

  @override
  int get minutes => occurrence.minutes;
}

class VisitEvent extends CalendarEvent {
  const VisitEvent(this.visit);

  final Visit visit;

  @override
  int get minutes => visit.startsAt.hour * 60 + visit.startsAt.minute;
}

/// Everything shown for one local day, computed once per data change.
class DayAgenda {
  DayAgenda(this.day, this.events)
    : visits = events.whereType<VisitEvent>().length,
      doses = events.whereType<DoseEvent>().length,
      taken = events
          .whereType<DoseEvent>()
          .where((e) => e.log?.status == DoseStatus.taken)
          .length,
      logged = events.whereType<DoseEvent>().where((e) => e.log != null).length;

  final DateTime day;

  /// Earliest first; at the same minute, visits before doses.
  final List<CalendarEvent> events;
  final int visits;
  final int doses;
  final int taken;
  final int logged;

  int get remaining => doses - logged;
}

enum RangeStatus { loading, ready, error }

/// The Calendar's week of data for the active profile. Selection (day,
/// filter) lives here too, in a permanent service, so it survives tab
/// switches; the data part is replaced whenever the week, profile or
/// account changes.
///
/// Medicines come from [CareService]'s single live list (all of the
/// profile's medicines, including ones that started months ago). Visits are
/// queried for the visible week only. Dose logs reuse [CareService]'s
/// 30-day window when the week lies inside it, and are otherwise queried
/// for the week alone.
class CalendarService extends GetxService with WidgetsBindingObserver {
  CalendarService(
    this.care, {
    this.debounce = const Duration(milliseconds: 250),
  });

  final CareService care;

  /// Delay before re-querying after the week changes, so tapping through
  /// several weeks quickly opens only the last week's listeners.
  final Duration debounce;

  // Selection.

  late final selectedDay = care.today.value.obs;
  final filter = CalendarFilter.all.obs;

  DateTime get weekStart => weekStartOf(selectedDay.value);

  static DateTime weekStartOf(DateTime day) =>
      CareDates.addDays(CareDates.dateOnly(day), 1 - day.weekday);

  List<DateTime> get week => [
    for (var i = 0; i < 7; i++) CareDates.addDays(weekStart, i),
  ];

  void select(DateTime day) => selectedDay.value = CareDates.dateOnly(day);

  void shiftWeek(int weeks) =>
      select(CareDates.addDays(selectedDay.value, weeks * 7));

  void goToday() => select(care.today.value);

  /// Same day of the month in [year]/[month], clamped to its length
  /// (Jan 31 → Feb 28/29); today when that month is the current one.
  void selectMonth(int year, int month) {
    final today = care.today.value;
    if (today.year == year && today.month == month) return select(today);
    final last = DateTime(year, month + 1, 0).day;
    select(DateTime(year, month, selectedDay.value.day.clamp(1, last)));
  }

  // Data.

  final _visits = <Visit>[];
  final _logs = <String, DoseLog>{};
  bool _ownLogs = false;
  final _status = RangeStatus.loading.obs;
  final error = RxnString();

  /// Bumped whenever derived agendas change; views read it to rebuild.
  final version = 0.obs;

  String? _key;
  DateTime? _rangeStart;
  int _generation = 0;
  Timer? _debounceTimer;
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _loaded = <String>{};
  final _workers = <Worker>[];
  final _cache = <DateTime, DayAgenda>{};

  /// How many times agendas were computed, to check the cache in tests.
  int computations = 0;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _workers.addAll([
      ever(selectedDay, (_) => _syncRange()),
      ever(care.status, (_) => _syncRange()),
      ever(care.medicines, (_) => _invalidate()),
      ever(care.logs, (_) {
        if (!_ownLogs) _invalidate();
      }),
      ever(care.today, _onNewDay),
    ]);
    _syncRange();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final w in _workers) {
      w.dispose();
    }
    _debounceTimer?.cancel();
    _cancel();
    super.onClose();
  }

  /// Back from the background: catch up with a day that changed meanwhile.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) care.rollOver();
  }

  DateTime? _previousToday;

  void _onNewDay(DateTime today) {
    // Someone looking at "today" keeps looking at today.
    final was = _previousToday;
    _previousToday = today;
    if (was != null && selectedDay.value == was) select(today);
    // The logs source may switch (the 30-day window moved).
    _syncRange(force: true);
  }

  RangeStatus get status {
    final s = care.status.value;
    if (s == CareStatus.error) return RangeStatus.error;
    if (s != CareStatus.ready) return RangeStatus.loading;
    return _status.value;
  }

  String? get loadError =>
      care.status.value == CareStatus.error ? care.error.value : error.value;

  Future<void> retry() async {
    if (care.status.value == CareStatus.error) await care.retry();
    _syncRange(force: true);
  }

  void _syncRange({bool force = false}) {
    _previousToday ??= care.today.value;
    // The active profile's data location: own, or the owner's when shared.
    final uid = care.dataUid;
    final pid = care.dataPid;
    final key =
        uid == null || pid == null || care.status.value == CareStatus.idle
        ? null
        : care.dataKey;
    final start = weekStart;
    if (!force && key == _key && start == _rangeStart) return;
    final profileChanged = key != _key;
    _key = key;
    _rangeStart = start;
    // Drop the old week (or profile) at once, never showing it as current.
    _cancel();
    _status.value = RangeStatus.loading;
    _invalidate();
    _debounceTimer?.cancel();
    if (key == null || uid == null || pid == null) return;
    if (profileChanged || debounce == Duration.zero) {
      _listen(uid, pid, start);
    } else {
      _debounceTimer = Timer(debounce, () => _listen(uid, pid, start));
    }
  }

  void _cancel() {
    _generation++;
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
    _loaded.clear();
    _visits.clear();
    _logs.clear();
    error.value = null;
  }

  void _listen(String uid, String pid, DateTime start) {
    final end = CareDates.addDays(start, 7);
    final careLogsFrom = CareDates.addDays(
      care.today.value,
      -CareRepository.historyDays,
    );
    _ownLogs = start.isBefore(careLogsFrom);
    final generation = _generation;
    final needed = _ownLogs ? 2 : 1;

    void track<T>(String name, Stream<T> stream, void Function(T) onData) {
      _subscriptions.add(
        stream.listen(
          (data) {
            if (generation != _generation) return; // an older week/profile
            onData(data);
            _loaded.add(name);
            if (_loaded.length == needed) _status.value = RangeStatus.ready;
            _invalidate();
          },
          onError: (Object e) {
            if (generation != _generation) return;
            error.value = e is CareFailure
                ? e.message
                : 'Could not load this week. Please try again.';
            _status.value = RangeStatus.error;
          },
        ),
      );
    }

    track(
      'visits',
      care.canManageVisits
          ? care.repository.watchVisitsBetween(uid, pid, start, end)
          : Stream.value(<Visit>[]),
      (List<Visit> list) => _visits
        ..clear()
        ..addAll(list),
    );
    if (_ownLogs) {
      track(
        'logs',
        care.canSeeChecklist
            ? care.repository.watchLogsBetween(
                uid,
                pid,
                start,
                end,
                shared: care.isShared,
              )
            : Stream.value(<DoseLog>[]),
        (List<DoseLog> list) => _logs
          ..clear()
          ..addAll({for (final l in list) l.id: l}),
      );
    }
  }

  void _invalidate() {
    _cache.clear();
    version.value++;
  }

  DoseLog? _logFor(DoseOccurrence o) =>
      _ownLogs ? _logs[o.logId] : care.logFor(o);

  /// The agenda for [day] of the loaded week (empty while loading or for
  /// days outside it). Cached until the data changes.
  DayAgenda agendaFor(DateTime day) {
    final d = CareDates.dateOnly(day);
    final start = _rangeStart;
    final inRange =
        start != null &&
        !d.isBefore(start) &&
        d.isBefore(CareDates.addDays(start, 7));
    if (!inRange || status != RangeStatus.ready) return DayAgenda(d, const []);
    return _cache.putIfAbsent(d, () {
      computations++;
      final events = <CalendarEvent>[
        for (final v in _visits)
          if (CareDates.dateOnly(v.startsAt) == d) VisitEvent(v),
        for (final m in care.medicines)
          for (final o in m.occurrencesOn(d)) DoseEvent(o, _logFor(o)),
      ];
      events.sort((a, b) {
        final byTime = a.minutes.compareTo(b.minutes);
        if (byTime != 0) return byTime;
        if (a is VisitEvent && b is DoseEvent) return -1;
        if (a is DoseEvent && b is VisitEvent) return 1;
        return 0;
      });
      return DayAgenda(d, events);
    });
  }

  DayAgenda get selectedAgenda => agendaFor(selectedDay.value);

  /// The selected day's rows after the filter chip.
  List<CalendarEvent> get visibleEvents {
    final events = selectedAgenda.events;
    return switch (filter.value) {
      CalendarFilter.all => events,
      CalendarFilter.appointments => events.whereType<VisitEvent>().toList(),
      CalendarFilter.doses => events.whereType<DoseEvent>().toList(),
    };
  }
}
