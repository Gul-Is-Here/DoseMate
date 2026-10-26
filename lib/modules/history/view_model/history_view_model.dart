import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/care_dates.dart';
import '../../../core/utils/history_export.dart';
import '../../../data/models/medicine.dart';
import '../../../data/services/care_service.dart';
import '../../../data/services/history_service.dart';
import '../../../widgets/app_snackbar.dart';

enum ExportFormat { pdf, csv }

/// Screen layer over the permanent [HistoryService]: labels for the rows
/// and summary, filter choices and the export flow.
class HistoryViewModel extends GetxController {
  final history = Get.find<HistoryService>();
  final care = Get.find<CareService>();

  /// Set while an export is being generated, to ignore repeated taps.
  final exporting = false.obs;

  @override
  void onInit() {
    super.onInit();
    history.activate();
  }

  DateTime get today => care.today.value;

  String get profileName => care.profiles.activeProfile?.fullName ?? '';

  // Summary.

  String get summaryTitle {
    final n = history.summary.recorded;
    final period = switch (history.range.value) {
      HistoryRange.daily => 'Today',
      HistoryRange.weekly => 'This Week',
      HistoryRange.monthly => 'Last 30 Days',
    };
    return '$period: $n scheduled ${n == 1 ? 'dose' : 'doses'} recorded';
  }

  /// "Oct 18 – Oct 24", or one day.
  String get rangeLabel {
    final (from, to) = history.bounds;
    final last = CareDates.addDays(to, -1);
    return from == last
        ? CareDates.short(from)
        : '${CareDates.short(from)} – ${CareDates.short(last)}';
  }

  int get takenPercent {
    final s = history.summary;
    return s.recorded == 0 ? 0 : (s.taken * 100 / s.recorded).round();
  }

  // Rows. The log's own snapshot comes first, so renamed or deleted
  // medicines keep the name they had when the dose was recorded.

  String nameOf(DoseLog l) =>
      _nonEmpty(l.medicineName) ??
      _nonEmpty(care.medicineById(l.medicineId)?.name) ??
      'Medicine no longer available';

  String dosageOf(DoseLog l) =>
      _nonEmpty(l.dosage) ??
      _nonEmpty(care.medicineById(l.medicineId)?.dosage) ??
      '';

  static String? _nonEmpty(String? s) =>
      s == null || s.trim().isEmpty ? null : s;

  /// "Marked Taken at 9:08 AM", "Skipped at 8:05 PM".
  String statusLine(DoseLog l) {
    final what = l.status == DoseStatus.taken ? 'Marked Taken' : 'Skipped';
    final at = l.loggedAt;
    return at == null
        ? '$what • waiting to sync'
        : '$what at ${CareDates.clockOf(at)}';
  }

  /// "Thursday, Oct 24".
  String dayTitle(DateTime day) => CareDates.long(day);

  /// "Today", "Yesterday" or nothing.
  String? daySuffix(DateTime day) =>
      switch (CareDates.daysBetween(day, today)) {
        0 => 'Today',
        1 => 'Yesterday',
        _ => null,
      };

  // Filters.

  String get medicineLabel {
    final id = history.medicineId.value;
    if (id == null) return 'All Medicines';
    return care.medicineById(id)?.name ?? 'Medicine';
  }

  String get statusLabel => switch (history.statusFilter.value) {
    null => 'Status: All',
    DoseStatus.taken => 'Status: Taken',
    DoseStatus.skipped => 'Status: Skipped',
  };

  List<Medicine> get medicineChoices => care.medicines;

  void toggleSort() => history.newestFirst.toggle();

  // Export.

  List<ExportRow> _rows() => [
    for (final l in history.exportLogs())
      ExportRow(
        day: l.day,
        scheduledMinutes: l.minutes,
        medicine: nameOf(l),
        dosage: dosageOf(l),
        status: l.status == DoseStatus.taken ? 'Taken' : 'Skipped',
        loggedAt: l.loggedAt,
        note: l.note ?? '',
      ),
  ];

  String get _fileBase =>
      'dosemate-log-${CareDates.dayKey(history.bounds.$1)}'
      '-to-${CareDates.dayKey(today)}';

  /// Runs after the user authorized it in the confirmation dialog. Uses
  /// the profile's already-loaded 30-day logs, so it reads nothing more.
  Future<void> export(ExportFormat format) async {
    if (exporting.value) return;
    final rows = _rows();
    if (rows.isEmpty) {
      showSnack('Nothing to export', 'No doses were recorded in this period.');
      return;
    }
    exporting.value = true;
    try {
      switch (format) {
        case ExportFormat.pdf:
          final bytes = await historyPdf(
            profileName: profileName,
            rangeLabel: rangeLabel,
            rows: rows,
          );
          await Printing.layoutPdf(
            name: '$_fileBase.pdf',
            onLayout: (_) async => bytes,
          );
        case ExportFormat.csv:
          await SharePlus.instance.share(
            ShareParams(
              files: [
                XFile.fromData(
                  historyCsv(rows),
                  mimeType: 'text/csv',
                  name: '$_fileBase.csv',
                ),
              ],
              fileNameOverrides: ['$_fileBase.csv'],
            ),
          );
      }
      Get.rawSnackbar(message: 'Summary report generated successfully');
    } on Exception catch (e) {
      if (kDebugMode) debugPrint('Export failed: ${e.runtimeType}');
      showSnack(
        "Couldn't create the report",
        'Please try again. Nothing was shared.',
      );
    } finally {
      exporting.value = false;
    }
  }
}
