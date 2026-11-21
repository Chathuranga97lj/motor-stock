import 'package:flutter/material.dart';

import '../models/bill.dart';
import '../models/branch.dart';
import '../models/totals.dart';
import '../services/bill_service.dart';
import '../utils/latest_request.dart';
import '../utils/money.dart';
import '../theme.dart';
import '../utils/period.dart';
import 'bill_detail_screen.dart';
import 'new_bill_screen.dart';

/// Bills issued at [branch], with the total for the chosen period.
class BillsScreen extends StatefulWidget {
  const BillsScreen({
    super.key,
    required this.branch,
    this.isSuperAdmin = false,
  });

  final Branch branch;
  final bool isSuperAdmin;

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  final _service = BillService();
  ReportPeriod _period = ReportPeriod.today;
  List<Bill> _bills = [];
  // Collected = money received in the period, including payments on older
  // credit bills.
  BillTotals _totals = const BillTotals();
  bool _loading = true;
  String? _error;
  final _latest = LatestRequest();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = _latest.start();
    setState(() => _loading = true);
    try {
      final branchId = widget.branch.id;
      final from = _period.from;
      final (bills, totals) = await (
        _service.fetchBills(branchId: branchId, from: from),
        _service.fetchTotals(branchId: branchId, from: from)
            .catchError((_) => null),
      ).wait;
      // Without migration 013 (or if the totals fail), add up on the phone.
      final t = totals ??
          BillTotals.fromBills(bills,
              collected: await _service.fetchCollected(
                  branchId: branchId, from: from));
      if (mounted && _latest.isLatest(request)) {
        setState(() {
          _bills = bills;
          _totals = t;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _latest.isLatest(request)) {
        setState(() => _error = 'Could not load bills: $e');
      }
    } finally {
      if (mounted && _latest.isLatest(request)) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = _totals;

    return Scaffold(
      appBar: AppBar(title: Text('Bills • ${widget.branch.name}')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-bill',
        onPressed: () => _open(
          NewBillScreen(
            branch: widget.branch,
            isSuperAdmin: widget.isSuperAdmin,
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New bill'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: SegmentedButton<ReportPeriod>(
              segments: [
                for (final p in ReportPeriod.values)
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
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: _totalCard(
                    theme,
                    label: 'Sales',
                    // After returns.
                    value: t.sales,
                    note:
                        '${t.bills} bills'
                        '${t.cancelled > 0 ? ', ${t.cancelled} cancelled' : ''}',
                    color: theme.colorScheme.primaryContainer,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _totalCard(
                    theme,
                    label: 'Collected',
                    value: t.collected,
                    note: 'money received',
                    color: theme.colorScheme.secondaryContainer,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_outlined, size: 16),
                const SizedBox(width: 4),
                // Before bill discounts.
                Text('Parts ${formatMoney(t.parts)}'),
                const SizedBox(width: 16),
                const Icon(Icons.build_outlined, size: 16),
                const SizedBox(width: 4),
                Text('Service ${formatMoney(t.services)}'),
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
    ThemeData theme, {
    required String label,
    required double value,
    required String note,
    required Color color,
  }) {
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
    if (_bills.isEmpty && !_loading) {
      return const Center(child: Text('No bills in this period'));
    }
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: _bills.length,
        itemBuilder: (context, i) {
          final b = _bills[i];
          return TileCard(
            child: ListTile(
              leading: Icon(
                b.cancelled ? Icons.cancel_outlined : Icons.receipt_long,
                color: b.cancelled ? scheme.error : scheme.primary,
              ),
              title: Text(b.billNo),
              subtitle: Text(
                [
                  formatDateTime(b.createdAt),
                  if (b.customerName != null) b.customerName!,
                  if (!b.cancelled) b.paymentStatus.label,
                ].join(' • '),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    b.cancelled ? 'Cancelled' : formatMoney(b.netTotal),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: b.cancelled ? scheme.error : null,
                    ),
                  ),
                  if (!b.cancelled && b.hasReturns)
                    Text(
                      'Returned ${formatMoney(b.returnedTotal)}',
                      style: const TextStyle(fontSize: 12, color: Brand.muted),
                    ),
                  if (b.hasBalance)
                    Text(
                      'Due ${formatMoney(b.balance)}',
                      style: TextStyle(fontSize: 12, color: scheme.error),
                    ),
                ],
              ),
              onTap: () => _open(
                BillDetailScreen(
                  billId: b.id,
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
