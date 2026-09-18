import 'package:flutter/foundation.dart';

import '../models/field_definition.dart';
import '../models/sheet.dart';
import '../services/excel_import_service.dart';
import '../services/google_auth_service.dart';
import '../services/google_sheets_service.dart';
import '../services/local_storage_service.dart';

/// Central application state using Provider.
/// Handles authentication, spreadsheet initialization,
/// and sheet (tab) management.
class AppState extends ChangeNotifier {
  final GoogleAuthService _authService;
  final GoogleSheetsService _sheetsService;
  final LocalStorageService _storageService;

  AppState({
    required GoogleAuthService authService,
    required GoogleSheetsService sheetsService,
    required LocalStorageService storageService,
  })  : _authService = authService,
        _sheetsService = sheetsService,
        _storageService = storageService;

  bool _isLoading = false;
  bool _isAuthenticated = false;
  String? _spreadsheetId;
  List<Sheet> _sheets = [];
  String? _errorMessage;

  /// Cache of sheet-name -> has at least one data entry.
  /// Used to conditionally show View Data / Download / three-dot actions.
  final Map<String, bool> _sheetHasEntries = {};

  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  String? get spreadsheetId => _spreadsheetId;
  List<Sheet> get sheets => _sheets;
  String? get errorMessage => _errorMessage;

  GoogleAuthService get authService => _authService;
  GoogleSheetsService get sheetsService => _sheetsService;
  LocalStorageService get storageService => _storageService;

  /// Attempts to restore a previous sign-in session.
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    final signedIn = await _authService.trySilentSignIn();
    if (signedIn) {
      await _loadUserData();
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Signs the user in and initializes the spreadsheet.
  Future<bool> signIn() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final success = await _authService.signIn();
    if (success) {
      await _loadUserData();
    } else {
      final details = _authService.lastError;
      _errorMessage = details == null
          ? 'Sign-in was canceled or failed. Please try again.'
          : 'Google Sign-In failed:\n$details';
    }

    _isLoading = false;
    notifyListeners();
    return success;
  }

  /// Signs the user out.
  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();
    await _authService.signOut();
    _isAuthenticated = false;
    _spreadsheetId = null;
    _sheets = [];
    _sheetHasEntries.clear();
    _isLoading = false;
    notifyListeners();
  }

  /// Loads user data: finds/creates the spreadsheet and loads sheets.
  Future<void> _loadUserData() async {
    try {
      _isAuthenticated = true;

      // Check for existing spreadsheet ID locally.
      _spreadsheetId = await _storageService.getSpreadsheetId();

      // If not saved locally, find or create it.
      if (_spreadsheetId == null) {
        _spreadsheetId = await _sheetsService.getOrCreateSpreadsheetId();
        await _storageService.saveSpreadsheetId(_spreadsheetId!);
      }

      // Load local sheets metadata first (preserves the imported flags).
      final localSheets = await _storageService.getSheets();
      final importedFlags = <String, bool>{
        for (final s in localSheets)
          if (s.isImported) s.name: true,
      };

      // Rebuild the sheet list straight from Drive so every sheet that
      // already exists in the user's spreadsheet (including ones created
      // before a sign-out, or from another device) shows up on load.
      try {
        final remoteSheets = await _sheetsService.fetchRemoteSheets(
          spreadsheetId: _spreadsheetId!,
          importedFlags: importedFlags,
        );
        _sheets = remoteSheets;
        await _storageService.saveSheets(remoteSheets);
      } catch (_) {
        // Offline or transient failure: fall back to the local cache.
        _sheets = localSheets;
      }
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Failed to initialize Google Sheets: ${e.toString()}';
      _isAuthenticated = false;
    }
  }

  /// Imports the given external worksheets (parsed from an Excel file)
  /// into the primary spreadsheet as read-only sheets.
  ///
  /// Returns the number of successfully imported sheets.
  Future<int> importSheets(List<ExternalExcelSheet> sheetsToImport) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    var imported = 0;
    try {
      final spreadsheetId = _spreadsheetId;
      if (spreadsheetId == null) {
        throw StateError('Spreadsheet not initialized.');
      }

      for (final external in sheetsToImport) {
        final sheet = await _sheetsService.importExternalSheet(
          spreadsheetId: spreadsheetId,
          desiredName: external.name,
          rows: external.rows,
        );
        await _storageService.upsertSheet(sheet);
        _sheetHasEntries[sheet.name] = true;
        imported++;
      }
      _sheets = await _storageService.getSheets();
    } catch (e) {
      _errorMessage = 'Failed to import sheets: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return imported;
    }

    _isLoading = false;
    notifyListeners();
    return imported;
  }

  /// Creates a new sheet both remotely and locally.
  Future<bool> createSheet({
    required String name,
    required List<Map<String, String>> fieldDefs,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final spreadsheetId = _spreadsheetId;
      if (spreadsheetId == null) {
        throw StateError('Spreadsheet not initialized.');
      }

      // Convert field definitions to model objects.
      final fields = fieldDefs
          .map((f) => FieldDefinition(
                label: f['label']!,
                type: _parseFieldType(f['type']!),
              ))
          .toList();

      // Create the remote tab and local sheet metadata.
      final sheet = await _sheetsService.createSheet(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        spreadsheetId: spreadsheetId,
        fields: fields,
      );
      await _storageService.upsertSheet(sheet);
      _sheets = await _storageService.getSheets();
      // A brand-new sheet has no entries yet.
      _sheetHasEntries[sheet.name] = false;
    } catch (e) {
      _errorMessage = 'Failed to create sheet: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    _isLoading = false;
    notifyListeners();
    return true;
  }

  /// Returns whether the given sheet currently has at least one entry.
  ///
  /// Uses a local cache when available, otherwise queries Google Sheets.
  /// When [refresh] is true the remote state is always queried.
  Future<bool> sheetHasEntries(
    Sheet sheet, {
    bool refresh = false,
  }) async {
    final key = sheet.name;
    if (!refresh && _sheetHasEntries.containsKey(key)) {
      return _sheetHasEntries[key]!;
    }
    try {
      final hasEntries = await _sheetsService.sheetHasEntries(
        spreadsheetId: sheet.spreadsheetId,
        sheetName: sheet.name,
      );
      _sheetHasEntries[key] = hasEntries;
      return hasEntries;
    } catch (_) {
      return _sheetHasEntries[key] ?? false;
    }
  }

  /// Synchronously reads the cached entry state (defaults to false).
  bool cachedSheetHasEntries(Sheet sheet) =>
      _sheetHasEntries[sheet.name] ?? false;

  /// Refreshes the cached entry state for every known sheet.
  Future<void> refreshSheetEntryStates() async {
    for (final sheet in _sheets) {
      await sheetHasEntries(sheet, refresh: true);
    }
    notifyListeners();
  }

  /// Marks a sheet as having entries (used right after adding an entry).
  void markSheetHasEntries(Sheet sheet) {
    _sheetHasEntries[sheet.name] = true;
    notifyListeners();
  }

  /// Deletes a sheet both remotely (Google Sheets tab) and locally.
  ///
  /// Returns true when the sheet was deleted.
  Future<bool> deleteSheet(Sheet sheet) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Delete the remote tab first. Missing tabs are treated as success.
      await _sheetsService.deleteSheetTab(
        spreadsheetId: sheet.spreadsheetId,
        sheetName: sheet.name,
      );
      await _storageService.deleteSheet(sheet.id);
      _sheets = await _storageService.getSheets();
      _sheetHasEntries.remove(sheet.name);
    } catch (e) {
      _errorMessage = 'Failed to delete sheet: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    _isLoading = false;
    notifyListeners();
    return true;
  }

  /// Exports a sheet via the OS share sheet (CSV that opens in Excel).
  /// Returns true when the share sheet was opened.
  Future<bool> downloadSheet(Sheet sheet) async {
    _errorMessage = null;
    notifyListeners();
    try {
      final file = await _sheetsService.exportSheetAsCsv(
        spreadsheetId: sheet.spreadsheetId,
        sheetName: sheet.name,
      );
      if (file == null) {
        _errorMessage = 'No data available to download for "${sheet.name}".';
        notifyListeners();
        return false;
      }
      return true;
    } catch (e) {
      _errorMessage = 'Failed to download sheet: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  /// Clears any displayed error message.
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Parses a field type string to a [FieldType] enum.
  FieldType _parseFieldType(String type) {
    switch (type) {
      case 'date':
        return FieldType.date;
      case 'number':
        return FieldType.number;
      default:
        return FieldType.text;
    }
  }
}