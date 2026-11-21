import 'package:flutter/material.dart';

import '../models/bill.dart';
import '../models/branch.dart';
import '../models/stock_return.dart';
import '../services/return_service.dart';
import '../theme.dart';
import '../utils/errors.dart';
import '../utils/money.dart';
import '../utils/period.dart';
import '../widgets/returns_section.dart';
import 'bill_detail_screen.dart';
import 'purchase_detail_screen.dart';

/// Customer and supplier returns at [branch], newest first.
class ReturnsScreen extends StatefulWidget {
  const ReturnsScreen({
    super.key,
    required this.branch,
    this.isSuperAdmin = false,
  });

  final Branch branch;
  final bool isSuperAdmin;

  @override
  State<ReturnsScreen> createState() => _ReturnsScreenState();
}

class _ReturnsScreenState extends State<ReturnsScreen> {
  final _service = ReturnService();
  ReturnKind _kind = ReturnKind.customer;
  ReportPeriod _period = ReportPeriod.month;
  List<StockReturn> _returns = [];
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
      final list = await _service.fetchReturns(
        _kind,
        branchId: widget.branch.id,
        from: _period.from,
      );
      if (mounted) {
        setState(() {
          _returns = list;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = errorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(StockReturn r) async {
    if (r.docId == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => r.kind == ReturnKind.customer
          ? BillDetailScreen(billId: r.docId!, isSuperAdmin: widget.isSuperAdmin)
          : PurchaseDetailScreen(
              purchaseId: r.docId!, isSuperAdmin: widget.isSuperAdmin),
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final value = roundMoney(_returns.fold(0.0, (s, r) => s + r.value));
    final refunded = roundMoney(_returns.fold(0.0, (s, r) => s + r.refundAmount));
    final customer = _kind == ReturnKind.customer;
    return Scaffold(
      appBar: AppBar(title: Text('Returns • ${widget.branch.name}')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: SegmentedButton<ReturnKind>(
              segments: const [
                ButtonSegment(
                  value: ReturnKind.customer,
                  icon: Icon(Icons.person_outline),
                  label: Text('From customers'),
                ),
                ButtonSegment(
                  value: ReturnKind.supplier,
                  icon: Icon(Icons.local_shipping_outlined),
                  label: Text('To suppliers'),
                ),
              ],
              selected: {_kind},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                setState(() => _kind = s.first);
                _load();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: SegmentedButton<ReportPeriod>(
              segments: [
                for (final p in ReportPeriod.withoutToday)
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
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: StatBox(
                      label: 'Returned',
                      value: formatMoney(value),
                      note: '${_returns.length} '
                          '${_returns.length == 1 ? 'return' : 'returns'}',
                      color: Brand.red,
                      icon: Icons.assignment_return_outlined,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatBox(
                      label: customer ? 'Refunded' : 'Refunds received',
                      value: formatMoney(refunded),
                      note: customer ? 'money given back' : 'money back',
                      color: Brand.blue,
                      icon: Icons.payments_outlined,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(child: _list()),
        ],
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
    if (_returns.isEmpty && !_loading) {
      return const Center(child: Text('No returns in this period'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: _returns.length,
        itemBuilder: (context, i) => TileCard(
          onTap: () => _open(_returns[i]),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: ReturnSummary(ret: _returns[i], showDoc: true),
          ),
        ),
      ),
    );
  }
}
