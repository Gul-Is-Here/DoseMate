import '../../data/models/medicine.dart';
import 'care_dates.dart';

/// What happened to one scheduled dose, as every screen shows it.
enum DoseState { taken, skipped, overdue, due, missed, scheduled }

/// The one rule for a dose's state, shared by Home, Calendar, Details and
/// History.
///
/// Times are local wall-clock times: a dose at 8:00 is due at 8:00 in the
/// device's current time zone, so after travelling it follows the new
/// local day. Overdue and Missed are worked out, never stored, so logging a
/// dose late still counts, and a snooze or a dismissed notification never
/// changes the state.
abstract class DoseStates {
  /// How long after its time a dose counts as Due rather than Overdue.
  static const grace = Duration(minutes: 15);

  static DoseState of(DoseOccurrence o, DoseLog? log, DateTime now) {
    switch (log?.status) {
      case DoseStatus.taken:
        return DoseState.taken;
      case DoseStatus.skipped:
        return DoseState.skipped;
      case null:
    }
    final today = CareDates.dateOnly(now);
    // Missed once its local day has ended.
    if (o.day.isBefore(today)) return DoseState.missed;
    if (o.day.isAfter(today)) return DoseState.scheduled;
    return isOverdue(o, now) ? DoseState.overdue : DoseState.due;
  }

  /// Unlogged doses only: whether [o] is past its grace period.
  static bool isOverdue(DoseOccurrence o, DateTime now) =>
      o.at.isBefore(now.subtract(grace));
}
