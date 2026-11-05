import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/branch.dart';
import '../models/lookup.dart';
import '../models/part.dart';
import '../models/profile.dart';
import '../services/branch_service.dart';
import '../services/lookup_service.dart';
import '../services/parts_service.dart';
import '../utils/money.dart';
import '../widgets/transfer_sheet.dart';
import 'manage_lookups_screen.dart';
import 'part_form_screen.dart';
import 'transfers_screen.dart';
import 'users_screen.dart';
import 'bills_screen.dart';
import 'new_bill_screen.dart';
import 'to_collect_screen.dart';

class PartsListScreen extends StatefulWidget {
  const PartsListScreen({super.key, required this.profile});

  /// The signed-in user's role; decides which actions are shown.
  final UserProfile profile;

  @override
  State<PartsListScreen> createState() => _PartsListScreenState();
}

class _PartsListScreenState extends State<PartsListScreen> {
  final _service = PartsService();
  final _lookupService = LookupService();
  final _branchService = BranchService();
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<Part> _parts = [];
  Lookups _lookups = const Lookups();
  List<Branch> _branches = [];
  // The branch this device is working in.
  String? _branchId;
  // Active filters, keyed by list kind.
  final Map<LookupKind, String?> _filters = {};
  bool _loading = true;
  bool _lowStockOnly = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBranches();
    _loadLookups();
    _load();
  }

  Branch? get _branch => _branches.where((b) => b.id == _branchId).firstOrNull;

  bool get _isSuperAdmin => widget.profile.isSuperAdmin;

  Future<void> _loadBranches() async {
    try {
      final branches = await _branchService.fetchBranches();
      // Admins always work in their own branch.
      final saved = _isSuperAdmin
          ? _branchId ?? await _branchService.loadSelectedBranchId()
          : widget.profile.branchId;
      if (!mounted) return;
      setState(() {
        _branches = branches;
        _branchId = branches.any((b) => b.id == saved)
            ? saved
            : branches.firstOrNull?.id; // main branch comes first
      });
    } catch (_) {
      // The stock list shows its own error if the database is unreachable.
    }
  }

  Future<void> _pickBranch() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Working in branch')),
            for (final b in _branches)
              ListTile(
                leading: Icon(b.isMain ? Icons.store : Icons.storefront_outlined),
                title: Text(b.name),
                subtitle: b.isMain ? const Text('Main branch') : null,
                selected: b.id == _branchId,
                onTap: () => Navigator.pop(context, b.id),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == _branchId) return;
    setState(() => _branchId = picked);
    _branchService.saveSelectedBranchId(picked);
  }

  Future<void> _transfer(Part part) async {
    if (!_isSuperAdmin || _branches.length < 2) return;
    final done = await showTransferSheet(context,
        part: part, branches: _branches, fromBranchId: _branchId);
    if (done != null) _load();
  }

  Future<void> _openTransfers() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TransfersScreen()),
    );
  }

  Future<void> _openUsers() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const UsersScreen()),
    );
  }

  // Bills change stock, so the list reloads after both of these.
  Future<void> _openBills() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          BillsScreen(branch: _branch!, isSuperAdmin: _isSuperAdmin),
    ));
    _load();
  }

  Future<void> _openToCollect() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          ToCollectScreen(branch: _branch!, isSuperAdmin: _isSuperAdmin),
    ));
  }

  Future<void> _newBill() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          NewBillScreen(branch: _branch!, isSuperAdmin: _isSuperAdmin),
    ));
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
    await _loadBranches();
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
      MaterialPageRoute(
        builder: (_) => PartFormScreen(
          part: part,
          branches: _branches,
          branchId: _branchId,
          isSuperAdmin: _isSuperAdmin,
        ),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _adjust(Part part, int delta) async {
    final branchId = _branchId;
    if (branchId == null) return;
    try {
      await _branchService.adjustStock(part.id!, branchId, delta);
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
    final low = _parts.where((p) => p.isLowStockAt(_branchId)).toList();
    final visible = _lowStockOnly ? low : _parts;
    final lowCount = low.length;

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
            tooltip: 'Bills',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: _branch == null ? null : _openBills,
          ),
          IconButton(
            tooltip: 'To collect',
            icon: const Icon(Icons.account_balance_wallet_outlined),
            onPressed: _branch == null ? null : _openToCollect,
          ),
          PopupMenuButton<VoidCallback>(
            tooltip: 'More',
            onSelected: (action) => action(),
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: Text(widget.profile.role.label),
                  subtitle: Text(
                      Supabase.instance.client.auth.currentUser?.email ?? ''),
                ),
              ),
              const PopupMenuDivider(),
              if (_isSuperAdmin) ...[
                PopupMenuItem(
                  value: _openManageLists,
                  child: const ListTile(
                    leading: Icon(Icons.list_alt),
                    title: Text('Lists & branches'),
                  ),
                ),
                PopupMenuItem(
                  value: _openUsers,
                  child: const ListTile(
                    leading: Icon(Icons.manage_accounts_outlined),
                    title: Text('Users'),
                  ),
                ),
                PopupMenuItem(
                  value: _openTransfers,
                  child: const ListTile(
                    leading: Icon(Icons.swap_horiz),
                    title: Text('Transfer history'),
                  ),
                ),
              ],
              PopupMenuItem(
                value: () => Supabase.instance.client.auth.signOut(),
                child: const ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('Sign out'),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'add-part',
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add),
            label: const Text('Add part'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'new-bill',
            onPressed: _branch == null ? null : _newBill,
            icon: const Icon(Icons.receipt_long),
            label: const Text('New bill'),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: InkWell(
              onTap: _branches.length > 1 ? _pickBranch : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.place_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(TextSpan(children: [
                        const TextSpan(text: 'Branch: '),
                        TextSpan(
                          text: _branch?.name ?? '…',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ])),
                    ),
                    if (_branches.length > 1) ...[
                      const Text('Change'),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ],
                ),
              ),
            ),
          ),
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
          branchId: _branchId,
          otherBranches: _branches.where((b) => b.id != _branchId).toList(),
          imageUrl: parts[i].images.isEmpty
              ? null
              : _service.imageUrl(parts[i].images.first),
          onTap: () => _openForm(parts[i]),
          onLongPress: () => _transfer(parts[i]),
          onAdjust: (delta) => _adjust(parts[i], delta),
        ),
      ),
    );
  }
}

class _PartTile extends StatelessWidget {
  const _PartTile({
    required this.part,
    required this.branchId,
    required this.otherBranches,
    required this.imageUrl,
    required this.onTap,
    required this.onLongPress,
    required this.onAdjust,
  });

  final Part part;
  final String? branchId;
  final List<Branch> otherBranches;
  final String? imageUrl;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<int> onAdjust;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final quantity = part.quantityAt(branchId);
    final isLow = part.isLowStockAt(branchId);
    final subtitle = [
      part.partNo,
      [part.brandName, part.bikeModelName].whereType<String>().join(' '),
      part.categoryName,
    ]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' • ');
    final elsewhere = [
      for (final b in otherBranches) '${b.name} ${part.quantityAt(b.id)}',
    ].join(' • ');

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
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
        '${formatMoney(part.sellPrice)}'
        '${elsewhere.isEmpty ? '' : '\nOther: $elsewhere'}',
      ),
      isThreeLine: subtitle.isNotEmpty || elsewhere.isNotEmpty,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Remove one',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: quantity > 0 ? () => onAdjust(-1) : null,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isLow ? scheme.errorContainer : scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$quantity',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isLow
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
