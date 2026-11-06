import 'package:flutter/material.dart';

import '../models/bill.dart';
import '../models/branch.dart';
import '../models/purchase.dart';
import '../services/purchase_service.dart';
import '../utils/money.dart';
import '../theme.dart';
import 'purchase_detail_screen.dart';
import 'stock_in_screen.dart';

enum _Period {
  today('Today'),
  week('7 days'),
  month('30 days'),
  all('All');

  const _Period(this.label);
  final String label;

  DateTime? get from {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      _Period.today => today,
      _Period.week => today.subtract(const Duration(days: 6)),
      _Period.month => today.subtract(const Duration(days: 29)),
      _Period.all => null,
    };
  }
}

/// Stock-in history of [branch], with Purchased and Paid totals.
class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({
    super.key,
    required this.branch,
    this.isSuperAdmin = false,
  });

  final Branch branch;
  final bool isSuperAdmin;

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  final _service = PurchaseService();
  _Period _period = _Period.month;
  List<Supplier> _suppliers = [];
  String? _supplierId;
  List<Purchase> _purchases = [];
  double _paid = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service
        .fetchSuppliers()
        .then((s) {
          if (mounted) setState(() => _suppliers = s);
        })
        .catchError((_) {});
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final (purchases, paid) = await (
        _service.fetchPurchases(
          branchId: widget.branch.id,
          from: _period.from,
          supplierId: _supplierId,
        ),
        _service.fetchPaid(
          branchId: widget.branch.id,
          from: _period.from,
          supplierId: _supplierId,
        ),
      ).wait;
      if (mounted) {
        setState(() {
          _purchases = purchases;
          _paid = paid;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load stock-ins: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = _purchases.where((p) => !p.cancelled);
    final purchased = roundMoney(active.fold(0.0, (s, p) => s + p.total));

    return Scaffold(
      appBar: AppBar(title: Text('Stock-ins • ${widget.branch.name}')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'stock-in',
        onPressed: () => _open(
          StockInScreen(
            branch: widget.branch,
            isSuperAdmin: widget.isSuperAdmin,
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Stock in'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: SegmentedButton<_Period>(
              segments: [
                for (final p in _Period.values)
                  ButtonSegment(value: p, label: Text(p.label)),
              ],
              selected: {_period},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                setState(() => _period = s.first);
                _load();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: DropdownButtonFormField<String?>(
              initialValue: _supplierId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Supplier',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All suppliers'),
                ),
                for (final s in _suppliers)
                  DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
              ],
              onChanged: (id) {
                setState(() => _supplierId = id);
                _load();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: _totalCard(
                    theme,
                    'Purchased',
                    purchased,
                    '${active.length} stock-ins',
                    theme.colorScheme.primaryContainer,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _totalCard(
                    theme,
                    'Paid to suppliers',
                    _paid,
                    'money given',
                    theme.colorScheme.secondaryContainer,
                  ),
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(child: _list()),
        ],
      ),
    );
  }

  Widget _totalCard(
    ThemeData theme,
    String label,
    double value,
    String note,
    Color color,
  ) {
    return Card(
      margin: EdgeInsets.zero,
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelLarge),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatMoney(value),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(note, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _list() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_purchases.isEmpty && !_loading) {
      return const Center(child: Text('No stock-ins in this period'));
    }
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: _purchases.length,
        itemBuilder: (context, i) {
          final p = _purchases[i];
          return TileCard(
            child: ListTile(
              leading: Icon(
                p.cancelled
                    ? Icons.cancel_outlined
                    : Icons.inventory_2_outlined,
                color: p.cancelled ? scheme.error : scheme.primary,
              ),
              title: Text(p.supplierName),
              subtitle: Text(
                [
                  p.purchaseNo,
                  if (p.invoiceNo != null) 'Inv ${p.invoiceNo}',
                  formatDateTime(p.createdAt).substring(0, 10),
                  if (!p.cancelled) p.paymentStatus.label,
                ].join(' • '),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    p.cancelled ? 'Cancelled' : formatMoney(p.total),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: p.cancelled ? scheme.error : null,
                    ),
                  ),
                  if (p.hasBalance)
                    Text(
                      'To pay ${formatMoney(p.balance)}',
                      style: TextStyle(fontSize: 12, color: scheme.error),
                    ),
                ],
              ),
              onTap: () => _open(
                PurchaseDetailScreen(
                  purchaseId: p.id,
                  isSuperAdmin: widget.isSuperAdmin,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
