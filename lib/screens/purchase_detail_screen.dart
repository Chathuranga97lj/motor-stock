import 'package:flutter/material.dart';

import '../models/purchase.dart';
import '../services/purchase_service.dart';
import '../theme.dart';
import '../utils/money.dart';
import '../widgets/payment_widgets.dart';

/// One stock-in, with Record payment and Cancel for the super admin.
class PurchaseDetailScreen extends StatefulWidget {
  const PurchaseDetailScreen({
    super.key,
    required this.purchaseId,
    this.isSuperAdmin = false,
    this.justCreated = false,
  });

  final String purchaseId;
  final bool isSuperAdmin;
  final bool justCreated;

  @override
  State<PurchaseDetailScreen> createState() => _PurchaseDetailScreenState();
}

class _PurchaseDetailScreenState extends State<PurchaseDetailScreen> {
  final _service = PurchaseService();
  Purchase? _purchase;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _service.fetchPurchase(widget.purchaseId);
      if (mounted) {
        setState(() {
          _purchase = p;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load stock-in: $e');
    }
  }

  Future<void> _run(Future<void> Function() action, String failMessage) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$failMessage: ${'$e'.replaceFirst('Exception: ', '')}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recordPayment() async {
    final p = _purchase!;
    final result = await showPaymentDialog(context, balance: p.balance);
    if (result == null) return;
    await _run(() async {
      await _service.addPayment(
        p.id,
        amount: result.amount,
        method: result.method,
        note: result.note,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Paid ${formatMoney(result.amount)} to ${p.supplierName}',
            ),
          ),
        );
      }
    }, 'Could not record payment');
  }

  Future<void> _cancel() async {
    final p = _purchase!;
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cancel ${p.purchaseNo}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The stock is taken back out. This only works if the '
              'items are still in stock (not sold or moved).',
            ),
            if (p.amountPaid > 0) ...[
              const SizedBox(height: 12),
              Text(
                '${formatMoney(p.amountPaid)} was paid to ${p.supplierName}. '
                'Get it back from them.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'Reason (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel stock-in'),
          ),
        ],
      ),
    );
    final text = reason.text;
    reason.dispose();
    if (confirmed != true) return;
    await _run(() async {
      await _service.cancelPurchase(p.id, reason: text);
      await _load();
    }, 'Could not cancel');
  }

  @override
  Widget build(BuildContext context) {
    final p = _purchase;
    final canPay = p != null && p.hasBalance && widget.isSuperAdmin;
    return Scaffold(
      appBar: AppBar(
        title: Text(p?.purchaseNo ?? 'Stock-in'),
        actions: [
          if (p != null && widget.isSuperAdmin && !p.cancelled)
            PopupMenuButton<String>(
              onSelected: (_) => _cancel(),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'cancel',
                  child: ListTile(
                    leading: Icon(Icons.cancel_outlined),
                    title: Text('Cancel stock-in'),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: p == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
            )
          : _body(p),
      bottomNavigationBar: !canPay
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _busy ? null : _recordPayment,
                  icon: const Icon(Icons.payments_outlined),
                  label: Text('Pay supplier • ${formatMoney(p.balance)} due'),
                ),
              ),
            ),
    );
  }

  Widget _body(Purchase p) {
    final theme = Theme.of(context);
    Widget row(String label, String value, {TextStyle? style}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: style),
        ],
      ),
    );

    const white70 = TextStyle(color: Colors.white70);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        if (widget.justCreated && !p.cancelled)
          Card(
            color: const Color(0xFFE3F6EC),
            child: ListTile(
              leading: const Icon(Icons.check_circle, color: Brand.green),
              title: const Text('Stock-in saved'),
              subtitle: Text(
                '${p.itemCount} items added to ${p.branchName} stock.',
              ),
            ),
          ),
        if (p.cancelled)
          Card(
            color: theme.colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.cancel_outlined),
              title: const Text('Cancelled'),
              subtitle: p.cancelReason == null ? null : Text(p.cancelReason!),
            ),
          ),
        BrandHeader(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.local_shipping_outlined,
                    color: Colors.white70,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      p.supplierName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (!p.cancelled) PaymentStatusChip(status: p.paymentStatus),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                formatMoney(p.total),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  decoration: p.cancelled ? TextDecoration.lineThrough : null,
                  decorationColor: Colors.white,
                ),
              ),
              Text(
                'Invoice ${p.invoiceNo ?? '-'} • '
                '${formatDateTime(p.invoiceDate).substring(0, 10)} • ${p.branchName}',
                style: white70,
              ),
              if (p.hasBalance) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Brand.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Still to pay ${formatMoney(p.balance)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        SectionCard(
          title: 'Details',
          icon: Icons.info_outline,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p.supplierPhone != null)
                Text('Supplier phone: ${p.supplierPhone}'),
              Text(
                'Entered ${formatDateTime(p.createdAt)}'
                '${p.enteredBy == null ? '' : ' by ${p.enteredBy}'}',
                style: theme.textTheme.bodySmall,
              ),
              if (p.note != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Note: ${p.note}'),
                ),
            ],
          ),
        ),
        SectionCard(
          title: 'Items',
          icon: Icons.inventory_2_outlined,
          child: Column(
            children: [
              for (final item in p.items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(item.partName),
                  subtitle: Text(
                    '${item.partNo == null ? '' : '${item.partNo} • '}'
                    '${item.quantity} × ${formatMoney(item.unitCost)}',
                  ),
                  trailing: Text(
                    formatMoney(item.lineTotal),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Brand.ink,
                    ),
                  ),
                ),
            ],
          ),
        ),
        SectionCard(
          title: 'Totals',
          icon: Icons.calculate_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p.discount > 0) ...[
                row('Subtotal', formatMoney(p.subtotal)),
                row('Discount', '- ${formatMoney(p.discount)}'),
                const Divider(height: 16),
              ],
              row(
                'Total cost',
                formatMoney(p.total),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  decoration: p.cancelled ? TextDecoration.lineThrough : null,
                ),
              ),
              row('Paid', formatMoney(p.amountPaid)),
              if (p.hasBalance)
                row(
                  'Still to pay',
                  formatMoney(p.balance),
                  style: const TextStyle(
                    color: Brand.red,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              if (p.hasBalance && !widget.isSuperAdmin)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'The super admin records payments to suppliers.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        SectionCard(
          title: 'Payments to supplier',
          icon: Icons.payments_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p.payments.isEmpty)
                const Text(
                  'No payments yet',
                  style: TextStyle(color: Brand.muted),
                ),
              for (final pay in p.payments)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(0xFFE3F6EC),
                    child: Icon(Icons.check, size: 18, color: Brand.green),
                  ),
                  title: Text(
                    '${formatMoney(pay.amount)} • ${pay.method.label}',
                  ),
                  subtitle: Text(
                    [
                      formatDateTime(pay.createdAt),
                      if (pay.takenBy != null) pay.takenBy!,
                      if (pay.note != null) pay.note!,
                    ].join(' • '),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
