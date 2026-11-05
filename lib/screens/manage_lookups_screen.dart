import 'package:flutter/material.dart';

import '../models/branch.dart';
import '../models/lookup.dart';
import '../services/branch_service.dart';
import '../services/lookup_service.dart';
import '../widgets/lookup_widgets.dart';

/// Add, rename and delete categories, brands and bike models;
/// add and rename shop branches.
class ManageLookupsScreen extends StatefulWidget {
  const ManageLookupsScreen({super.key});

  @override
  State<ManageLookupsScreen> createState() => _ManageLookupsScreenState();
}

class _ManageLookupsScreenState extends State<ManageLookupsScreen> {
  final _service = LookupService();
  final _branchService = BranchService();
  Lookups _lookups = const Lookups();
  List<Branch> _branches = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (lookups, branches) =
          await (_service.fetchAll(), _branchService.fetchBranches()).wait;
      if (mounted) {
        setState(() {
          _lookups = lookups;
          _branches = branches;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load lists: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$e'.replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _add(LookupKind kind, {LookupItem? brand}) async {
    final name = await showNameDialog(
      context,
      title: 'New ${kind.label.toLowerCase()}',
      helperText: brand == null ? null : 'For brand ${brand.name}',
    );
    if (name == null) return;
    await _run(() => _service.add(kind, name, brandId: brand?.id));
  }

  Future<void> _rename(LookupKind kind, LookupItem item) async {
    final name = await showNameDialog(context,
        title: 'Rename ${kind.label.toLowerCase()}', initial: item.name);
    if (name == null || LookupService.normalize(name) == item.name) return;
    await _run(() => _service.rename(kind, item, name));
  }

  Future<void> _delete(LookupKind kind, LookupItem item) async {
    final int used;
    try {
      used = await _service.usageCount(kind, item);
    } catch (e) {
      await _run(() => Future.error(e));
      return;
    }
    if (!mounted) return;

    final models = kind == LookupKind.brand
        ? _lookups.modelsOf(item.id).length
        : 0;
    final warnings = [
      if (models > 0) 'Its $models bike models will also be deleted.',
      if (used > 0)
        '$used part${used == 1 ? '' : 's'} will be left without a '
            '${kind.label.toLowerCase()}${kind == LookupKind.brand ? ' and model' : ''}.',
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${item.name}"?'),
        content: Text(warnings.isEmpty ? 'Not used by any part.' : warnings.join('\n\n')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) await _run(() => _service.delete(kind, item));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: LookupKind.values.length + 1,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lists & branches'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Theme.of(context).colorScheme.tertiary,
            tabs: [
              for (final k in LookupKind.values) Tab(text: k.pluralLabel),
              const Tab(text: 'Branches'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : TabBarView(children: [
                    _simpleList(LookupKind.category),
                    _simpleList(LookupKind.brand),
                    _modelsList(),
                    _branchesList(),
                  ]),
      ),
    );
  }

  // Branches can be added and renamed but not deleted, because their
  // stock and transfer history must stay intact.
  Widget _branchesList() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _addTile('Add branch', () async {
          final name = await showNameDialog(context, title: 'New branch');
          if (name != null) await _run(() => _branchService.addBranch(name));
        }),
        const Divider(height: 1),
        for (final b in _branches)
          ListTile(
            leading: Icon(b.isMain ? Icons.store : Icons.storefront_outlined),
            title: Text(b.name),
            subtitle: Text([
              if (b.isMain) 'Main branch',
              if (b.address != null) b.address!,
              if (b.phone != null) b.phone!,
              if (b.address == null && b.phone == null)
                'Add address and phone for bills',
            ].join(' • ')),
            trailing: IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _editBranch(b),
            ),
          ),
      ],
    );
  }

  Future<void> _editBranch(Branch b) async {
    final name = TextEditingController(text: b.name);
    final address = TextEditingController(text: b.address);
    final phone = TextEditingController(text: b.phone);
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit branch'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: address,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Address', helperText: 'Printed on bills'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'Phone', helperText: 'Printed on bills'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    final values = (name.text, address.text, phone.text);
    for (final c in [name, address, phone]) {
      c.dispose();
    }
    if (save != true || values.$1.trim().isEmpty) return;
    await _run(() => _branchService.updateBranch(b,
        name: values.$1, address: values.$2, phone: values.$3));
  }

  Widget _simpleList(LookupKind kind) {
    final items = _lookups.of(kind);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _addTile('Add ${kind.label.toLowerCase()}', () => _add(kind)),
        const Divider(height: 1),
        for (final item in items) _itemTile(kind, item),
      ],
    );
  }

  Widget _modelsList() {
    if (_lookups.brands.isEmpty) {
      return const Center(child: Text('Add a brand first'));
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final brand in _lookups.brands) ...[
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(brand.name,
                style: Theme.of(context).textTheme.titleSmall),
          ),
          for (final model in _lookups.modelsOf(brand.id))
            _itemTile(LookupKind.model, model),
          _addTile('Add ${brand.name} model',
              () => _add(LookupKind.model, brand: brand)),
        ],
      ],
    );
  }

  Widget _addTile(String label, VoidCallback onTap) => ListTile(
        leading: const Icon(Icons.add_circle_outline),
        title: Text(label),
        textColor: Theme.of(context).colorScheme.primary,
        iconColor: Theme.of(context).colorScheme.primary,
        onTap: onTap,
      );

  Widget _itemTile(LookupKind kind, LookupItem item) => ListTile(
        title: Text(item.name),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Rename',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _rename(kind, item),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(kind, item),
            ),
          ],
        ),
      );
}
