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
import '../theme.dart';
import '../utils/money.dart';
import '../widgets/barcode_scanner.dart';
import '../widgets/transfer_sheet.dart';
import 'manage_lookups_screen.dart';
import 'part_form_screen.dart';
import 'transfers_screen.dart';
import 'users_screen.dart';
import 'bills_screen.dart';
import 'new_bill_screen.dart';
import 'to_collect_screen.dart';
import 'purchases_screen.dart';
import 'stock_in_screen.dart';
import 'to_pay_screen.dart';

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
                leading: Icon(
                  b.isMain ? Icons.store : Icons.storefront_outlined,
                ),
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
    final done = await showTransferSheet(
      context,
      part: part,
      branches: _branches,
      fromBranchId: _branchId,
    );
    if (done != null) _load();
  }

  Future<void> _openTransfers() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const TransfersScreen()));
  }

  Future<void> _openUsers() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const UsersScreen()));
  }

  // Bills change stock, so the list reloads after both of these.
  Future<void> _openBills() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            BillsScreen(branch: _branch!, isSuperAdmin: _isSuperAdmin),
      ),
    );
    _load();
  }

  Future<void> _openToCollect() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ToCollectScreen(branch: _branch!, isSuperAdmin: _isSuperAdmin),
      ),
    );
  }

  // Stock-ins change stock, so the list reloads afterwards.
  Future<void> _stockIn() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            StockInScreen(branch: _branch!, isSuperAdmin: _isSuperAdmin),
      ),
    );
    _load();
  }

  Future<void> _openPurchases() async {
    if (_branch == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PurchasesScreen(branch: _branch!, isSuperAdmin: _isSuperAdmin),
      ),
    );
    _load();
  }

  Future<void> _openToPay() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ToPayScreen()));
  }

  Future<void> _newBill() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            NewBillScreen(branch: _branch!, isSuperAdmin: _isSuperAdmin),
      ),
    );
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
          (kind, id) => !lookups.of(kind).any((i) => i.id == id),
        );
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
            maxHeight: MediaQuery.sizeOf(context).height * 0.6,
          ),
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
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ManageLookupsScreen()));
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

  /// Scan a code from the search box: opens the matching part, or searches
  /// for the code when no part has it.
  Future<void> _scanSearch() async {
    final code = await scanCode(context, title: 'Find a part');
    if (code == null || !mounted) return;
    Part? part;
    try {
      part = await _service.findByBarcode(code);
    } catch (_) {
      // Fall back to a text search below.
    }
    if (!mounted) return;
    if (part != null) {
      await _openForm(part);
      return;
    }
    _searchController.text = code;
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No part has the code $code yet. Open a part and '
              'scan it into Barcode / QR to link it.')));
    }
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
    final outCount = _parts.where((p) => p.quantityAt(_branchId) == 0).length;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/branding/logo_mark.png', width: 34, height: 34),
            const SizedBox(width: 10),
            const Text('OSHU Stock'),
          ],
        ),
        actions: [
          PopupMenuButton<VoidCallback>(
            tooltip: 'More',
            icon: const Icon(Icons.menu_rounded),
            onSelected: (action) => action(),
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: Text(widget.profile.role.label),
                  subtitle: Text(
                    Supabase.instance.client.auth.currentUser?.email ?? '',
                  ),
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
                PopupMenuItem(
                  value: _openToPay,
                  child: const ListTile(
                    leading: Icon(Icons.local_shipping_outlined),
                    title: Text('To pay suppliers'),
                  ),
                ),
              ],
              PopupMenuItem(
                value: _openPurchases,
                child: const ListTile(
                  leading: Icon(Icons.inventory_2_outlined),
                  title: Text('Stock-in history'),
                ),
              ),
              PopupMenuItem(
                value: () => _openForm(),
                child: const ListTile(
                  leading: Icon(Icons.add_box_outlined),
                  title: Text('Add part (no stock-in)'),
                ),
              ),
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
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-bill',
        onPressed: _branch == null ? null : _newBill,
        icon: const Icon(Icons.receipt_long),
        label: const Text('New bill'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: _header(low.length, outCount),
              ),
            ),
            SliverToBoxAdapter(
              child: _searchAndFilters(low.length, visible.length),
            ),
            ..._listSlivers(visible),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }

  /// Branch, stock summary and quick actions on the brand gradient.
  Widget _header(int lowCount, int outCount) {
    final canChange = _branches.length > 1;
    return BrandHeader(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: canChange ? _pickBranch : null,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.storefront, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _branch?.isMain == true ? 'Main branch' : 'Branch',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                        ),
                      ),
                      Text(
                        _branch?.name ?? '…',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                if (canChange)
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Change',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Icon(Icons.arrow_drop_down, color: Colors.white),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _headerStat(
                'Parts',
                '${_parts.length}',
                Icons.inventory_2_outlined,
                Colors.white,
              ),
              const SizedBox(width: 8),
              _headerStat(
                'Low stock',
                '$lowCount',
                Icons.warning_amber_rounded,
                Brand.yellow,
                onTap: () => setState(() => _lowStockOnly = !_lowStockOnly),
              ),
              const SizedBox(width: 8),
              _headerStat(
                'Out of stock',
                '$outCount',
                Icons.remove_shopping_cart_outlined,
                const Color(0xFFFF9C94),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _QuickAction(
                icon: Icons.receipt_long,
                label: 'New bill',
                color: Brand.red,
                onTap: _branch == null ? null : _newBill,
              ),
              _QuickAction(
                icon: Icons.inventory_2_outlined,
                label: 'Stock in',
                color: Brand.blue,
                onTap: _branch == null ? null : _stockIn,
              ),
              _QuickAction(
                icon: Icons.history,
                label: 'Bills',
                color: Brand.navy,
                onTap: _branch == null ? null : _openBills,
              ),
              _QuickAction(
                icon: Icons.account_balance_wallet_outlined,
                label: 'To collect',
                color: Brand.green,
                onTap: _branch == null ? null : _openToCollect,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerStat(
    String label,
    String value,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchAndFilters(int lowCount, int visibleCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, color: Brand.blue),
              hintText: 'Search name, part no or code',
              suffixIcon: _searchController.text.isEmpty
                  ? IconButton(
                      tooltip: 'Scan barcode / QR',
                      icon: const Icon(Icons.qr_code_scanner, color: Brand.blue),
                      onPressed: _scanSearch,
                    )
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchController.clear();
                        _load();
                        setState(() {});
                      },
                    ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  avatar: const Icon(Icons.warning_amber_rounded, size: 18),
                  label: Text('Low stock ($lowCount)'),
                  selected: _lowStockOnly,
                  showCheckmark: false,
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
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                _lowStockOnly ? 'Low stock parts' : 'Parts',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Brand.ink,
                ),
              ),
              const Spacer(),
              Text(
                '$visibleCount items',
                style: const TextStyle(color: Brand.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChip(LookupKind kind) {
    final id = _filters[kind];
    final name = _lookups
        .of(kind)
        .where((i) => i.id == id)
        .map((i) => i.name)
        .firstOrNull;
    return InputChip(
      label: Text(name ?? kind.label),
      avatar: name == null ? const Icon(Icons.arrow_drop_down) : null,
      selected: name != null,
      showCheckmark: false,
      onPressed: () => _pickFilter(kind),
      onDeleted: name == null ? null : () => _setFilter(kind, null),
    );
  }

  List<Widget> _listSlivers(List<Part> parts) {
    Widget fill(Widget child) => SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(padding: const EdgeInsets.all(24), child: child),
      ),
    );
    if (_loading && _parts.isEmpty) {
      return [fill(const CircularProgressIndicator())];
    }
    if (_error != null) {
      return [
        fill(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: Brand.muted),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      ];
    }
    if (parts.isEmpty) {
      return [
        fill(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 48, color: Brand.muted),
              SizedBox(height: 8),
              Text('No parts found', style: TextStyle(color: Brand.muted)),
            ],
          ),
        ),
      ];
    }
    final others = _branches.where((b) => b.id != _branchId).toList();
    return [
      SliverList.builder(
        itemCount: parts.length,
        itemBuilder: (context, i) => _PartCard(
          part: parts[i],
          branchId: _branchId,
          otherBranches: others,
          imageUrl: parts[i].images.isEmpty
              ? null
              : _service.imageUrl(parts[i].images.first),
          onTap: () => _openForm(parts[i]),
          onLongPress: () => _transfer(parts[i]),
          onAdjust: (delta) => _adjust(parts[i], delta),
        ),
      ),
    ];
  }
}

/// A round shortcut button on the home header.
class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, color: color, size: 27),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PartCard extends StatelessWidget {
  const _PartCard({
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
    final quantity = part.quantityAt(branchId);
    final isLow = part.isLowStockAt(branchId);
    final stockColor = quantity == 0
        ? Brand.red
        : isLow
        ? const Color(0xFFE08A00)
        : Brand.green;
    final details = [
      part.partNo,
      [part.brandName, part.bikeModelName].whereType<String>().join(' '),
      part.categoryName,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' • ');
    final elsewhere = [
      for (final b in otherBranches) '${b.name} ${part.quantityAt(b.id)}',
    ].join(' • ');

    return TileCard(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 70,
                height: 70,
                child: imageUrl == null
                    ? ColoredBox(
                        color: Brand.blue.withValues(alpha: 0.08),
                        child: const Icon(
                          Icons.two_wheeler,
                          color: Brand.blue,
                          size: 32,
                        ),
                      )
                    : Image.network(
                        imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.broken_image),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    part.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Brand.ink,
                    ),
                  ),
                  if (details.isNotEmpty)
                    Text(
                      details,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Brand.muted,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Brand.blue.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      formatMoney(part.sellPrice),
                      style: const TextStyle(
                        color: Brand.blue,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (elsewhere.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Other: $elsewhere',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Brand.muted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            Column(
              children: [
                Container(
                  width: 64,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: stockColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$quantity',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: stockColor,
                        ),
                      ),
                      Text(
                        quantity == 0 ? 'out' : 'in stock',
                        style: TextStyle(fontSize: 10.5, color: stockColor),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _stepButton(
                      Icons.remove,
                      'Remove one',
                      quantity > 0 ? () => onAdjust(-1) : null,
                    ),
                    _stepButton(Icons.add, 'Add one', () => onAdjust(1)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepButton(IconData icon, String tooltip, VoidCallback? onPressed) =>
      IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        iconSize: 20,
        color: Brand.blue,
        icon: Icon(icon),
        onPressed: onPressed,
      );
}
