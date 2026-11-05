import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/lookup.dart';
import '../models/part.dart';
import '../services/lookup_service.dart';
import '../services/parts_service.dart';
import 'manage_lookups_screen.dart';
import 'part_form_screen.dart';

class PartsListScreen extends StatefulWidget {
  const PartsListScreen({super.key});

  @override
  State<PartsListScreen> createState() => _PartsListScreenState();
}

class _PartsListScreenState extends State<PartsListScreen> {
  final _service = PartsService();
  final _lookupService = LookupService();
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<Part> _parts = [];
  Lookups _lookups = const Lookups();
  // Active filters, keyed by list kind.
  final Map<LookupKind, String?> _filters = {};
  bool _loading = true;
  bool _lowStockOnly = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLookups();
    _load();
  }

  Future<void> _loadLookups() async {
    try {
      final lookups = await _lookupService.fetchAll();
      if (!mounted) return;
      setState(() {
        _lookups = lookups;
        // Drop filters whose entry was deleted.
        _filters.removeWhere(
            (kind, id) => !lookups.of(kind).any((i) => i.id == id));
      });
    } catch (_) {
      // Filters just stay empty; the stock list shows its own error.
    }
  }

  Future<void> _pickFilter(LookupKind kind) async {
    final items = kind == LookupKind.model
        ? _lookups.modelsOf(_filters[LookupKind.brand])
        : _lookups.of(kind);
    // Wrapped so "All" (null) is distinguishable from dismissing the sheet.
    final picked = await showModalBottomSheet<({String? id})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.6),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text('All ${kind.pluralLabel.toLowerCase()}'),
                onTap: () => Navigator.pop(context, (id: null)),
              ),
              for (final item in items)
                ListTile(
                  title: Text(item.name),
                  selected: item.id == _filters[kind],
                  onTap: () => Navigator.pop(context, (id: item.id)),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    _setFilter(kind, picked.id);
  }

  void _setFilter(LookupKind kind, String? id) {
    setState(() {
      _filters[kind] = id;
      if (kind == LookupKind.brand) _filters.remove(LookupKind.model);
    });
    _load();
  }

  Future<void> _openManageLists() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ManageLookupsScreen()),
    );
    await _loadLookups();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final parts = await _service.fetchParts(
        search: _searchController.text,
        categoryId: _filters[LookupKind.category],
        brandId: _filters[LookupKind.brand],
        bikeModelId: _filters[LookupKind.model],
      );
      if (mounted) setState(() => _parts = parts);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load stock: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  Future<void> _openForm([Part? part]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PartFormScreen(part: part)),
    );
    // The form may have added categories, brands or models.
    await _loadLookups();
    if (changed == true) _load();
  }

  Future<void> _adjust(Part part, int delta) async {
    try {
      await _service.adjustQuantity(part, delta);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible =
        _lowStockOnly ? _parts.where((p) => p.isLowStock).toList() : _parts;
    final lowCount = _parts.where((p) => p.isLowStock).length;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/branding/logo_mark.png', width: 32, height: 32),
            const SizedBox(width: 10),
            const Text('OSHU Stock'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Categories, brands & models',
            icon: const Icon(Icons.list_alt),
            onPressed: _openManageLists,
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add part'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search name or part no',
                isDense: true,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                FilterChip(
                  label: Text('Low stock ($lowCount)'),
                  selected: _lowStockOnly,
                  onSelected: (v) => setState(() => _lowStockOnly = v),
                ),
                for (final kind in LookupKind.values)
                  if (kind != LookupKind.model ||
                      _filters[LookupKind.brand] != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _filterChip(kind),
                    ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('${visible.length} items',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ),
          Expanded(child: _buildBody(visible)),
        ],
      ),
    );
  }

  Widget _filterChip(LookupKind kind) {
    final id = _filters[kind];
    final name =
        _lookups.of(kind).where((i) => i.id == id).map((i) => i.name).firstOrNull;
    return InputChip(
      label: Text(name ?? kind.label),
      avatar: name == null ? const Icon(Icons.arrow_drop_down) : null,
      selected: name != null,
      showCheckmark: false,
      onPressed: () => _pickFilter(kind),
      onDeleted: name == null ? null : () => _setFilter(kind, null),
    );
  }

  Widget _buildBody(List<Part> parts) {
    if (_loading && _parts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, textAlign: TextAlign.center),
            ),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (parts.isEmpty) {
      return const Center(child: Text('No parts found'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: parts.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) => _PartTile(
          part: parts[i],
          imageUrl: parts[i].images.isEmpty
              ? null
              : _service.imageUrl(parts[i].images.first),
          onTap: () => _openForm(parts[i]),
          onAdjust: (delta) => _adjust(parts[i], delta),
        ),
      ),
    );
  }
}

class _PartTile extends StatelessWidget {
  const _PartTile({
    required this.part,
    required this.imageUrl,
    required this.onTap,
    required this.onAdjust,
  });

  final Part part;
  final String? imageUrl;
  final VoidCallback onTap;
  final ValueChanged<int> onAdjust;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = [
      part.partNo,
      [part.brandName, part.bikeModelName].whereType<String>().join(' '),
      part.categoryName,
    ]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' • ');

    return ListTile(
      onTap: onTap,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 56,
          height: 56,
          child: imageUrl == null
              ? ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: const Icon(Icons.image_not_supported_outlined),
                )
              : Image.network(imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(Icons.broken_image)),
        ),
      ),
      title: Text(part.name),
      subtitle: Text(
        '${subtitle.isEmpty ? '' : '$subtitle\n'}'
        'Price ${part.sellPrice.toStringAsFixed(2)}',
      ),
      isThreeLine: subtitle.isNotEmpty,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Remove one',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: part.quantity > 0 ? () => onAdjust(-1) : null,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: part.isLowStock
                  ? scheme.errorContainer
                  : scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${part.quantity}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: part.isLowStock
                    ? scheme.onErrorContainer
                    : scheme.onSecondaryContainer,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Add one',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => onAdjust(1),
          ),
        ],
      ),
    );
  }
}
