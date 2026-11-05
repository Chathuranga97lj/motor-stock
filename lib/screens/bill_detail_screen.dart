import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/bill.dart';
import '../services/bill_pdf.dart';
import '../services/bill_service.dart';
import '../utils/money.dart';

/// One saved bill, with Share, Print and (super admin) Cancel.
class BillDetailScreen extends StatefulWidget {
  const BillDetailScreen({
    super.key,
    required this.billId,
    this.isSuperAdmin = false,
    this.justCreated = false,
  });

  final String billId;
  final bool isSuperAdmin;

  /// Shows a "Bill saved" message when opened right after saving.
  final bool justCreated;

  @override
  State<BillDetailScreen> createState() => _BillDetailScreenState();
}

class _BillDetailScreenState extends State<BillDetailScreen> {
  final _service = BillService();
  Bill? _bill;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bill = await _service.fetchBill(widget.billId);
      if (mounted) {
        setState(() {
          _bill = bill;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load bill: $e');
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
    final bill = _bill!;
    final result = await showDialog<_PaymentInput>(
      context: context,
      builder: (_) => _PaymentDialog(balance: bill.balance),
    );
    if (result == null) return;
    await _run(() async {
      await _service.addPayment(bill.id,
          amount: result.amount, method: result.method, note: result.note);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Payment of ${formatMoney(result.amount)} recorded')));
      }
    }, 'Could not record payment');
  }

  Future<void> _cancel() async {
    final reason = TextEditingController();
    final paid = _bill!.amountPaid;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cancel ${_bill!.billNo}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('The items go back into stock. '
                'The bill stays in the history marked as cancelled.'),
            if (paid > 0) ...[
              const SizedBox(height: 12),
              Text(
                'The customer has paid ${formatMoney(paid)} on this bill. '
                'Refund it to them.',
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
              child: const Text('Keep bill')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancel bill')),
        ],
      ),
    );
    final text = reason.text;
    reason.dispose();
    if (confirmed != true) return;
    await _run(() async {
      await _service.cancelBill(widget.billId, reason: text);
      await _load();
    }, 'Could not cancel');
  }

  @override
  Widget build(BuildContext context) {
    final bill = _bill;
    return Scaffold(
      appBar: AppBar(
        title: Text(bill?.billNo ?? 'Bill'),
        actions: [
          if (bill != null && widget.isSuperAdmin && !bill.cancelled)
            PopupMenuButton<String>(
              onSelected: (_) => _cancel(),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'cancel',
                  child: ListTile(
                    leading: Icon(Icons.cancel_outlined),
                    title: Text('Cancel bill'),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: bill == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
            )
          : _body(bill),
      bottomNavigationBar: bill == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (bill.hasBalance) ...[
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.secondary,
                          ),
                          onPressed: _busy ? null : _recordPayment,
                          icon: const Icon(Icons.payments_outlined),
                          label: Text(
                              'Record payment • ${formatMoney(bill.balance)} due'),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(() => printBill(bill), 'Could not print'),
                        icon: const Icon(Icons.print_outlined),
                        label: const Text('Print'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(() => shareBill(bill), 'Could not share'),
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.share),
                        label: const Text('Share'),
                      ),
                    ),
                  ],
                ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _body(Bill bill) {
    final theme = Theme.of(context);
    Widget row(String label, String value, {TextStyle? style}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(label)),
            Text(value, style: style),
          ]),
        );
    final customer = [bill.customerName, bill.customerPhone]
        .whereType<String>()
        .join(' • ');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.justCreated && !bill.cancelled)
          Card(
            color: theme.colorScheme.secondaryContainer,
            child: const ListTile(
              leading: Icon(Icons.check_circle_outline),
              title: Text('Bill saved'),
              subtitle: Text('Stock has been updated. Share or print it below.'),
            ),
          ),
        if (bill.cancelled)
          Card(
            color: theme.colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.cancel_outlined),
              title: const Text('Cancelled'),
              subtitle: bill.cancelReason == null ? null : Text(bill.cancelReason!),
            ),
          ),
        const SizedBox(height: 8),
        Text(bill.branchName, style: theme.textTheme.titleMedium),
        Text(formatDateTime(bill.createdAt)),
        if (customer.isNotEmpty) Text('Customer: $customer'),
        if (!bill.cancelled) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: _StatusChip(status: bill.paymentStatus),
          ),
        ],
        if (bill.issuedBy != null)
          Text('Issued by: ${bill.issuedBy}', style: theme.textTheme.bodySmall),
        const Divider(height: 24),
        for (final item in bill.items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(item.partName),
            subtitle: Text('${item.partNo == null ? '' : '${item.partNo} • '}'
                '${item.quantity} × ${formatMoney(item.unitPrice)}'),
            trailing: Text(formatMoney(item.lineTotal),
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        const Divider(height: 24),
        row('Subtotal', formatMoney(bill.subtotal)),
        if (bill.discount > 0) row('Discount', '- ${formatMoney(bill.discount)}'),
        row('Total', formatMoney(bill.total),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              decoration: bill.cancelled ? TextDecoration.lineThrough : null,
            )),
        row('Paid', formatMoney(bill.amountPaid)),
        if (bill.hasBalance)
          row('Balance due', formatMoney(bill.balance),
              style: TextStyle(
                  color: theme.colorScheme.error, fontWeight: FontWeight.bold)),
        const Divider(height: 24),
        Text('Payments', style: theme.textTheme.titleSmall),
        if (bill.payments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No payments yet'),
          ),
        for (final p in bill.payments)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.payments_outlined),
            title: Text('${formatMoney(p.amount)} • ${p.method.label}'),
            subtitle: Text([
              formatDateTime(p.createdAt),
              if (p.takenBy != null) p.takenBy!,
              if (p.note != null) p.note!,
            ].join(' • ')),
          ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final PaymentStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (status) {
      PaymentStatus.paid => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      PaymentStatus.partial => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      PaymentStatus.unpaid => (scheme.errorContainer, scheme.onErrorContainer),
    };
    return Chip(
      label: Text(status.label),
      backgroundColor: bg,
      labelStyle: TextStyle(color: fg, fontWeight: FontWeight.w600),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}

typedef _PaymentInput = ({double amount, PaymentMethod method, String? note});

/// Amount (defaults to the full balance), method and note.
class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.balance});

  final double balance;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final _amount =
      TextEditingController(text: widget.balance.toStringAsFixed(2));
  final _note = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  double get _value => roundMoney(double.tryParse(_amount.text) ?? 0);

  String? get _error {
    if (_value <= 0) return 'Enter an amount';
    if (_value > widget.balance) return 'More than the balance';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record payment'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Balance due: ${formatMoney(widget.balance)}'),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              decoration: InputDecoration(
                labelText: 'Amount ($currencySymbol)',
                errorText: _amount.text.isEmpty ? null : _error,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            SegmentedButton<PaymentMethod>(
              segments: [
                for (final m in PaymentMethod.receiving)
                  ButtonSegment(value: m, label: Text(m.shortLabel)),
              ],
              selected: {_method},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _method = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _error != null
              ? null
              : () => Navigator.pop<_PaymentInput>(context, (
                    amount: _value,
                    method: _method,
                    note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                  )),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
