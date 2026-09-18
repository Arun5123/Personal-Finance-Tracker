import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/sheet.dart';

/// Service for persisting app metadata locally using SharedPreferences.
/// Stores the spreadsheet ID and the list of sheets (tabs).
class LocalStorageService {
  static const String _spreadsheetIdKey = 'spreadsheet_id';
  static const String _sheetsKey = 'sheets';
  // Old key kept for one-time migration of existing installs.
  static const String _legacySheetsKey = 'sheet_categories';

  /// Saves the primary spreadsheet ID locally.
  Future<void> saveSpreadsheetId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_spreadsheetIdKey, id);
  }

  /// Retrieves the saved spreadsheet ID (null if not set).
  Future<String?> getSpreadsheetId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_spreadsheetIdKey);
  }

  /// Saves the list of sheets locally.
  Future<void> saveSheets(List<Sheet> sheets) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = sheets.map((c) => c.toJson()).toList();
    await prefs.setString(_sheetsKey, jsonEncode(jsonList));
  }

  /// Retrieves the saved list of sheets (empty list if none).
  Future<List<Sheet>> getSheets() async {
    final prefs = await SharedPreferences.getInstance();
    var raw = prefs.getString(_sheetsKey);
    // One-time migration from the old key name.
    if ((raw == null || raw.isEmpty) &&
        prefs.containsKey(_legacySheetsKey)) {
      raw = prefs.getString(_legacySheetsKey);
      if (raw != null && raw.isNotEmpty) {
        await prefs.setString(_sheetsKey, raw);
        await prefs.remove(_legacySheetsKey);
      }
    }
    if (raw == null || raw.isEmpty) {
      return [];
    }
    final jsonList = jsonDecode(raw) as List;
    return jsonList
        .map((json) => Sheet.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Adds or updates a single sheet in the local list.
  Future<void> upsertSheet(Sheet sheet) async {
    final sheets = await getSheets();
    final existingIndex = sheets.indexWhere((c) => c.id == sheet.id);
    if (existingIndex >= 0) {
      sheets[existingIndex] = sheet;
    } else {
      sheets.add(sheet);
    }
    await saveSheets(sheets);
  }

  /// Removes a sheet from the local list by its ID.
  Future<void> deleteSheet(String sheetId) async {
    final sheets = await getSheets();
    sheets.removeWhere((c) => c.id == sheetId);
    await saveSheets(sheets);
  }
}