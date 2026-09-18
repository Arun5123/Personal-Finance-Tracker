import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/field_definition.dart';
import '../models/sheet.dart';
import 'google_auth_service.dart';

/// Service responsible for all Google Sheets and Google Drive operations:
/// - Finding/creating the primary spreadsheet.
/// - Creating new tabs (sheets) with custom field headers.
/// - Appending data rows.
/// - Fetching existing data for viewing.
/// - Syncing sheet metadata from Drive (restore after sign-in).
/// - Importing worksheets from external Excel files.
class GoogleSheetsService {
  final GoogleAuthService _authService;

  GoogleSheetsService(this._authService);

  /// Finds a spreadsheet in the user's Drive named "Personal_Finance_Tracker".
  /// Returns the file ID if found, or null if not found.
  Future<String?> _findSpreadsheetId() async {
    final driveApi = await _authService.driveApi;
    final response = await driveApi.files.list(
      q: "name='Personal_Finance_Tracker' and mimeType='application/vnd.google-apps.spreadsheet' and trashed=false",
      spaces: 'drive',
      $fields: 'files(id, name)',
    );
    final files = response.files;
    if (files == null || files.isEmpty) {
      return null;
    }
    return files.first.id;
  }

  /// Creates a new spreadsheet named "Personal_Finance_Tracker".
  /// Returns the newly created spreadsheet ID.
  Future<String> _createSpreadsheet() async {
    final driveApi = await _authService.driveApi;
    final file = drive.File()
      ..name = 'Personal_Finance_Tracker'
      ..mimeType = 'application/vnd.google-apps.spreadsheet';
    final created = await driveApi.files.create(file);
    return created.id!;
  }

  /// Ensures the primary spreadsheet exists.
  /// Searches for "Personal_Finance_Tracker"; creates it if missing.
  /// Returns the spreadsheet ID.
  Future<String> getOrCreateSpreadsheetId() async {
    final existingId = await _findSpreadsheetId();
    if (existingId != null) {
      return existingId;
    }
    return _createSpreadsheet();
  }

  /// Creates a new tab (sheet) inside the given spreadsheet.
  /// The field labels are written to Row 1 as headers.
  /// Returns the new sheet's title (tab name).
  Future<String> createSheetTab({
    required String spreadsheetId,
    required String sheetName,
    required List<FieldDefinition> fields,
  }) async {
    final sheetsApi = await _authService.sheetsApi;

    // Add the new sheet to the spreadsheet.
    final addSheetRequest = sheets.Request(
      addSheet: sheets.AddSheetRequest(
        properties: sheets.SheetProperties(title: sheetName),
      ),
    );
    await sheetsApi.spreadsheets.batchUpdate(
      sheets.BatchUpdateSpreadsheetRequest(
        requests: [addSheetRequest],
      ),
      spreadsheetId,
    );

    // Write headers to Row 1.
    // Note: Sheet names with spaces must be quoted in A1 notation.
    final headers = fields.map((f) => f.label).toList();
    await sheetsApi.spreadsheets.values.update(
      sheets.ValueRange(
        values: [headers],
      ),
      spreadsheetId,
      "'$sheetName'!A1",
      valueInputOption: 'RAW',
    );

    // Format the header row (bold, background color).
    // We need to find the sheetId by fetching spreadsheet metadata.
    try {
      final spreadsheetInfo = await sheetsApi.spreadsheets.get(spreadsheetId);
      final sheetId = spreadsheetInfo.sheets
          ?.firstWhere((s) => s.properties?.title == sheetName)
          .properties
          ?.sheetId;

      if (sheetId != null) {
        final formatRequest = sheets.Request(
          repeatCell: sheets.RepeatCellRequest(
            range: sheets.GridRange(
              sheetId: sheetId,
              startRowIndex: 0,
              endRowIndex: 1,
            ),
            cell: sheets.CellData(
              userEnteredFormat: sheets.CellFormat(
                textFormat: sheets.TextFormat(
                  bold: true,
                ),
                backgroundColor: sheets.Color(
                  red: 0.9,
                  green: 0.9,
                  blue: 0.9,
                ),
              ),
            ),
            fields: 'userEnteredFormat(textFormat,backgroundColor)',
          ),
        );
        await sheetsApi.spreadsheets.batchUpdate(
          sheets.BatchUpdateSpreadsheetRequest(requests: [formatRequest]),
          spreadsheetId,
        );
      }
    } catch (_) {
      // Header formatting is non-critical; ignore errors.
    }

    return sheetName;
  }

  /// Appends a data row to the specified tab in the spreadsheet.
  Future<void> appendRow({
    required String spreadsheetId,
    required String sheetName,
    required List<String> rowValues,
  }) async {
    final sheetsApi = await _authService.sheetsApi;
    await sheetsApi.spreadsheets.values.append(
      sheets.ValueRange(
        values: [rowValues],
      ),
      spreadsheetId,
      "'$sheetName'!A1",
      valueInputOption: 'USER_ENTERED',
    );
  }

  /// Fetches all rows from the specified tab.
  /// Returns a list of rows, where each row is a list of cell values.
  Future<List<List<String>>> getSheetData({
    required String spreadsheetId,
    required String sheetName,
  }) async {
    final sheetsApi = await _authService.sheetsApi;
    final response = await sheetsApi.spreadsheets.values.get(
      spreadsheetId,
      "'$sheetName'!A1:Z1000",
    );
    final values = response.values;
    if (values == null || values.isEmpty) {
      return [];
    }
    return values
        .map((row) => row.map((cell) => cell.toString()).toList())
        .toList();
  }

  /// Convenience method to create a [Sheet] locally and remotely.
  Future<Sheet> createSheet({
    required String id,
    required String name,
    required String spreadsheetId,
    required List<FieldDefinition> fields,
  }) async {
    final tabName = await createSheetTab(
      spreadsheetId: spreadsheetId,
      sheetName: name,
      fields: fields,
    );
    return Sheet(
      id: id,
      name: tabName,
      spreadsheetId: spreadsheetId,
      fields: fields,
      createdAt: DateTime.now(),
    );
  }

  /// Sanitizes a name so it is valid as a Google Sheets tab name.
  static String sanitizeSheetName(String name) {
    var clean = name.replaceAll(RegExp(r'[\[\]*/\\?:]'), '_').trim();
    if (clean.length > 100) clean = clean.substring(0, 100);
    return clean.isEmpty ? 'Imported Sheet' : clean;
  }

  /// Best-effort inference of a field type from a header label.
  static FieldType inferFieldType(String header) {
    final lower = header.toLowerCase();
    if (lower.contains('date') ||
        lower.contains('month') ||
        lower.contains('day')) {
      return FieldType.date;
    }
    const numericHints = [
      'amount', 'rent', 'total', 'price', 'fee', 'balance',
      'paid', 'due', 'cost', 'rate', 'count', 'qty', 'quantity',
    ];
    if (numericHints.any(lower.contains)) return FieldType.number;
    return FieldType.text;
  }

  /// Fetches every tab of the given spreadsheet together with its
  /// header row, so the sheet list can be rebuilt straight from Drive.
  ///
  /// This is what makes previously created sheets re-appear after
  /// sign-out / sign-in (or on a fresh install) without any local cache.
  /// Tabs with an empty header row are skipped (e.g. the untouched
  /// default "Sheet1"). [importedFlags] preserves the read-only
  /// imported flag for tabs that were previously imported.
  Future<List<Sheet>> fetchRemoteSheets({
    required String spreadsheetId,
    Map<String, bool> importedFlags = const {},
  }) async {
    final sheetsApi = await _authService.sheetsApi;
    final info = await sheetsApi.spreadsheets.get(spreadsheetId);

    final result = <Sheet>[];
    for (final tab in info.sheets ?? const <sheets.Sheet>[]) {
      final title = tab.properties?.title;
      if (title == null || title.isEmpty) continue;

      List<String> headers;
      try {
        final response = await sheetsApi.spreadsheets.values
            .get(spreadsheetId, "'$title'!A1:Z1");
        final values = response.values;
        headers = (values == null || values.isEmpty)
            ? const <String>[]
            : values.first
                .map((c) => c.toString())
                .where((c) => c.trim().isNotEmpty)
                .toList();
      } catch (_) {
        // Treat unreadable tabs as empty and skip them.
        continue;
      }
      if (headers.isEmpty) continue;

      result.add(Sheet(
        id: tab.properties?.sheetId?.toString() ?? title,
        name: title,
        spreadsheetId: spreadsheetId,
        fields: headers
            .map((h) => FieldDefinition(label: h, type: inferFieldType(h)))
            .toList(),
        createdAt: DateTime.now(),
        isImported: importedFlags[title] ?? false,
      ));
    }
    return result;
  }

  /// Imports the rows of an external Excel worksheet into a new tab of
  /// the primary spreadsheet and returns the resulting read-only [Sheet].
  Future<Sheet> importExternalSheet({
    required String spreadsheetId,
    required String desiredName,
    required List<List<String>> rows,
  }) async {
    final sheetsApi = await _authService.sheetsApi;

    // Pick a tab name that does not collide with existing tabs.
    final existingInfo = await sheetsApi.spreadsheets.get(spreadsheetId);
    final existingTitles = (existingInfo.sheets ?? const <sheets.Sheet>[])
        .map((s) => s.properties?.title ?? '')
        .toSet();

    final base = sanitizeSheetName(desiredName);
    var tabName = base;
    var counter = 2;
    while (existingTitles.contains(tabName)) {
      final suffix = ' ($counter)';
      final maxBaseLength = 100 - suffix.length;
      tabName = base.length > maxBaseLength
          ? base.substring(0, maxBaseLength) + suffix
          : base + suffix;
      counter++;
    }

    // Create the new tab and capture its generated sheetId.
    final batchResponse = await sheetsApi.spreadsheets.batchUpdate(
      sheets.BatchUpdateSpreadsheetRequest(
        requests: [
          sheets.Request(
            addSheet: sheets.AddSheetRequest(
              properties: sheets.SheetProperties(title: tabName),
            ),
          ),
        ],
      ),
      spreadsheetId,
    );
    final newSheetId =
        batchResponse.replies?.first.addSheet?.properties?.sheetId;

    // Write the header + data rows.
    if (rows.isNotEmpty) {
      await sheetsApi.spreadsheets.values.update(
        sheets.ValueRange(
          values: rows
              .map((row) => row.map((c) => c.toString()).toList())
              .toList(),
        ),
        spreadsheetId,
        "'$tabName'!A1",
        valueInputOption: 'RAW',
      );

      // Format the header row (bold, light gray) to match created sheets.
      if (newSheetId != null) {
        try {
          await sheetsApi.spreadsheets.batchUpdate(
            sheets.BatchUpdateSpreadsheetRequest(
              requests: [
                sheets.Request(
                  repeatCell: sheets.RepeatCellRequest(
                    range: sheets.GridRange(
                      sheetId: newSheetId,
                      startRowIndex: 0,
                      endRowIndex: 1,
                    ),
                    cell: sheets.CellData(
                      userEnteredFormat: sheets.CellFormat(
                        textFormat: sheets.TextFormat(bold: true),
                        backgroundColor: sheets.Color(
                          red: 0.9,
                          green: 0.9,
                          blue: 0.9,
                        ),
                      ),
                    ),
                    fields: 'userEnteredFormat(textFormat,backgroundColor)',
                  ),
                ),
              ],
            ),
            spreadsheetId,
          );
        } catch (_) {
          // Header formatting is non-critical; ignore errors.
        }
      }
    }

    final headers = rows.isEmpty
        ? const <String>[]
        : rows.first.map((c) => c.toString()).toList();

    return Sheet(
      id: newSheetId?.toString() ?? tabName,
      name: tabName,
      spreadsheetId: spreadsheetId,
      fields: headers
          .map((h) => FieldDefinition(label: h, type: inferFieldType(h)))
          .toList(),
      createdAt: DateTime.now(),
      isImported: true,
    );
  }

  /// Deletes a sheet tab from the remote spreadsheet, if it exists.
  ///
  /// This looks up the tab (sheetId) by its title and issues a
  /// `deleteSheet` batchUpdate request. If the tab is already missing
  /// this is treated as a success so local state can still be cleaned up.
  Future<void> deleteSheetTab({
    required String spreadsheetId,
    required String sheetName,
  }) async {
    final sheetsApi = await _authService.sheetsApi;
    final spreadsheetInfo = await sheetsApi.spreadsheets.get(spreadsheetId);
    int? sheetId;
    for (final sheet in spreadsheetInfo.sheets ?? const <sheets.Sheet>[]) {
      if (sheet.properties?.title == sheetName) {
        sheetId = sheet.properties?.sheetId;
        break;
      }
    }
    if (sheetId == null) return;

    await sheetsApi.spreadsheets.batchUpdate(
      sheets.BatchUpdateSpreadsheetRequest(
        requests: [
          sheets.Request(
            deleteSheet: sheets.DeleteSheetRequest(
              sheetId: sheetId,
            ),
          ),
        ],
      ),
      spreadsheetId,
    );
  }

  /// Returns true when the given sheet tab has at least one data row
  /// beyond the header row.
  Future<bool> sheetHasEntries({
    required String spreadsheetId,
    required String sheetName,
  }) async {
    final data = await getSheetData(
      spreadsheetId: spreadsheetId,
      sheetName: sheetName,
    );
    if (data.isEmpty) return false;
    // Row 1 is the header. Anything after that counts as an entry.
    // Ignore completely blank rows.
    for (var i = 1; i < data.length; i++) {
      final row = data[i];
      if (row.any((cell) => cell.trim().isNotEmpty)) return true;
    }
    return false;
  }

  /// Exports the sheet tab to a local CSV file and opens the OS share
  /// sheet so the user can save / send it (acts as "Download Excel" —
  /// CSV opens directly in Excel / Google Sheets).
  ///
  /// Returns the created file, or null when there is nothing to export.
  Future<File?> exportSheetAsCsv({
    required String spreadsheetId,
    required String sheetName,
  }) async {
    final data = await getSheetData(
      spreadsheetId: spreadsheetId,
      sheetName: sheetName,
    );
    if (data.isEmpty) return null;

    final buffer = StringBuffer();
    for (final row in data) {
      buffer.writeln(row.map(_escapeCsvCell).join(','));
    }

    final directory = await getTemporaryDirectory();
    final safeName = sheetName
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    // The downloaded file must be named exactly after the sheet —
    // no prefixes or timestamps.
    final fileName = '${safeName.isEmpty ? 'sheet' : safeName}.csv';
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(buffer.toString());

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv', name: fileName)],
      text: 'Export of sheet "$sheetName"',
      subject: 'Download sheet: $sheetName',
    );
    return file;
  }

  String _escapeCsvCell(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}