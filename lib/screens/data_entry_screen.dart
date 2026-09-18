import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/field_definition.dart';
import '../models/sheet.dart';
import '../state/app_state.dart';

/// Screen for adding a new entry to a selected sheet/tab.
/// Dynamically generates form fields based on the sheet's field definitions.
class DataEntryScreen extends StatefulWidget {
  final Sheet sheet;

  const DataEntryScreen({super.key, required this.sheet});

  /// Named constructor kept for readability: DataEntryScreen.sheet(sheet: ...).
  const DataEntryScreen.sheet({super.key, required this.sheet});

  @override
  State<DataEntryScreen> createState() => _DataEntryScreenState();
}

class _DataEntryScreenState extends State<DataEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final field in widget.sheet.fields)
        field.label: TextEditingController(),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(FieldDefinition field) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _controllers[field.label]!.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final appState = context.read<AppState>();
      final rowValues = widget.sheet.fields
          .map((field) => _controllers[field.label]!.text.trim())
          .toList();

      await appState.sheetsService.appendRow(
        spreadsheetId: widget.sheet.spreadsheetId,
        sheetName: widget.sheet.name,
        rowValues: rowValues,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Entry saved successfully!')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to save entry: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Add Entry — ${widget.sheet.name}'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Dynamic form fields
            ...widget.sheet.fields.asMap().entries.map(
                  (entry) => _buildField(
                    index: entry.key,
                    field: entry.value,
                  ),
                ),
            const SizedBox(height: 24),

            // Error message
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ),

            // Submit button
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(
                  _isSubmitting ? 'Saving...' : 'Submit Entry',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the appropriate input widget based on the field type.
  Widget _buildField({required int index, required FieldDefinition field}) {
    switch (field.type) {
      case FieldType.date:
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: TextFormField(
            controller: _controllers[field.label],
            readOnly: true,
            decoration: InputDecoration(
              labelText: field.label,
              hintText: 'Tap to pick date',
              border: const OutlineInputBorder(),
              suffixIcon: const Icon(Icons.calendar_today),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please select a date';
              }
              return null;
            },
            onTap: () => _pickDate(field),
          ),
        );
      case FieldType.number:
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: TextFormField(
            controller: _controllers[field.label],
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: field.label,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.numbers),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter a number';
              }
              if (double.tryParse(value.trim()) == null) {
                return 'Please enter a valid number';
              }
              return null;
            },
          ),
        );
      case FieldType.text:
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: TextFormField(
            controller: _controllers[field.label],
            decoration: InputDecoration(
              labelText: field.label,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.text_fields),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter a value';
              }
              return null;
            },
          ),
        );
    }
  }
}