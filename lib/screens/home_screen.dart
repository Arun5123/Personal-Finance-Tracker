import 'package:characters/characters.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/sheet.dart';
import '../state/app_state.dart';
import '../widgets/app_animations.dart';

/// Home screen showing all created sheets/tabs and
/// options to create new ones, add entries, or view data.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh per-sheet entry states so menu actions are up to date.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().refreshSheetEntryStates();
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final sheets = appState.sheets;

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: ClipOval(
            child: Image.asset(
              'assets/app_logo.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: AppColors.surfaceTint,
                child: const Icon(Icons.table_chart, color: AppColors.primary),
              ),
            ),
          ),
        ),
        title: const Text('My Sheets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () async {
              await appState.signOut();
              if (context.mounted) {
                Navigator.of(context).pushReplacementNamed('/login');
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildUserBanner(appState),
          _buildErrorBanner(appState),
          _buildSheetsList(context, sheets),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.of(context).pushNamed('/create-sheet');
          if (created == true && context.mounted) {
            await context.read<AppState>().refreshSheetEntryStates();
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Sheet'),
      ),
    );
  }

  Widget _buildUserBanner(AppState appState) {
    if (!appState.authService.isSignedIn) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.surfaceTint,
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.blue.shade200,
            child: Text(
              (appState.authService.userDisplayName ?? 'U')
                  .characters
                  .first
                  .toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appState.authService.userDisplayName ?? 'User',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  appState.authService.userEmail ?? '',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(AppState appState) {
    if (appState.errorMessage == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.red.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.error, color: Colors.red.shade700),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                appState.errorMessage!,
                style: TextStyle(color: Colors.red.shade700),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: appState.clearError,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSheetsList(BuildContext context, List<Sheet> sheets) {
    if (sheets.isEmpty) return _buildEmptyState();
    return Expanded(
      child: RefreshIndicator(
        onRefresh: () => context.read<AppState>().refreshSheetEntryStates(),
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: sheets.length,
          itemBuilder: (context, index) {
            final sheet = sheets[index];
            return StaggeredEntrance(
              index: index,
              child: _SheetCard(sheet: sheet),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.description_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No sheets yet',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap the button below to create your first\nsheet like "House Rent" or "Monthly Collection"',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            const Text(
              'Your data is saved directly to your Google Drive',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card widget for each sheet with actions to add/view data.
/// The three-dot menu is always visible and the Delete option is
/// always available — even for sheets with no entries yet.
class _SheetCard extends StatefulWidget {
  final Sheet sheet;

  const _SheetCard({required this.sheet});

  @override
  State<_SheetCard> createState() => _SheetCardState();
}

class _SheetCardState extends State<_SheetCard> {
  bool _checkingEntries = true;
  bool _hasEntries = false;

  @override
  void initState() {
    super.initState();
    _loadEntryState();
  }

  @override
  void didUpdateWidget(covariant _SheetCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sheet.name != widget.sheet.name ||
        oldWidget.sheet.spreadsheetId != widget.sheet.spreadsheetId) {
      _loadEntryState();
    }
  }

  Future<void> _loadEntryState() async {
    // Imported sheets always contain data loaded from the external
    // Excel file, so there is no need to query.
    if (widget.sheet.isImported) {
      if (mounted) {
        setState(() {
          _hasEntries = true;
          _checkingEntries = false;
        });
      }
      return;
    }
    setState(() => _checkingEntries = true);
    try {
      final appState = context.read<AppState>();
      final cached = appState.cachedSheetHasEntries(widget.sheet);
      if (cached && mounted) setState(() => _hasEntries = true);
      final hasEntries =
          await appState.sheetHasEntries(widget.sheet, refresh: true);
      if (mounted) {
        setState(() {
          _hasEntries = hasEntries;
          _checkingEntries = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _checkingEntries = false);
    }
  }

  void _openViewData() {
    Navigator.of(context).pushNamed('/view-data', arguments: widget.sheet);
  }

  Future<void> _handleMenuSelection(String value) async {
    if (value == 'view') {
      _openViewData();
    } else if (value == 'download') {
      final appState = context.read<AppState>();
      final ok = await appState.downloadSheet(widget.sheet);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Sheet "${widget.sheet.name}" exported as '
                    '"${widget.sheet.name}.csv". Choose where to save it.'
                : (appState.errorMessage ??
                    'Could not download sheet "${widget.sheet.name}".'),
          ),
        ),
      );
    } else if (value == 'delete') {
      _confirmDeleteSheet();
    }
  }

  Future<void> _confirmDeleteSheet() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${widget.sheet.name}"?'),
        content: const Text(
          "All the sheet's content and the sheet will be deleted. "
          'Do you wish to continue?',
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
    final appState = context.read<AppState>();
    final sheetName = widget.sheet.name;
    final success = await appState.deleteSheet(widget.sheet);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Sheet "$sheetName" deleted.'
              : (appState.errorMessage ?? 'Could not delete "$sheetName".'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sheet = widget.sheet;
    final showEntryActions = _hasEntries && !_checkingEntries;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderRow(context, sheet),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              children: sheet.fields
                  .map<Widget>(
                    (field) => Chip(
                      label: Text(
                        field.label,
                        style: const TextStyle(fontSize: 11),
                      ),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Colors.grey.shade100,
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            _buildActionRow(context, sheet, showEntryActions),
            if (_checkingEntries && !sheet.isImported)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Checking entries…',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderRow(BuildContext context, Sheet sheet) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surfaceTint,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            sheet.isImported ? Icons.upload_file : Icons.table_chart,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sheet.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    '${sheet.fields.length} fields',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  if (sheet.isImported) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Text(
                        'Imported · Read-only',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        // Three-dot menu is always visible; Delete is always available,
        // even when the sheet has no entries.
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          tooltip: 'Sheet options',
          onSelected: _handleMenuSelection,
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'view',
              child: Row(
                children: [
                  Icon(Icons.visibility_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('View Data'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'download',
              child: Row(
                children: [
                  Icon(Icons.download_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('Download Excel'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  SizedBox(width: 12),
                  Text('Delete Sheet', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Action buttons per sheet type. Imported sheets are read-only:
  /// they offer "View Data" only, with no way to add entries.
  Widget _buildActionRow(
    BuildContext context,
    Sheet sheet,
    bool showEntryActions,
  ) {
    if (sheet.isImported) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _openViewData,
          icon: const Icon(Icons.visibility_outlined, size: 18),
          label: const Text('View Data'),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final added = await Navigator.of(context)
                  .pushNamed('/add-entry', arguments: sheet);
              if (added == true && mounted) {
                context.read<AppState>().markSheetHasEntries(sheet);
                await _loadEntryState();
              }
            },
            icon: const Icon(Icons.add_circle_outline, size: 18),
            label: const Text('Add Entry'),
          ),
        ),
        if (showEntryActions) ...[
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _openViewData,
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('View Data'),
            ),
          ),
        ],
      ],
    );
  }
}
