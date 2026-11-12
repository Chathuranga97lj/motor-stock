import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/branch.dart';
import '../models/lookup.dart';
import '../services/import_template.dart';
import '../services/lookup_service.dart';
import '../services/part_import.dart';
import '../services/parts_service.dart';
import '../theme.dart';
import '../utils/money.dart';

const _xlsxMime =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
const _orange = Color(0xFFD97A00);

/// Reads the sheet on another isolate so big files don't freeze the screen.
/// Top-level on purpose: the closure must not capture the screen's state,
/// which cannot be sent to another isolate.
Future<ImportSheet> _readInBackground(
  Uint8List bytes,
  String fileName,
  List<ImportBranch> branches,
) =>
    Isolate.run(() => parseImportSheet(readSheetTable(bytes, fileName), branches));

enum _Filter {
  all('All'),
  create('New'),
  update('Update'),
  skip('Skipped'),
  check('Check');

  const _Filter(this.label);
  final String label;
}

/// Super admin: adds many parts at once from an Excel or CSV sheet, with a
/// preview of what happens to every row before anything is saved.
/// Pops with true when parts were imported.
class ImportPartsScreen extends StatefulWidget {
  const ImportPartsScreen({super.key, required this.branches, this.branchId});

  final List<Branch> branches;

  /// Default branch for a plain Quantity column.
  final String? branchId;

  @override
  State<ImportPartsScreen> createState() => _ImportPartsScreenState();
}

class _ImportPartsScreenState extends State<ImportPartsScreen> {
  final _service = PartsService();
  Lookups _lookups = const Lookups();
  String? _busy;
  String? _error;
  String? _fileName;
  ImportSheet? _sheet;
  ImportResult? _check;
  String? _qtyBranchId;
  bool _updateStock = false;
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _qtyBranchId = widget.branchId ?? widget.branches.firstOrNull?.id;
    _loadLookups();
  }

  Future<void> _loadLookups() async {
    try {
      final lookups = await LookupService().fetchAll();
      if (mounted) setState(() => _lookups = lookups);
    } catch (_) {
      // Only used for the template lists and hints.
    }
  }

  String _branchName(String id) =>
      widget.branches.where((b) => b.id == id).firstOrNull?.name ?? '?';

  static String _clean(Object e) =>
      '$e'.replaceFirst(RegExp(r'^(Exception|ImportFileException): '), '');

  List<Map<String, dynamic>> _payload(ImportSheet sheet) => [
        for (final r in sheet.validRows)
          r.toJson(quantityBranchId: _qtyBranchId),
      ];

  // ---------- Actions ----------

  Future<void> _pickFile() async {
    final PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(dialogTitle: 'Choose the parts sheet');
    } catch (e) {
      setState(() => _error = 'Could not open the file: ${_clean(e)}');
      return;
    }
    if (picked == null || !mounted) return;
    final file = picked;
    setState(() {
      _busy = 'Reading ${file.name}…';
      _error = null;
      _sheet = null;
      _check = null;
    });
    try {
      final bytes = await file.readAsBytes();
      final name = file.name;
      final sheet = await _readInBackground(bytes, name, [
        for (final b in widget.branches) ImportBranch(b.id, b.name),
      ]);
      if (!mounted) return;
      setState(() => _busy = 'Checking ${sheet.rows.length} rows…');
      final check = sheet.validRows.isEmpty
          ? ImportResult.fromJson(const {})
          : await _service.importParts(_payload(sheet), dryRun: true);
      if (!mounted) return;
      setState(() {
        _fileName = name;
        _sheet = sheet;
        _check = check;
        _filter = _Filter.all;
        _updateStock = false;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _runImport() async {
    final sheet = _sheet;
    final check = _check;
    if (sheet == null || check == null) return;
    final count = check.created + check.updated;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Import $count ${count == 1 ? 'part' : 'parts'}?'),
        content: Text([
          if (check.created > 0)
            '${check.created} new ${check.created == 1 ? 'part is' : 'parts are'} '
                'added with the sheet quantities as opening stock.',
          if (check.updated > 0)
            '${check.updated} ${check.updated == 1 ? 'part' : 'parts'} already '
                'in the app get the prices and details from the sheet'
                '${_updateStock ? ', and their stock is set from the sheet' : '. Their stock stays as it is'}.',
          if (_skipCount > 0)
            '$_skipCount ${_skipCount == 1 ? 'row has' : 'rows have'} a problem '
                'and ${_skipCount == 1 ? 'is' : 'are'} skipped.',
        ].join('\n\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _busy = 'Importing $count parts…';
      _error = null;
    });
    try {
      final result = await _service.importParts(
        _payload(sheet),
        dryRun: false,
        updateStock: _updateStock,
      );
      if (!mounted) return;
      final skipped = sheet.errorCount + result.skipped;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Brand.green, size: 40),
          title: const Text('Import done'),
          content: Text([
            '${result.created} ${result.created == 1 ? 'part' : 'parts'} added',
            '${result.updated} ${result.updated == 1 ? 'part' : 'parts'} updated',
            if (skipped > 0) '$skipped ${skipped == 1 ? 'row' : 'rows'} skipped',
          ].join('\n')),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Import failed: ${_clean(e)}');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _saveTemplate() async {
    final brandNames = {for (final b in _lookups.brands) b.id: b.name};
    final models = [
      for (final m in _lookups.models)
        if (brandNames[m.brandId] != null) (brandNames[m.brandId]!, m.name),
    ]..sort((a, b) => a.$1 == b.$1 ? a.$2.compareTo(b.$2) : a.$1.compareTo(b.$1));
    final bytes = buildImportTemplate(
      branches: [for (final b in widget.branches) b.name],
      lists: TemplateLists(
        categories: [for (final c in _lookups.categories) c.name]..sort(),
        brands: [for (final b in _lookups.brands) b.name]..sort(),
        models: models,
      ),
    );
    try {
      final uri = await FilePicker.saveFile(
        fileName: 'OSHU Parts Import Template.xlsx',
        bytes: bytes,
        mimeType: _xlsxMime,
        dialogTitle: 'Save the template',
      );
      if (uri != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Template saved. Fill it in Excel, then choose it here.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not save the template: ${_clean(e)}');
      }
    }
  }

  // ---------- Row status ----------

  ImportAction _actionOf(ImportRow r) => !r.isValid
      ? ImportAction.skip
      : _check?.outcomes[r.rowNo]?.action ?? ImportAction.skip;

  int _count(_Filter f) =>
      _sheet?.rows.where((r) => _matches(r, f)).length ?? 0;

  bool _matches(ImportRow r, _Filter f) => switch (f) {
        _Filter.all => true,
        _Filter.create => _actionOf(r) == ImportAction.create,
        _Filter.update => _actionOf(r) == ImportAction.update,
        _Filter.skip => _actionOf(r) == ImportAction.skip,
        _Filter.check =>
          _actionOf(r) != ImportAction.skip && r.warnings.isNotEmpty,
      };

  int get _skipCount => _count(_Filter.skip);

  bool get _updatesHaveStock => _sheet!.rows.any((r) =>
      _actionOf(r) == ImportAction.update &&
      r.stockFor(_qtyBranchId).isNotEmpty);

  String _updateNote(ImportRow r) {
    if (r.stockFor(_qtyBranchId).isEmpty) {
      return 'Already in the app: prices and details are updated';
    }
    return _updateStock
        ? 'Already in the app: prices, details and stock are updated'
        : 'Already in the app: prices and details are updated, stock stays';
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final sheet = _sheet;
    final importCount = (_check?.created ?? 0) + (_check?.updated ?? 0);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import parts'),
        actions: [
          if (sheet != null && _busy == null)
            IconButton(
              tooltip: 'Choose another file',
              icon: const Icon(Icons.file_open_outlined),
              onPressed: _pickFile,
            ),
        ],
      ),
      body: _busy != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_busy!),
                ],
              ),
            )
          : sheet == null
              ? _startView()
              : _previewView(sheet),
      bottomNavigationBar: sheet == null || _busy != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: FilledButton.icon(
                  onPressed: importCount == 0 ? null : _runImport,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text(importCount == 0
                      ? 'Nothing to import'
                      : 'Import $importCount ${importCount == 1 ? 'part' : 'parts'}'),
                ),
              ),
            ),
    );
  }

  Widget _errorCard() => Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline,
                  color: Theme.of(context).colorScheme.onErrorContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _startView() {
    final columns = <(String, String)>[
      ('Name', 'needed'),
      ('Part No', 'item code'),
      ('Barcode', 'optional'),
      ('Category', 'new names are added to the list'),
      ('Bike Brand', 'new names are added to the list'),
      ('Bike Model', 'needs a bike brand'),
      ('Buy Price', 'cost price'),
      ('Sell Price', 'price on the bill'),
      for (final b in widget.branches)
        (branchQtyHeader(b.name), 'opening stock at ${b.name}'),
      ('Low Stock Level', 'empty means 2'),
    ];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (_error != null) _errorCard(),
        SectionCard(
          title: 'Add parts from a sheet',
          icon: Icons.upload_file,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Add many parts at once from an Excel (.xlsx) or CSV file: '
                'names, prices and opening stock. You see what will happen to '
                'every row before anything is saved.',
                style: TextStyle(color: Brand.muted),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Choose Excel or CSV file'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _saveTemplate,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Get the Excel template'),
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Columns the app reads',
          icon: Icons.view_column_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (name, note) in columns)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(
                      text: name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(
                      text: '  $note',
                      style: const TextStyle(color: Brand.muted),
                    ),
                  ])),
                ),
              const SizedBox(height: 8),
              const Text(
                'Close names work too, like Item Code, Unit Price (buy price), '
                'Selling Price or Qty. Other columns, like pictures, are skipped.',
                style: TextStyle(color: Brand.muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _previewView(ImportSheet sheet) {
    final check = _check!;
    final visible = sheet.rows.where((r) => _matches(r, _filter)).toList();
    final hasNewNames = check.newCategories.isNotEmpty ||
        check.newBrands.isNotEmpty ||
        check.newModels.isNotEmpty;
    final header = <Widget>[
      if (_error != null) _errorCard(),
      SectionCard(
        title: _fileName,
        icon: Icons.description_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${sheet.rows.length} ${sheet.rows.length == 1 ? 'row' : 'rows'}'
              '${sheet.blankRows > 0 ? ' • ${sheet.blankRows} empty rows left out' : ''}',
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in sheet.columns.entries)
                  _columnChip(e.key.label, e.value),
                for (final e in sheet.branchColumns.entries)
                  _columnChip('${_branchName(e.key)} stock', e.value),
              ],
            ),
            if (sheet.ignoredColumns.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Not used: ${sheet.ignoredColumns.join(', ')}',
                style: const TextStyle(color: Brand.muted, fontSize: 13),
              ),
            ],
            if (!sheet.columns.containsKey(ImportField.sellPrice)) ...[
              const SizedBox(height: 8),
              const Text(
                'No Sell Price column: new parts get price 0.',
                style: TextStyle(color: _orange, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      if (sheet.hasQuantityColumn && widget.branches.isNotEmpty)
        SectionCard(
          title: 'Opening stock',
          icon: Icons.store_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('The "${sheet.columns[ImportField.quantity]}" column is the '
                  'stock at this branch:'),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _qtyBranchId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Branch'),
                items: [
                  for (final b in widget.branches)
                    DropdownMenuItem(value: b.id, child: Text(b.name)),
                ],
                onChanged: (v) => setState(() => _qtyBranchId = v),
              ),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: StatBox(
                    label: 'New parts',
                    value: '${check.created}',
                    color: Brand.green,
                    icon: Icons.add_circle_outline,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatBox(
                    label: 'Update',
                    value: '${check.updated}',
                    note: 'already in the app',
                    color: Brand.blue,
                    icon: Icons.sync,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: StatBox(
                    label: 'Skipped',
                    value: '$_skipCount',
                    note: 'have a problem',
                    color: Brand.red,
                    icon: Icons.block,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatBox(
                    label: 'Check',
                    value: '${_count(_Filter.check)}',
                    note: 'imported, take a look',
                    color: _orange,
                    icon: Icons.warning_amber_rounded,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      if (hasNewNames)
        SectionCard(
          title: 'New names for the lists',
          icon: Icons.playlist_add,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (check.newCategories.isNotEmpty)
                _namesLine('Categories', check.newCategories),
              if (check.newBrands.isNotEmpty)
                _namesLine('Bike brands', check.newBrands),
              if (check.newModels.isNotEmpty)
                _namesLine('Bike models', check.newModels),
              const SizedBox(height: 6),
              Text(
                'These are added to Lists & branches. If one is another '
                'spelling of a name the app already has, fix it in the sheet '
                'and choose the file again.'
                '${check.newCategories.isNotEmpty && _lookups.categories.isNotEmpty ? '\nCategories in the app: ${_lookups.categories.map((c) => c.name).join(', ')}' : ''}',
                style: const TextStyle(color: Brand.muted, fontSize: 13),
              ),
            ],
          ),
        ),
      if (check.updated > 0 && _updatesHaveStock)
        Card(
          child: SwitchListTile(
            value: _updateStock,
            onChanged: (v) => setState(() => _updateStock = v),
            title: const Text('Also set the stock of parts already in the app'),
            subtitle: Text(_updateStock
                ? 'Their stock becomes the quantity in the sheet.'
                : 'Off: only their prices and details change.'),
          ),
        ),
      SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          children: [
            for (final f in _Filter.values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text('${f.label} (${_count(f)})'),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
              ),
          ],
        ),
      ),
    ];

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          sliver: SliverList.list(children: header),
        ),
        if (visible.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No rows here')),
            ),
          )
        else
          SliverList.builder(
            itemCount: visible.length,
            itemBuilder: (context, i) => _rowTile(visible[i]),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }

  Widget _columnChip(String field, String header) {
    final same = field.toLowerCase() == header.toLowerCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Brand.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        same ? field : '$field ← $header',
        style: const TextStyle(fontSize: 13, color: Brand.ink),
      ),
    );
  }

  Widget _namesLine(String label, List<String> names) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text.rich(TextSpan(children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: names.join(', ')),
        ])),
      );

  Widget _rowTile(ImportRow r) {
    final action = _actionOf(r);
    final (color, label) = switch (action) {
      ImportAction.create => (Brand.green, 'New'),
      ImportAction.update => (Brand.blue, 'Update'),
      ImportAction.skip => (Brand.red, 'Skip'),
    };
    final serverMessage = r.isValid ? _check?.outcomes[r.rowNo]?.message : null;
    final details = [
      r.partNo,
      r.category,
      [r.brand, r.model].whereType<String>().join(' '),
    ].whereType<String>().where((s) => s.isNotEmpty).join(' • ');
    final stock = r.stockFor(_qtyBranchId);
    final messages = <(IconData, Color, String)>[
      for (final e in r.errors) (Icons.error_outline, Brand.red, e),
      if (action == ImportAction.skip && serverMessage != null)
        (Icons.error_outline, Brand.red, serverMessage),
      if (action == ImportAction.update)
        (Icons.info_outline, Brand.blue, _updateNote(r)),
      if (action != ImportAction.skip)
        for (final w in r.warnings) (Icons.warning_amber_rounded, _orange, w),
    ];
    return TileCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    r.name.isEmpty ? '(no name)' : r.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Row ${r.rowNo}',
                  style: const TextStyle(color: Brand.muted, fontSize: 12),
                ),
              ],
            ),
            if (details.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  details,
                  style: const TextStyle(color: Brand.muted, fontSize: 13),
                ),
              ),
            if (r.sellPrice != null || r.buyPrice != null || stock.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 2,
                  children: [
                    if (r.sellPrice != null)
                      Text('Sell ${formatMoney(r.sellPrice!)}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (r.buyPrice != null)
                      Text('Buy ${formatMoney(r.buyPrice!)}',
                          style: const TextStyle(color: Brand.muted)),
                    for (final e in stock.entries)
                      Text('${_branchName(e.key)}: ${e.value}',
                          style: const TextStyle(color: Brand.muted)),
                  ],
                ),
              ),
            for (final (icon, c, text) in messages)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 16, color: c),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(text, style: TextStyle(color: c, fontSize: 13)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
