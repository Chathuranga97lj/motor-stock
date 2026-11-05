import 'package:flutter/material.dart';

import '../models/bill.dart';
import '../models/branch.dart';
import '../services/bill_service.dart';
import '../utils/money.dart';
import '../theme.dart';
import 'bill_detail_screen.dart';
import 'new_bill_screen.dart';

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
  _Period _period = _Period.today;
  List<Bill> _bills = [];
  // Money received in the period, including payments on older credit bills.
  double _collected = 0;
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
      final (bills, collected) = await (
        _service.fetchBills(branchId: widget.branch.id, from: _period.from),
        _service.fetchCollected(branchId: widget.branch.id, from: _period.from),
      ).wait;
      if (mounted) {
        setState(() {
          _bills = bills;
          _collected = collected;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load bills: $e');
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
    final completed = _bills.where((b) => !b.cancelled);
    final total = completed.fold(0.0, (sum, b) => sum + b.total);
    // Before bill discounts.
    final parts = completed.fold(0.0, (sum, b) => sum + b.partsTotal);
    final service = completed.fold(0.0, (sum, b) => sum + b.servicesTotal);

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
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: _totalCard(
                    theme,
                    label: 'Sales',
                    value: total,
                    note:
                        '${completed.length} bills'
                        '${_bills.length > completed.length ? ', ${_bills.length - completed.length} cancelled' : ''}',
                    color: theme.colorScheme.primaryContainer,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _totalCard(
                    theme,
                    label: 'Collected',
                    value: _collected,
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
                Text('Parts ${formatMoney(parts)}'),
                const SizedBox(width: 16),
                const Icon(Icons.build_outlined, size: 16),
                const SizedBox(width: 4),
                Text('Service ${formatMoney(service)}'),
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
                    b.cancelled ? 'Cancelled' : formatMoney(b.total),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: b.cancelled ? scheme.error : null,
                    ),
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
