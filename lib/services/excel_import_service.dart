import 'dart:io';

import 'package:excel/excel.dart';

/// A single worksheet parsed from an external Excel workbook.
class ExternalExcelSheet {
  final String name;
  final List<List<String>> rows;

  const ExternalExcelSheet({required this.name, required this.rows});

  /// Number of data rows (excluding the header row).
  int get dataRowCount => rows.isEmpty ? 0 : rows.length - 1;

  /// Header labels (first non-empty row).
  List<String> get headers =>
      rows.isEmpty ? const [] : rows.first.map((c) => c.toString()).toList();
}

/// Service that parses external Excel (.xlsx) workbooks so their
/// worksheets can be imported into the user's Google Sheets spreadsheet.
class ExcelImportService {
  /// Parses the workbook at [filePath] and returns every non-empty
  /// worksheet it contains.
  ///
  /// The first row of each worksheet is treated as the header row and
  /// every row below it as a data row. Completely empty rows at the
  /// start/end of a worksheet are trimmed.
  Future<List<ExternalExcelSheet>> parseWorkbook(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final workbook = Excel.decodeBytes(bytes);

    final result = <ExternalExcelSheet>[];
    for (final entry in workbook.tables.entries) {
      final table = entry.value;
      final rows = <List<String>>[];
      for (final row in table.rows) {
        rows.add(
          row.map((cell) => _cellToString(cell?.value)).toList(growable: false),
        );
      }

      // Trim fully-empty leading/trailing rows.
      while (rows.isNotEmpty && rows.first.every((c) => c.trim().isEmpty)) {
        rows.removeAt(0);
      }
      while (rows.isNotEmpty && rows.last.every((c) => c.trim().isEmpty)) {
        rows.removeLast();
      }

      if (rows.isEmpty) continue;

      result.add(ExternalExcelSheet(name: entry.key, rows: rows));
    }
    return result;
  }

  /// Converts a raw cell value to a stable string representation.
  ///
  /// The excel package (4.x) wraps cell values in sealed [CellValue]
  /// classes, so each subtype is unwrapped explicitly.
  String _cellToString(Object? value) {
    if (value == null) return '';
    if (value is TextCellValue) return value.value.toString();
    if (value is IntCellValue) return value.value.toString();
    if (value is DoubleCellValue) {
      final d = value.value;
      return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
    }
    if (value is DateCellValue) return value.asDateTimeLocal().toIso8601String();
    if (value is DateTimeCellValue) {
      return value.asDateTimeLocal().toIso8601String();
    }
    if (value is TimeCellValue) return value.asDuration().toString();
    if (value is BoolCellValue) return value.value ? 'TRUE' : 'FALSE';
    if (value is FormulaCellValue) return value.formula;
    return value.toString();
  }
}
