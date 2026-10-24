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
    this.isPending = false,
  });

  static const maxCourseDays = 3650;

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

  /// Saved on this device but not yet confirmed by the server.
  final bool isPending;

  /// Last local day of the course.
  DateTime get endDate => CareDates.addDays(startDate, courseDays - 1);

  bool get isActive => status == MedicineStatus.active;

  /// Scheduled doses per scheduled day (0 for as needed).
  int get dosesPerDay => frequency.isScheduled ? doseMinutes.length : 0;

  bool isScheduledOn(DateTime day) {
    if (!isActive || !frequency.isScheduled) return false;
    final d = CareDates.dateOnly(day);
    if (d.isBefore(startDate) || d.isAfter(endDate)) return false;
    return frequency != Frequency.specificDays || days.contains(d.weekday);
  }

  List<DoseOccurrence> occurrencesOn(DateTime day) => isScheduledOn(day)
      ? [
          for (final m in doseMinutes)
            DoseOccurrence(this, CareDates.dateOnly(day), m),
        ]
      : const [];

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
    isPending: isPending,
  );
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

/// Taken/Skipped record for one dose occurrence, stored at
/// `users/{uid}/profiles/{profileId}/doseLogs/{medicineId_day_minutes}`.
class DoseLog {
  const DoseLog({
    required this.medicineId,
    required this.day,
    required this.minutes,
    required this.status,
    this.loggedAt,
    this.isPending = false,
  });

  factory DoseLog.fromMap(
    Map<String, dynamic> data, {
    bool isPending = false,
  }) => DoseLog(
    medicineId: data['medicineId'] as String? ?? '',
    day: CareDates.parseDay(data['day']) ?? CareDates.dateOnly(DateTime.now()),
    minutes: (data['minutes'] as num?)?.toInt() ?? 0,
    status: DoseStatus.values.asNameMap()[data['status']] ?? DoseStatus.taken,
    loggedAt: (data['loggedAt'] as Timestamp?)?.toDate(),
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
  final bool isPending;

  String get id => idFor(medicineId, day, minutes);

  /// Time to show: when it was logged, or the scheduled time while pending.
  DateTime get shownTime => loggedAt ?? CareDates.at(day, minutes);
}
