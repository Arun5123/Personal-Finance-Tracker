import 'field_definition.dart';

/// Represents a sheet (tab) inside the primary spreadsheet.
/// Stores the sheet title, list of field definitions, and its spreadsheet ID
/// so we can create tabs across multiple spreadsheets if needed.
class Sheet {
  final String id;
  final String name;
  final String spreadsheetId;
  final List<FieldDefinition> fields;
  final DateTime createdAt;

  /// True when this sheet was imported from an external Excel file.
  /// Imported sheets are read-only: entries can be viewed but not added.
  final bool isImported;

  const Sheet({
    required this.id,
    required this.name,
    required this.spreadsheetId,
    required this.fields,
    required this.createdAt,
    this.isImported = false,
  });

  /// Serialize to a JSON map for local storage.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'spreadsheetId': spreadsheetId,
        'fields': fields.map((f) => f.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'isImported': isImported,
      };

  /// Deserialize from a JSON map.
  factory Sheet.fromJson(Map<String, dynamic> json) {
    return Sheet(
      id: json['id'] as String,
      name: json['name'] as String,
      spreadsheetId: json['spreadsheetId'] as String,
      fields: (json['fields'] as List)
          .map((f) => FieldDefinition.fromJson(f as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      isImported: (json['isImported'] as bool?) ?? false,
    );
  }

  /// Returns a copy of this sheet with the given fields replaced.
  Sheet copyWith({
    String? id,
    String? name,
    String? spreadsheetId,
    List<FieldDefinition>? fields,
    DateTime? createdAt,
    bool? isImported,
  }) {
    return Sheet(
      id: id ?? this.id,
      name: name ?? this.name,
      spreadsheetId: spreadsheetId ?? this.spreadsheetId,
      fields: fields ?? this.fields,
      createdAt: createdAt ?? this.createdAt,
      isImported: isImported ?? this.isImported,
    );
  }
}
