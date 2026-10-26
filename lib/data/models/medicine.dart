import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/care_dates.dart';

enum Frequency {
  onceDaily('Once daily'),
  multipleDaily('Multiple times daily'),
  specificDays('Specific days'),
  asNeeded('As needed (PRN)');

  const Frequency(this.label);

  final String label;

  /// Whether doses are scheduled at fixed times (as needed ones aren't).
  bool get isScheduled => this != asNeeded;
}

/// Active ones are scheduled; paused, archived and draft ones are not.
enum MedicineStatus { active, paused, archived, draft }

/// One medicine of one profile, stored at
/// `users/{uid}/profiles/{profileId}/medicines/{id}`.
class Medicine {
  const Medicine({
    required this.id,
    required this.name,
    required this.frequency,
    required this.doseMinutes,
    required this.startDate,
    required this.courseDays,
    this.dosage = '',
    this.notes = '',
    this.days = const [],
    this.quantity = 0,
    this.lowSupplyWarning = true,
    this.status = MedicineStatus.active,
    this.photoUrl,
    this.photoPath,
    this.pastSchedules = const [],
    this.pauses = const [],
    this.isPending = false,
  });

  static const maxCourseDays = 3650;

  /// Most schedule versions and pauses kept; older ones are dropped.
  static const maxHistory = 30;

  factory Medicine.fromMap(
    String id,
    Map<String, dynamic> data, {
    bool isPending = false,
  }) {
    final start =
        CareDates.parseDay(data['startDay']) ??
        CareDates.dateOnly(DateTime.now());
    final end = CareDates.parseDay(data['endDay']) ?? start;
    return Medicine(
      id: id,
      name: data['name'] as String? ?? '',
      dosage: data['dosage'] as String? ?? '',
      notes: data['notes'] as String? ?? '',
      frequency:
          Frequency.values.asNameMap()[data['frequency']] ??
          Frequency.onceDaily,
      doseMinutes: [
        for (final m in data['doseMinutes'] as List? ?? const [])
          if (m is int && m >= 0 && m < 1440) m,
      ]..sort(),
      days: [
        for (final d in data['days'] as List? ?? const [])
          if (d is int && d >= 1 && d <= 7) d,
      ]..sort(),
      startDate: start,
      courseDays: CareDates.daysBetween(start, end) + 1,
      quantity: (data['quantity'] as num?)?.toInt() ?? 0,
      lowSupplyWarning: data['lowSupplyWarning'] as bool? ?? false,
      status:
          MedicineStatus.values.asNameMap()[data['status']] ??
          MedicineStatus.active,
      photoUrl: data['photoUrl'] as String?,
      photoPath: data['photoPath'] as String?,
      pastSchedules: [
        for (final v in data['pastSchedules'] as List? ?? const [])
          ?ScheduleVersion.fromMap(v),
      ]..sort((a, b) => a.until.compareTo(b.until)),
      pauses: [
        for (final p in data['pauses'] as List? ?? const [])
          ?PauseRange.fromMap(p),
      ]..sort((a, b) => a.from.compareTo(b.from)),
      isPending: isPending,
    );
  }

  final String id;
  final String name;

  /// Free text such as "500mg - 1 capsule".
  final String dosage;
  final String notes;
  final Frequency frequency;

  /// Reminder times in minutes after local midnight, ascending.
  final List<int> doseMinutes;

  /// ISO weekdays (1 = Monday) for [Frequency.specificDays].
  final List<int> days;

  /// First local day of the course.
  final DateTime startDate;

  /// Length of the course in days, including the first and last day.
  final int courseDays;

  /// Doses on hand; taking a dose lowers it, a refill raises it.
  final int quantity;
  final bool lowSupplyWarning;
  final MedicineStatus status;
  final String? photoUrl;
  final String? photoPath;

  /// Schedules this medicine had before it was last edited, oldest first,
  /// so past days keep the doses they really had.
  final List<ScheduleVersion> pastSchedules;

  /// Days it was paused or archived, oldest first; the last one may still
  /// be open.
  final List<PauseRange> pauses;

  /// Saved on this device but not yet confirmed by the server.
  final bool isPending;

  /// Last local day of the course.
  DateTime get endDate => CareDates.addDays(startDate, courseDays - 1);

  bool get isActive => status == MedicineStatus.active;

  /// Scheduled doses per scheduled day (0 for as needed).
  int get dosesPerDay => frequency.isScheduled ? doseMinutes.length : 0;

  /// The schedule that applied on [day]: a past version, or the current one.
  ScheduleVersion scheduleOn(DateTime day) {
    final d = CareDates.dateOnly(day);
    for (final v in pastSchedules) {
      if (d.isBefore(v.until)) return v;
    }
    return ScheduleVersion(
      until: DateTime(9999),
      frequency: frequency,
      doseMinutes: doseMinutes,
      days: days,
    );
  }

  bool isPausedOn(DateTime day) {
    final d = CareDates.dateOnly(day);
    return pauses.any((p) => p.covers(d));
  }

  /// Whether [day] has scheduled doses. Past days use the schedule and
  /// pauses of the time, so editing or pausing never rewrites history.
  bool isScheduledOn(DateTime day) {
    if (status == MedicineStatus.draft) return false;
    final d = CareDates.dateOnly(day);
    if (d.isBefore(startDate) || d.isAfter(endDate)) return false;
    if (isPausedOn(d)) return false;
    // Paused or archived before pauses were recorded: no known start.
    if (!isActive && !pauses.any((p) => p.until == null)) return false;
    final s = scheduleOn(d);
    return s.frequency.isScheduled &&
        (s.frequency != Frequency.specificDays || s.days.contains(d.weekday));
  }

  List<DoseOccurrence> occurrencesOn(DateTime day) => isScheduledOn(day)
      ? [
          for (final m in scheduleOn(day).doseMinutes)
            DoseOccurrence(this, CareDates.dateOnly(day), m),
        ]
      : const [];

  /// [edited] (this medicine after an edit) with this one's history, plus
  /// the replaced schedule when the edit changed it. The new schedule
  /// applies from [today]; earlier days keep the old one.
  Medicine withHistoryFrom(Medicine old, DateTime today) {
    final day = CareDates.dateOnly(today);
    var past = old.pastSchedules;
    final changed =
        old.frequency != frequency ||
        !_sameList(old.doseMinutes, doseMinutes) ||
        !_sameList(old.days, days);
    if (changed &&
        old.status != MedicineStatus.draft &&
        old.startDate.isBefore(day)) {
      final previous = old.scheduleOn(CareDates.addDays(day, -1));
      past = [
        // An earlier edit today is replaced: today uses the latest schedule.
        for (final v in past)
          if (v.until.isBefore(day)) v,
        ScheduleVersion(
          until: day,
          frequency: previous.frequency,
          doseMinutes: previous.doseMinutes,
          days: previous.days,
        ),
      ];
    }
    return _with(
      pastSchedules: _last(past),
      pauses: _pausesFor(old.pauses, status, day),
    );
  }

  /// This medicine with [next] status from [today], recording the pause.
  Medicine withStatus(MedicineStatus next, DateTime today) => _with(
    status: next,
    pauses: _pausesFor(pauses, next, CareDates.dateOnly(today)),
  );

  /// Opens a pause when the medicine stops (paused or archived) and closes
  /// it when it starts again; a pause undone the same day leaves no trace.
  static List<PauseRange> _pausesFor(
    List<PauseRange> pauses,
    MedicineStatus status,
    DateTime day,
  ) {
    final open = pauses.lastOrNull?.until == null ? pauses.lastOrNull : null;
    final stopped =
        status == MedicineStatus.paused || status == MedicineStatus.archived;
    if (stopped && open == null) {
      return _last([...pauses, PauseRange(from: day)]);
    }
    if (status == MedicineStatus.active && open != null) {
      final rest = pauses.sublist(0, pauses.length - 1);
      return open.from.isBefore(day)
          ? [...rest, PauseRange(from: open.from, until: day)]
          : rest;
    }
    return pauses;
  }

  static List<T> _last<T>(List<T> list) =>
      list.length <= maxHistory ? list : list.sublist(list.length - maxHistory);

  static bool _sameList(List<int> a, List<int> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);

  /// Remaining doses at which the low supply warning starts: two days'
  /// worth, or 4 for as needed medicines.
  int get lowSupplyThreshold => dosesPerDay == 0 ? 4 : dosesPerDay * 2;

  bool get isLowSupply =>
      lowSupplyWarning &&
      status != MedicineStatus.archived &&
      status != MedicineStatus.draft &&
      quantity <= lowSupplyThreshold;

  /// Whole days the supply lasts at the scheduled rate, or null if unknown.
  int? get daysOfSupply => dosesPerDay == 0 ? null : quantity ~/ dosesPerDay;

  /// The fields written on save. Bookkeeping fields (createdAt, updatedAt)
  /// are added by the repository.
  Map<String, Object?> toWriteMap() => {
    'name': name,
    'dosage': dosage,
    'notes': notes,
    'frequency': frequency.name,
    'doseMinutes': doseMinutes,
    'days': days,
    'startDay': CareDates.dayKey(startDate),
    'endDay': CareDates.dayKey(endDate),
    'quantity': quantity,
    'lowSupplyWarning': lowSupplyWarning,
    'status': status.name,
    'photoUrl': photoUrl ?? FieldValue.delete(),
    'photoPath': photoPath ?? FieldValue.delete(),
    'pastSchedules': [for (final v in pastSchedules) v.toMap()],
    'pauses': [for (final p in pauses) p.toMap()],
  };

  Medicine copyWith({
    MedicineStatus? status,
    int? quantity,
    String? photoUrl,
    String? photoPath,
  }) => Medicine(
    id: id,
    name: name,
    dosage: dosage,
    notes: notes,
    frequency: frequency,
    doseMinutes: doseMinutes,
    days: days,
    startDate: startDate,
    courseDays: courseDays,
    quantity: quantity ?? this.quantity,
    lowSupplyWarning: lowSupplyWarning,
    status: status ?? this.status,
    photoUrl: photoUrl ?? this.photoUrl,
    photoPath: photoPath ?? this.photoPath,
    pastSchedules: pastSchedules,
    pauses: pauses,
    isPending: isPending,
  );

  Medicine _with({
    MedicineStatus? status,
    List<ScheduleVersion>? pastSchedules,
    List<PauseRange>? pauses,
  }) => Medicine(
    id: id,
    name: name,
    dosage: dosage,
    notes: notes,
    frequency: frequency,
    doseMinutes: doseMinutes,
    days: days,
    startDate: startDate,
    courseDays: courseDays,
    quantity: quantity,
    lowSupplyWarning: lowSupplyWarning,
    status: status ?? this.status,
    photoUrl: photoUrl,
    photoPath: photoPath,
    pastSchedules: pastSchedules ?? this.pastSchedules,
    pauses: pauses ?? this.pauses,
    isPending: isPending,
  );
}

/// A schedule a medicine had on the days before [until].
class ScheduleVersion {
  const ScheduleVersion({
    required this.until,
    required this.frequency,
    required this.doseMinutes,
    required this.days,
  });

  static ScheduleVersion? fromMap(Object? data) {
    if (data is! Map) return null;
    final until = CareDates.parseDay(data['until']);
    final frequency = Frequency.values.asNameMap()[data['frequency']];
    if (until == null || frequency == null) return null;
    return ScheduleVersion(
      until: until,
      frequency: frequency,
      doseMinutes: [
        for (final m in data['doseMinutes'] as List? ?? const [])
          if (m is int && m >= 0 && m < 1440) m,
      ]..sort(),
      days: [
        for (final d in data['days'] as List? ?? const [])
          if (d is int && d >= 1 && d <= 7) d,
      ]..sort(),
    );
  }

  /// First local day this version no longer applies.
  final DateTime until;
  final Frequency frequency;
  final List<int> doseMinutes;
  final List<int> days;

  Map<String, Object> toMap() => {
    'until': CareDates.dayKey(until),
    'frequency': frequency.name,
    'doseMinutes': doseMinutes,
    'days': days,
  };
}

/// Local days [from] up to, not including, [until] (open while null) on
/// which a medicine was paused or archived.
class PauseRange {
  const PauseRange({required this.from, this.until});

  static PauseRange? fromMap(Object? data) {
    if (data is! Map) return null;
    final from = CareDates.parseDay(data['from']);
    if (from == null) return null;
    return PauseRange(from: from, until: CareDates.parseDay(data['until']));
  }

  final DateTime from;
  final DateTime? until;

  bool covers(DateTime day) =>
      !day.isBefore(from) && (until == null || day.isBefore(until!));

  Map<String, Object> toMap() => {
    'from': CareDates.dayKey(from),
    if (until case final u?) 'until': CareDates.dayKey(u),
  };
}

/// One scheduled dose: a medicine at a time on a local day.
class DoseOccurrence {
  const DoseOccurrence(this.medicine, this.day, this.minutes);

  final Medicine medicine;
  final DateTime day;
  final int minutes;

  DateTime get at => CareDates.at(day, minutes);

  /// The id of this occurrence's log, so it can be logged only once.
  String get logId => DoseLog.idFor(medicine.id, day, minutes);
}

enum DoseStatus { taken, skipped }

/// One Taken, Skipped or Undo tap. Each write of a dose log carries the
/// tap's [rev], and the server only accepts a log newer than the one it
/// has, so a late sync from another device can't overwrite a newer tap.
/// A retry of the same tap (same [id] and [rev]) is accepted unchanged.
class DoseTap {
  const DoseTap(this.id, this.rev, this.at, {this.previousRev});

  /// A tap made at [now] on top of [previousRev], the log's last known
  /// revision: normally the tap time, kept above [previousRev] when this
  /// device's clock is behind the one that wrote it.
  factory DoseTap.at(DateTime now, {int? previousRev}) {
    final ms = now.millisecondsSinceEpoch;
    return DoseTap(
      _newId(),
      previousRev != null && previousRev >= ms ? previousRev + 1 : ms,
      now,
      previousRev: previousRev,
    );
  }

  /// This tap with the smallest revision the server accepts: just above
  /// [previousRev]. For a device whose clock runs fast (the server refuses
  /// revisions more than a few minutes ahead of its own time). Null when
  /// that's no smaller than [rev], so a refusal was a real conflict.
  DoseTap? get clockSafe {
    final next = (previousRev ?? 0) + 1;
    return next < rev
        ? DoseTap(_newId(), next, at, previousRev: previousRev)
        : null;
  }

  static final _random = Random.secure();

  static String _newId() =>
      [for (var i = 0; i < 20; i++) _chars[_random.nextInt(_chars.length)]]
          .join();

  static const _chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  final String id;
  final int rev;

  /// The log's revision this tap was made on, if known.
  final int? previousRev;

  /// Device time of the tap.
  final DateTime at;
}

/// Taken/Skipped record for one dose occurrence, stored at
/// `users/{uid}/profiles/{profileId}/doseLogs/{medicineId_day_minutes}`.
class DoseLog {
  const DoseLog({
    required this.medicineId,
    required this.day,
    required this.minutes,
    required this.status,
    this.loggedAt,
    this.note,
    this.medicineName,
    this.dosage,
    this.rev = 0,
    this.isUndone = false,
    this.isPending = false,
  });

  /// Stored status of a log whose Taken/Skipped was undone. It is kept
  /// (not deleted) so its revision still guards against older writes.
  static const cleared = 'cleared';

  /// Whether a stored log is an undone one.
  static bool isCleared(Map<String, dynamic> data) => data['status'] == cleared;

  factory DoseLog.fromMap(
    Map<String, dynamic> data, {
    bool isPending = false,
  }) => DoseLog(
    medicineId: data['medicineId'] as String? ?? '',
    day: CareDates.parseDay(data['day']) ?? CareDates.dateOnly(DateTime.now()),
    minutes: (data['minutes'] as num?)?.toInt() ?? 0,
    status: DoseStatus.values.asNameMap()[data['status']] ?? DoseStatus.skipped,
    loggedAt: (data['loggedAt'] as Timestamp?)?.toDate(),
    note: data['note'] as String?,
    medicineName: data['medicineName'] as String?,
    dosage: data['dosage'] as String?,
    rev: (data['rev'] as num?)?.toInt() ?? 0,
    isUndone: isCleared(data),
    isPending: isPending,
  );

  static String idFor(String medicineId, DateTime day, int minutes) =>
      '${medicineId}_${CareDates.dayKey(day)}_$minutes';

  final String medicineId;
  final DateTime day;
  final int minutes;
  final DoseStatus status;

  /// When it was recorded; null until the server time is known.
  final DateTime? loggedAt;

  /// Optional note entered with the log ("took 15 mins late").
  final String? note;

  /// The medicine's name and dosage when it was logged, so history keeps
  /// its meaning after the medicine is renamed or deleted. Missing on logs
  /// written before these were recorded.
  final String? medicineName;
  final String? dosage;

  /// [DoseTap.rev] of the last write; 0 on logs from before revisions.
  final int rev;

  /// An undone log: kept only for its [rev], never shown ([status] is
  /// meaningless).
  final bool isUndone;
  final bool isPending;

  String get id => idFor(medicineId, day, minutes);

  /// Taken by an app version without revisions, which took the dose from
  /// the supply itself.
  bool get isLegacyTaken => rev == 0 && !isUndone && status == DoseStatus.taken;

  /// Time to show: when it was logged, or the scheduled time while pending.
  DateTime get shownTime => loggedAt ?? CareDates.at(day, minutes);
}
