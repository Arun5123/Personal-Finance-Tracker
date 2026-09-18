import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/field_definition.dart';
import '../services/excel_import_service.dart';
import '../state/app_state.dart';
import '../widgets/app_animations.dart';

/// Screen for creating a new sheet with custom field definitions, or
/// importing worksheets from an external Excel file into the user's
/// Google Drive spreadsheet (read-only).
class CreateSheetScreen extends StatefulWidget {
  const CreateSheetScreen({super.key});

  @override
  State<CreateSheetScreen> createState() => _CreateSheetScreenState();
}

class _CreateSheetScreenState extends State<CreateSheetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _sheetNameController = TextEditingController();
  final List<_FieldInput> _fieldInputs = [
    _FieldInput(label: 'Date', type: FieldType.date),
    _FieldInput(label: 'Amount', type: FieldType.number),
  ];

  bool _isImportMode = false;
  bool _showSuccess = false;
  String? _successMessage;

  // Import state.
  final ExcelImportService _excelImporter = ExcelImportService();
  List<ExternalExcelSheet>? _parsedSheets;
  final Set<String> _selectedImports = {};
  String? _importFileName;

  @override
  void dispose() {
    _sheetNameController.dispose();
    for (final input in _fieldInputs) {
      input.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Add Sheet')),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Mode switch: Create vs Import.
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.edit_note),
                      label: Text('Create'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.upload_file),
                      label: Text('Import'),
                    ),
                  ],
                  selected: {_isImportMode},
                  onSelectionChanged: (selection) {
                    setState(() => _isImportMode = selection.first);
                  },
                ),
                const SizedBox(height: 20),
                if (_isImportMode)
                  _buildImportSection(appState)
                else
                  _buildCreateSection(appState),
                const SizedBox(height: 24),
                if (appState.errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      appState.errorMessage!,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),
              ],
            ),
          ),
          if (_showSuccess)
            SuccessCheckmark(message: _successMessage ?? 'Done!'),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CREATE mode
  // ---------------------------------------------------------------------------

  Widget _buildCreateSection(AppState appState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _sheetNameController,
          decoration: const InputDecoration(
            labelText: 'Sheet Name',
            hintText: 'e.g. House Rent, Monthly Collection',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.table_chart_outlined),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter a sheet name';
            }
            return null;
          },
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const Text(
              'Fields (Columns)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _addField,
              icon: const Icon(Icons.add),
              label: const Text('Add Field'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Tip: drag a row by its handle, or use the up/down arrows. '
          'The blue number shows the saved field order.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _fieldInputs.length,
          onReorder: _reorderFields,
          proxyDecorator: (child, index, animation) => Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: child,
          ),
          itemBuilder: (context, index) => _FieldInputCard(
            key: ValueKey(_fieldInputs[index].key),
            index: index,
            input: _fieldInputs[index],
            onRemove: _fieldInputs.length > 1
                ? () => _removeField(index)
                : null,
            onMoveUp: index > 0 ? () => _moveField(index, index - 1) : null,
            onMoveDown: index < _fieldInputs.length - 1
                ? () => _moveField(index, index + 1)
                : null,
            onTypeChanged: (type) {
              setState(() {
                _fieldInputs[index].type = type;
              });
            },
          ),
        ),
        const SizedBox(height: 24),
        // Create Sheet button — foreground color is explicit so the
        // label is always visible on the blue background.
        SizedBox(
          height: 52,
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: appState.isLoading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.primary.withOpacity(0.6),
              disabledForegroundColor: Colors.white,
            ),
            icon: appState.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check),
            label: Text(
              appState.isLoading ? 'Creating...' : 'Create Sheet',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // IMPORT mode
  // ---------------------------------------------------------------------------

  Widget _buildImportSection(AppState appState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceTint,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Pick an external Excel (.xlsx) file. Each worksheet is '
                  'copied into your Drive spreadsheet as a read-only sheet.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton.icon(
            onPressed: appState.isLoading ? null : _pickExcelFile,
            icon: const Icon(Icons.folder_open),
            label: Text(
              _importFileName == null
                  ? 'Choose Excel File'
                  : 'Change File',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (_importFileName != null) ...[
          const SizedBox(height: 8),
          Text(
            _importFileName!,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 16),
        if (_parsedSheets == null)
          const SizedBox.shrink()
        else if (_parsedSheets!.isEmpty)
          Text(
            'No worksheets with data were found in this file.',
            style: TextStyle(color: Colors.red.shade700),
          )
        else ...[
          Text(
            'Worksheets found (${_parsedSheets!.length})',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ..._parsedSheets!.map((external) {
            final selected = _selectedImports.contains(external.name);
            return CheckboxListTile(
              value: selected,
              onChanged: (checked) {
                setState(() {
                  if (checked == true) {
                    _selectedImports.add(external.name);
                  } else {
                    _selectedImports.remove(external.name);
                  }
                });
              },
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: Text(external.name),
              subtitle: Text(
                '${external.dataRowCount} data rows · '
                '${external.headers.length} columns',
                style: const TextStyle(fontSize: 12),
              ),
              secondary: const Icon(
                Icons.table_rows_outlined,
                color: AppColors.primary,
              ),
            );
          }),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: appState.isLoading || _selectedImports.isEmpty
                  ? null
                  : _importSelected,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.primary.withOpacity(0.6),
                disabledForegroundColor: Colors.white,
              ),
              icon: appState.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.upload),
              label: Text(
                appState.isLoading
                    ? 'Importing...'
                    : 'Import ${_selectedImports.length} Sheet${_selectedImports.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _pickExcelFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;

    try {
      final sheets = await _excelImporter.parseWorkbook(path);
      if (!mounted) return;
      setState(() {
        _importFileName = result.files.single.name;
        _parsedSheets = sheets;
        _selectedImports
          ..clear()
          ..addAll(sheets.map((s) => s.name));
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not read the Excel file: ${e.toString()}',
          ),
        ),
      );
    }
  }

  Future<void> _importSelected() async {
    final toImport = _parsedSheets!
        .where((s) => _selectedImports.contains(s.name))
        .toList();
    if (toImport.isEmpty) return;

    final appState = context.read<AppState>();
    final imported = await appState.importSheets(toImport);

    if (!mounted) return;
    if (imported > 0) {
      setState(() {
        _successMessage =
            '$imported sheet${imported == 1 ? '' : 's'} imported!';
        _showSuccess = true;
      });
      await Future.delayed(const Duration(milliseconds: 1400));
      if (mounted) Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            appState.errorMessage ?? 'Nothing was imported. Please try again.',
          ),
        ),
      );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    for (final field in _fieldInputs) {
      if (field.labelController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill in all field labels')),
        );
        return;
      }
    }

    final appState = context.read<AppState>();
    final fieldDefs = _fieldInputs
        .map((input) => {
              'label': input.labelController.text.trim(),
              'type': input.type.name,
            })
        .toList();

    final success = await appState.createSheet(
      name: _sheetNameController.text.trim(),
      fieldDefs: fieldDefs,
    );

    if (success && mounted) {
      setState(() {
        _successMessage = 'Sheet created successfully!';
        _showSuccess = true;
      });
      await Future.delayed(const Duration(milliseconds: 1400));
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  void _addField() {
    setState(() {
      _fieldInputs.add(_FieldInput(label: '', type: FieldType.text));
    });
  }

  void _removeField(int index) {
    setState(() {
      final removed = _fieldInputs.removeAt(index);
      removed.dispose();
    });
  }

  /// Moves a field from [oldIndex] to [newIndex], updating sequence numbers.
  void _moveField(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 ||
        newIndex < 0 ||
        oldIndex >= _fieldInputs.length ||
        newIndex >= _fieldInputs.length) {
      return;
    }
    setState(() {
      final field = _fieldInputs.removeAt(oldIndex);
      _fieldInputs.insert(newIndex, field);
    });
  }

  /// Handles drag-and-drop reordering. Sequence numbers follow the new order.
  void _reorderFields(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final field = _fieldInputs.removeAt(oldIndex);
      _fieldInputs.insert(newIndex, field);
    });
  }
}

/// Helper class holding state for each dynamic field input row.
class _FieldInput {
  static int _nextKey = 0;
  final String key;
  final TextEditingController labelController;
  FieldType type;

  _FieldInput({required String label, required this.type})
      : key = 'field_${_nextKey++}',
        labelController = TextEditingController(text: label);

  void dispose() {
    labelController.dispose();
  }
}

/// Widget for editing a single field definition.
class _FieldInputCard extends StatelessWidget {
  final int index;
  final _FieldInput input;
  final VoidCallback? onRemove;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final ValueChanged<FieldType> onTypeChanged;

  const _FieldInputCard({
    super.key,
    required this.index,
    required this.input,
    this.onRemove,
    this.onMoveUp,
    this.onMoveDown,
    required this.onTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: AppColors.surfaceTint,
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 28,
                  width: 28,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                    tooltip: 'Move field up',
                    onPressed: onMoveUp,
                  ),
                ),
                SizedBox(
                  height: 28,
                  width: 28,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                    tooltip: 'Move field down',
                    onPressed: onMoveDown,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            Expanded(
              child: TextFormField(
                controller: input.labelController,
                decoration: const InputDecoration(
                  labelText: 'Field Name (Label)',
                  hintText: 'e.g. Tenant Name',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<FieldType>(
              value: input.type,
              items: const [
                DropdownMenuItem(value: FieldType.date, child: Text('Date')),
                DropdownMenuItem(value: FieldType.number, child: Text('Number')),
                DropdownMenuItem(value: FieldType.text, child: Text('Text')),
              ],
              onChanged: (value) {
                if (value != null) {
                  onTypeChanged(value);
                }
              },
            ),
            if (onRemove != null)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: onRemove,
                tooltip: 'Remove field',
              ),
            const SizedBox(width: 4),
            ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.drag_handle, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
