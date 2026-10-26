import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'care_dates.dart';

/// One exported history line.
class ExportRow {
  const ExportRow({
    required this.day,
    required this.scheduledMinutes,
    required this.medicine,
    required this.dosage,
    required this.status,
    required this.loggedAt,
    required this.note,
  });

  final DateTime day;
  final int scheduledMinutes;
  final String medicine;
  final String dosage;
  final String status;
  final DateTime? loggedAt;
  final String note;

  List<String> get cells => [
    CareDates.dayKey(day),
    CareDates.clock(scheduledMinutes),
    medicine,
    dosage,
    status,
    loggedAt == null ? 'Waiting to sync' : CareDates.clockOf(loggedAt!),
    note,
  ];
}

const _headers = [
  'Date',
  'Scheduled',
  'Medicine',
  'Dosage',
  'Status',
  'Logged at',
  'Note',
];

/// RFC 4180 CSV. Cells that a spreadsheet would run as a formula
/// (=, +, -, @) are prefixed with a quote so they stay plain text.
Uint8List historyCsv(List<ExportRow> rows) {
  String cell(String v) {
    final safe = RegExp(r'^[=+\-@\t\r]').hasMatch(v) ? "'$v" : v;
    return '"${safe.replaceAll('"', '""')}"';
  }

  final lines = [
    _headers.map(cell).join(','),
    for (final r in rows) r.cells.map(cell).join(','),
  ];
  return Uint8List.fromList(utf8.encode('${lines.join('\r\n')}\r\n'));
}

/// A one-table A4 report.
Future<Uint8List> historyPdf({
  required String profileName,
  required String rangeLabel,
  required List<ExportRow> rows,
}) {
  final doc = pw.Document(title: 'DoseMate medication log');
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => [
        pw.Text(
          'Medication log',
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text('$profileName  •  $rangeLabel'),
        pw.SizedBox(height: 16),
        if (rows.isEmpty)
          pw.Text('No doses were recorded in this period.')
        else
          pw.TableHelper.fromTextArray(
            headers: _headers,
            data: [for (final r in rows) r.cells],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFE7EEFF),
            ),
          ),
        pw.SizedBox(height: 16),
        pw.Text(
          'Records reflect entries logged by the user or a caregiver.',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ],
    ),
  );
  return doc.save();
}
