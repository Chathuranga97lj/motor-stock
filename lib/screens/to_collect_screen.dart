import 'dart:async';

import 'package:flutter/material.dart';

import '../models/bill.dart';
import '../models/branch.dart';
import '../services/bill_service.dart';
import '../utils/money.dart';
import '../theme.dart';
import 'bill_detail_screen.dart';

/// Unpaid and part-paid bills of [branch], oldest first, with the total owed.
class ToCollectScreen extends StatefulWidget {
  const ToCollectScreen({
    super.key,
    required this.branch,
    this.isSuperAdmin = false,
  });

  final Branch branch;
  final bool isSuperAdmin;

  @override
  State<ToCollectScreen> createState() => _ToCollectScreenState();
}

class _ToCollectScreenState extends State<ToCollectScreen> {
  final _service = BillService();
  final _search = TextEditingController();
  Timer? _debounce;
  List<Bill> _bills = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final bills = await _service.fetchOutstanding(
        branchId: widget.branch.id,
        search: _search.text,
      );
      if (mounted) {
        setState(() {
          _bills = bills;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Bill bill) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BillDetailScreen(
          billId: bill.id,
          isSuperAdmin: widget.isSuperAdmin,
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final owed = roundMoney(_bills.fold(0.0, (sum, b) => sum + b.balance));
    final customers = _bills
        .map((b) => b.customerPhone ?? b.customerName ?? b.id)
        .toSet()
        .length;

    return Scaffold(
      appBar: AppBar(title: Text('To collect • ${widget.branch.name}')),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            color: theme.colorScheme.errorContainer,
            child: ListTile(
              leading: Icon(
                Icons.account_balance_wallet_outlined,
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
                '${_bills.length} bills • $customers customers'
                '${_search.text.trim().isEmpty ? '' : ' (search)'}',
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _search,
              keyboardType: TextInputType.text,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Customer name, phone or bike no',
                isDense: true,
              ),
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), _load);
              },
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(child: _list(theme)),
        ],
      ),
    );
  }

  Widget _list(ThemeData theme) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_bills.isEmpty && !_loading) {
      return const Center(child: Text('Nothing to collect 🎉'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _bills.length,
        itemBuilder: (context, i) {
          final b = _bills[i];
          final days = b.daysOld;
          return TileCard(
            child: ListTile(
              title: Text(b.customerName ?? '(no name)'),
              subtitle: Text(
                [
                  if (b.customerPhone != null) b.customerPhone!,
                  if (b.bikeNo != null) b.bikeNo!,
                  b.billNo,
                  days == 0 ? 'today' : '$days day${days == 1 ? '' : 's'} ago',
                  if (b.paymentStatus == PaymentStatus.partial)
                    'paid ${formatMoney(b.amountPaid)} of ${formatMoney(b.total)}',
                ].join(' • '),
              ),
              isThreeLine: b.paymentStatus == PaymentStatus.partial,
              trailing: Text(
                formatMoney(b.balance),
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onTap: () => _open(b),
            ),
          );
        },
      ),
    );
  }
}
