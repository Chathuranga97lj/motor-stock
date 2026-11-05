import 'package:flutter/material.dart';

import '../models/purchase.dart';
import '../services/purchase_service.dart';
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$failMessage: ${'$e'.replaceFirst('Exception: ', '')}')));
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
      await _service.addPayment(p.id,
          amount: result.amount, method: result.method, note: result.note);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Paid ${formatMoney(result.amount)} to ${p.supplierName}')));
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
            const Text('The stock is taken back out. This only works if the '
                'items are still in stock (not sold or moved).'),
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
              child: const Text('Keep')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancel stock-in')),
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
          child: Row(children: [
            Expanded(child: Text(label)),
            Text(value, style: style),
          ]),
        );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.justCreated && !p.cancelled)
          Card(
            color: theme.colorScheme.secondaryContainer,
            child: ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Stock-in saved'),
              subtitle: Text('${p.itemCount} items added to ${p.branchName} stock.'),
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
        const SizedBox(height: 8),
        Text(p.supplierName, style: theme.textTheme.titleLarge),
        if (p.supplierPhone != null) Text(p.supplierPhone!),
        const SizedBox(height: 4),
        Text('Invoice: ${p.invoiceNo ?? '-'} • '
            '${formatDateTime(p.invoiceDate).substring(0, 10)}'),
        Text('Branch: ${p.branchName}'),
        Text('Entered: ${formatDateTime(p.createdAt)}'
            '${p.enteredBy == null ? '' : ' by ${p.enteredBy}'}',
            style: theme.textTheme.bodySmall),
        if (p.note != null) Text('Note: ${p.note}'),
        if (!p.cancelled) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: PaymentStatusChip(status: p.paymentStatus),
          ),
        ],
        const Divider(height: 24),
        for (final item in p.items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(item.partName),
            subtitle: Text('${item.partNo == null ? '' : '${item.partNo} • '}'
                '${item.quantity} × ${formatMoney(item.unitCost)}'),
            trailing: Text(formatMoney(item.lineTotal),
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        const Divider(height: 24),
        if (p.discount > 0) ...[
          row('Subtotal', formatMoney(p.subtotal)),
          row('Discount', '- ${formatMoney(p.discount)}'),
        ],
        row('Total cost', formatMoney(p.total),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              decoration: p.cancelled ? TextDecoration.lineThrough : null,
            )),
        row('Paid', formatMoney(p.amountPaid)),
        if (p.hasBalance)
          row('Still to pay', formatMoney(p.balance),
              style: TextStyle(
                  color: theme.colorScheme.error, fontWeight: FontWeight.bold)),
        if (p.hasBalance && !widget.isSuperAdmin)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('The super admin records payments to suppliers.',
                style: theme.textTheme.bodySmall),
          ),
        const Divider(height: 24),
        Text('Payments to supplier', style: theme.textTheme.titleSmall),
        if (p.payments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No payments yet'),
          ),
        for (final pay in p.payments)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.payments_outlined),
            title: Text('${formatMoney(pay.amount)} • ${pay.method.label}'),
            subtitle: Text([
              formatDateTime(pay.createdAt),
              if (pay.takenBy != null) pay.takenBy!,
              if (pay.note != null) pay.note!,
            ].join(' • ')),
          ),
      ],
    );
  }
}
