import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/field_definition.dart';
import '../models/sheet.dart';
import '../state/app_state.dart';
import '../widgets/app_animations.dart';

/// Screen for viewing existing entries in a selected sheet/tab.
/// Fetches data directly from the Google Sheet.
class DataViewScreen extends StatefulWidget {
  final Sheet sheet;

  const DataViewScreen({super.key, required this.sheet});

  /// Named constructor kept for readability: DataViewScreen.sheet(sheet: ...).
  const DataViewScreen.sheet({super.key, required this.sheet});

  @override
  State<DataViewScreen> createState() => _DataViewScreenState();
}

class _DataViewScreenState extends State<DataViewScreen> {
  bool _isLoading = true;
  String? _error;
  List<String> _headers = [];
  List<List<String>> _rows = [];

  // Active per-column filters: header label -> selected value.
  final Map<String, String> _activeFilters = {};

  // Current sort state.
  String? _sortColumn;
  bool _sortAscending = true;

  // True while a row is being updated/deleted on the remote sheet.
  bool _isMutating = false;

  bool get _hasActiveFilters => _activeFilters.isNotEmpty;

  // Imported sheets are read-only: no row editing or deleting.
  bool get _canEditRows => !widget.sheet.isImported;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final appState = context.read<AppState>();
      final data = await appState.sheetsService.getSheetData(
        spreadsheetId: widget.sheet.spreadsheetId,
        sheetName: widget.sheet.name,
      );

      if (mounted) {
        setState(() {
          if (data.isNotEmpty) {
            _headers = data.first;
            _rows = data.skip(1).toList();
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load data: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('View Data — ${widget.sheet.name}'),
        actions: [
          if (_hasActiveFilters)
            IconButton(
              icon: Badge(
                label: Text('${_activeFilters.length}'),
                child: const Icon(Icons.filter_alt),
              ),
              tooltip: 'Clear all filters',
              onPressed: _clearAllFilters,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadData,
          ),
        ],
      ),
      body: Column(
        children: [
          if (widget.sheet.isImported)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.green.shade50,
              child: Row(
                children: [
                  Icon(Icons.lock_outline, size: 16, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Read-only — imported from an external Excel file. '
                      'Editing and deleting entries are disabled.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_hasActiveFilters) _buildActiveFilterChips(),
          if (_isMutating) const LinearProgressIndicator(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No entries yet',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap "Add Entry" from the home screen\nto add your first entry',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    // Build a scrollable, filterable, sortable table view.
    final visibleIndices = _visibleRowIndices;
    if (visibleIndices.isEmpty) {
      return _buildNoMatchesState();
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Align(
        alignment: Alignment.topLeft,
        child: SingleChildScrollView(
          key: ValueKey(visibleIndices.length),
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: DataTable(
            headingRowColor: MaterialStateProperty.all(Colors.blue.shade50),
            dataRowMinHeight: 44,
            dataRowMaxHeight: 56,
            columns: [
              for (final h in _headers) DataColumn(label: _buildHeaderLabel(h)),
              if (_canEditRows)
                const DataColumn(label: SizedBox.shrink()),
            ],
            rows: [
              for (final i in visibleIndices)
                DataRow(
                  cells: [
                    for (var c = 0; c < _headers.length; c++)
                      DataCell(
                        Text(
                          c < _rows[i].length ? _rows[i][c] : '',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    // Edit / delete actions for every row. Hidden
                    // entirely for imported (read-only) sheets.
                    if (_canEditRows)
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.edit_outlined,
                                size: 18,
                                color: AppColors.primary,
                              ),
                              tooltip: 'Edit this entry',
                              onPressed: _isMutating
                                  ? null
                                  : () => _showEditDialog(i),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: Colors.red,
                              ),
                              tooltip: 'Delete this entry',
                              onPressed: _isMutating
                                  ? null
                                  : () => _confirmDeleteRow(i),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Indices into [_rows] after applying every active filter and the
  /// current sort. The sheet row number for index i is i + 2, because
  /// row 1 is the header row.
  List<int> get _visibleRowIndices {
    var indices = List<int>.generate(_rows.length, (i) => i);

    // Apply all active filters (multiple columns can be combined).
    if (_activeFilters.isNotEmpty) {
      indices = indices.where((i) {
        final row = _rows[i];
        for (final entry in _activeFilters.entries) {
          final c = _headers.indexOf(entry.key);
          if (c < 0) continue;
          final cell = c < row.length ? row[c].trim() : '';
          if (entry.value == '(empty)') {
            if (cell.isNotEmpty) return false;
          } else if (cell != entry.value) {
            return false;
          }
        }
        return true;
      }).toList();
    }

    // Apply the current sort (numeric-aware).
    if (_sortColumn != null) {
      final sortIndex = _headers.indexOf(_sortColumn!);
      if (sortIndex >= 0) {
        indices.sort((i1, i2) {
          final a =
              sortIndex < _rows[i1].length ? _rows[i1][sortIndex] : '';
          final b =
              sortIndex < _rows[i2].length ? _rows[i2][sortIndex] : '';
          final cmp = _compareValues(a, b);
          return _sortAscending ? cmp : -cmp;
        });
      }
    }

    return indices;
  }

  /// Best-effort field type for a header, from the sheet's definitions.
  FieldType? _fieldTypeFor(String header) {
    for (final f in widget.sheet.fields) {
      if (f.label == header) return f.type;
    }
    return null;
  }

  /// Compares two cell values — numerically when both parse as numbers,
  /// otherwise case-insensitively as text (ISO dates sort correctly).
  int _compareValues(String a, String b) {
    final na = double.tryParse(a.replaceAll(',', ''));
    final nb = double.tryParse(b.replaceAll(',', ''));
    if (na != null && nb != null) return na.compareTo(nb);
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  /// Tappable header cell showing sort direction and filter state.
  Widget _buildHeaderLabel(String header) {
    final isFiltered = _activeFilters.containsKey(header);
    final isSorted = _sortColumn == header;

    return Tooltip(
      message: 'Tap to filter & sort "$header"',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _showColumnSheet(header),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                header,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 4),
              if (isSorted)
                Icon(
                  _sortAscending
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  size: 14,
                  color: AppColors.primary,
                ),
              if (isFiltered)
                const Icon(
                  Icons.filter_alt,
                  size: 14,
                  color: AppColors.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Bottom sheet shown when a table header is tapped. Lets the user
  /// sort the column or pick one of its distinct values to filter by.
  Future<void> _showColumnSheet(String header) async {
    final index = _headers.indexOf(header);
    if (index < 0) return;

    // Distinct values in this column with their row counts.
    final counts = <String, int>{};
    for (final row in _rows) {
      final value = index < row.length ? row[index].trim() : '';
      final key = value.isEmpty ? '(empty)' : value;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => _compareValues(a.key, b.key));

    final currentFilter = _activeFilters[header];
    final isSortedHere = _sortColumn == header;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      header,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(sheetContext).pop(),
                  ),
                ],
              ),
            ),
            // Sort buttons for this column.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _sortColumn = header;
                          _sortAscending = true;
                        });
                        Navigator.of(sheetContext).pop();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isSortedHere && _sortAscending
                            ? AppColors.primary
                            : null,
                      ),
                      icon: const Icon(Icons.arrow_upward, size: 18),
                      label: const Text('Sort A → Z'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _sortColumn = header;
                          _sortAscending = false;
                        });
                        Navigator.of(sheetContext).pop();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isSortedHere && !_sortAscending
                            ? AppColors.primary
                            : null,
                      ),
                      icon: const Icon(Icons.arrow_downward, size: 18),
                      label: const Text('Sort Z → A'),
                    ),
                  ),
                ],
              ),
            ),
            // Clear the filter for this column.
            if (currentFilter != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() => _activeFilters.remove(header));
                      Navigator.of(sheetContext).pop();
                    },
                    icon: const Icon(Icons.filter_alt_off, size: 18),
                    label: const Text('Clear filter for this column'),
                  ),
                ),
              ),
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Select a value to show only those records',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: entries.length,
                itemBuilder: (context, i) {
                  final entry = entries[i];
                  final selected = currentFilter == entry.key;
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: selected ? AppColors.primary : Colors.grey,
                    ),
                    title: Text(entry.key),
                    trailing: Text(
                      '${entry.value} row${entry.value == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    onTap: () {
                      setState(() {
                        if (selected) {
                          _activeFilters.remove(header);
                        } else {
                          _activeFilters[header] = entry.key;
                        }
                      });
                      Navigator.of(sheetContext).pop();
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Removes every active filter (all columns).
  void _clearAllFilters() {
    setState(() {
      _activeFilters.clear();
    });
  }

  /// Horizontally scrollable row of chips, one per active filter, each
  /// removable via its delete icon.
  Widget _buildActiveFilterChips() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: AppColors.surfaceTint,
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final entry in _activeFilters.entries)
            InputChip(
              visualDensity: VisualDensity.compact,
              backgroundColor: Colors.white,
              deleteIcon: const Icon(Icons.close, size: 16),
              label: Text(
                '${entry.key}: ${entry.value}',
                style: const TextStyle(fontSize: 12),
              ),
              onDeleted: () {
                setState(() => _activeFilters.remove(entry.key));
              },
            ),
        ],
      ),
    );
  }

  /// Empty state shown when filters eliminate every row.
  Widget _buildNoMatchesState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.filter_alt_off_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'No entries match the selected filters',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _clearAllFilters,
            icon: const Icon(Icons.filter_alt_off, size: 18),
            label: const Text('Clear all filters'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Row editing & deleting
  // ---------------------------------------------------------------------------

  /// Opens a prefilled edit dialog for the row at [rowIndex] and saves
  /// the changes back to the Google Sheet on confirm.
  Future<void> _showEditDialog(int rowIndex) async {
    final row = _rows[rowIndex];
    final rowNumber = rowIndex + 2; // Row 1 is the header.
    final formKey = GlobalKey<FormState>();
    final controllers = <TextEditingController>[
      for (var c = 0; c < _headers.length; c++)
        TextEditingController(text: c < row.length ? row[c] : ''),
    ];

    List<String>? newValues;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Edit entry — row $rowNumber'),
        content: SizedBox(
          width: double.maxFinite,
          child: Form(
            key: formKey,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (var c = 0; c < _headers.length; c++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildEditField(c, controllers[c]),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              newValues = controllers.map((ctl) => ctl.text.trim()).toList();
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    for (final ctl in controllers) {
      ctl.dispose();
    }

    if (newValues == null || !mounted) return;

    setState(() => _isMutating = true);
    try {
      await context.read<AppState>().sheetsService.updateRow(
            spreadsheetId: widget.sheet.spreadsheetId,
            sheetName: widget.sheet.name,
            rowNumber: rowNumber,
            rowValues: newValues!,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entry updated.')),
      );
      await _loadData();
      if (mounted) {
        await context.read<AppState>().refreshSheetEntryStates();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update entry: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  /// Builds one input field inside the edit dialog. Date fields open a
  /// date picker, matching the Add Entry form behaviour.
  Widget _buildEditField(int index, TextEditingController controller) {
    final header = _headers[index];
    final type = _fieldTypeFor(header);
    final isDate = type == FieldType.date;

    return TextFormField(
      controller: controller,
      readOnly: isDate,
      keyboardType: type == FieldType.number
          ? TextInputType.number
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: header,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: isDate ? const Icon(Icons.calendar_today) : null,
      ),
      onTap: isDate
          ? () async {
              final picked = await showDatePicker(
                context: context,
                initialDate:
                    DateTime.tryParse(controller.text) ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                controller.text = DateFormat('yyyy-MM-dd').format(picked);
              }
            }
          : null,
    );
  }

  /// Confirms and deletes the row at [rowIndex] from the Google Sheet.
  Future<void> _confirmDeleteRow(int rowIndex) async {
    final row = _rows[rowIndex];
    final rowNumber = rowIndex + 2; // Row 1 is the header.
    final firstCell = row.isNotEmpty ? row.first : '(empty)';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: Text(
          'The record "$firstCell" (row $rowNumber) will be permanently '
          'deleted from the sheet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isMutating = true);
    try {
      await context.read<AppState>().sheetsService.deleteRow(
            spreadsheetId: widget.sheet.spreadsheetId,
            sheetName: widget.sheet.name,
            rowNumber: rowNumber,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entry deleted.')),
      );
      await _loadData();
      if (mounted) {
        await context.read<AppState>().refreshSheetEntryStates();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete entry: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }
}