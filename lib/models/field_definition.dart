/// Enum representing the supported field types for dynamic form generation.
enum FieldType {
  date,
  number,
  text;

  /// Parse a [FieldType] from a string (used for JSON serialization).
  static FieldType fromString(String value) {
    return FieldType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => FieldType.text,
    );
  }
}

/// Represents a single dynamic field definition for a sheet.
/// This includes the label and the type used for form generation & validation.
class FieldDefinition {
  final String label;
  final FieldType type;

  const FieldDefinition({
    required this.label,
    required this.type,
  });

  /// Serialize to a JSON map for local storage.
  Map<String, dynamic> toJson() => {
        'label': label,
        'type': type.name,
      };

  /// Deserialize from a JSON map.
  factory FieldDefinition.fromJson(Map<String, dynamic> json) {
    return FieldDefinition(
      label: json['label'] as String,
      type: FieldType.fromString(json['type'] as String),
    );
  }
}