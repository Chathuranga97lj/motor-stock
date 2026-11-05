import 'package:flutter/material.dart';

import '../models/bill.dart';
import '../models/purchase.dart';
import '../services/purchase_service.dart';
import '../theme.dart';
import '../utils/money.dart';
import 'purchase_detail_screen.dart';

/// Super admin: what is still owed to suppliers, all branches, by supplier.
class ToPayScreen extends StatefulWidget {
  const ToPayScreen({super.key});

  @override
  State<ToPayScreen> createState() => _ToPayScreenState();
}

class _ToPayScreenState extends State<ToPayScreen> {
  final _service = PurchaseService();
  List<Purchase> _purchases = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final purchases = await _service.fetchToPay();
      if (mounted) {
        setState(() {
          _purchases = purchases;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Purchase p) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PurchaseDetailScreen(purchaseId: p.id, isSuperAdmin: true),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final owed = roundMoney(_purchases.fold(0.0, (s, p) => s + p.balance));

    // Group by supplier, biggest debt first.
    final bySupplier = <String, List<Purchase>>{};
    for (final p in _purchases) {
      bySupplier.putIfAbsent(p.supplierId, () => []).add(p);
    }
    double owedTo(List<Purchase> list) =>
        roundMoney(list.fold(0.0, (s, p) => s + p.balance));
    final groups = bySupplier.values.toList()
      ..sort((a, b) => owedTo(b).compareTo(owedTo(a)));

    return Scaffold(
      appBar: AppBar(title: const Text('To pay suppliers')),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            color: theme.colorScheme.errorContainer,
            child: ListTile(
              leading: Icon(
                Icons.local_shipping_outlined,
                color: theme.colorScheme.onErrorContainer,
              ),
              title: Text(
                formatMoney(owed),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              subtitle: Text(
                '${_purchases.length} invoices • ${groups.length} suppliers • all branches',
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
                  )
                : groups.isEmpty && !_loading
                ? const Center(child: Text('Nothing owed to suppliers 🎉'))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      children: [
                        for (final list in groups)
                          TileCard(
                            child: ExpansionTile(
                              shape: const Border(),
                              collapsedShape: const Border(),
                              leading: const Icon(
                                Icons.local_shipping_outlined,
                              ),
                              initiallyExpanded: groups.length <= 3,
                              title: Text(
                                list.first.supplierName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  if (list.first.supplierPhone != null)
                                    list.first.supplierPhone!,
                                  '${list.length} invoice${list.length == 1 ? '' : 's'}',
                                ].join(' • '),
                              ),
                              trailing: Text(
                                formatMoney(owedTo(list)),
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              children: [
                                for (final p in list)
                                  ListTile(
                                    contentPadding: const EdgeInsets.only(
                                      left: 32,
                                      right: 16,
                                    ),
                                    title: Text(
                                      'Inv ${p.invoiceNo ?? '-'} • ${p.purchaseNo}',
                                    ),
                                    subtitle: Text(
                                      [
                                        p.branchName,
                                        p.daysOld == 0
                                            ? 'today'
                                            : '${p.daysOld} days ago',
                                        if (p.amountPaid > 0)
                                          'paid ${formatMoney(p.amountPaid)} of ${formatMoney(p.total)}',
                                      ].join(' • '),
                                    ),
                                    trailing: Text(formatMoney(p.balance)),
                                    onTap: () => _open(p),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
