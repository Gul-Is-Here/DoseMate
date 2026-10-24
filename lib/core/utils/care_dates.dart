/// Local-calendar helpers for schedules. Days are stored as `yyyy-MM-dd`
/// strings so a dose belongs to the user's local day wherever the record is
/// read, and times of day as minutes after local midnight.
abstract class CareDates {
  static const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', //
    'Friday', 'Saturday', 'Sunday',
  ];

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Calendar arithmetic, so DST changes never shift the day.
  static DateTime addDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);

  static int daysBetween(DateTime from, DateTime to) => DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime? parseDay(Object? key) {
    if (key is! String) return null;
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final [y, m, d] = parts.map(int.tryParse).toList();
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  static DateTime at(DateTime day, int minutes) =>
      DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);

  /// "8:00 PM".
  static String clock(int minutes) {
    final h = minutes ~/ 60, m = minutes % 60;
    final hour = h % 12 == 0 ? 12 : h % 12;
    return '$hour:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
  }

  static String clockOf(DateTime t) => clock(t.hour * 60 + t.minute);

  /// "Oct 24".
  static String short(DateTime d) => '${months[d.month - 1]} ${d.day}';

  /// "Wednesday, Oct 24".
  static String long(DateTime d) => '${weekdays[d.weekday - 1]}, ${short(d)}';

  /// "Today", "Tomorrow", "In 3 days" or "Yesterday" relative to [today].
  static String relative(DateTime day, DateTime today) {
    final n = daysBetween(today, day);
    return switch (n) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      > 1 => 'In $n days',
      _ => '${-n} days ago',
    };
  }

  /// "Morning", "Afternoon", "Evening" or "Night" for a time of day.
  static String partOfDay(int minutes) {
    final h = minutes ~/ 60;
    if (h >= 5 && h < 12) return 'Morning';
    if (h >= 12 && h < 17) return 'Afternoon';
    if (h >= 17 && h < 21) return 'Evening';
    return 'Night';
  }
}
