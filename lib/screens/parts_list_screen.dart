import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/part.dart';
import '../services/parts_service.dart';
import 'part_form_screen.dart';

class PartsListScreen extends StatefulWidget {
  const PartsListScreen({super.key});

  @override
  State<PartsListScreen> createState() => _PartsListScreenState();
}

class _PartsListScreenState extends State<PartsListScreen> {
  final _service = PartsService();
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<Part> _parts = [];
  bool _loading = true;
  bool _lowStockOnly = false;
  String? _error;

  @override
  void initState() {
    super.initState();
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
      final parts = await _service.fetchParts(search: _searchController.text);
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
        title: const Text('Stock'),
        actions: [
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
                hintText: 'Search name, part no, brand, bike model',
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                FilterChip(
                  label: Text('Low stock ($lowCount)'),
                  selected: _lowStockOnly,
                  onSelected: (v) => setState(() => _lowStockOnly = v),
                ),
                const Spacer(),
                Text('${visible.length} items'),
              ],
            ),
          ),
          Expanded(child: _buildBody(visible)),
        ],
      ),
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
    final subtitle = [part.partNo, part.brand, part.bikeModel]
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
