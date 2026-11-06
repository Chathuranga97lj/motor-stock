import 'package:flutter/material.dart';

import '../models/bill.dart';
import '../services/bill_pdf.dart';
import '../services/bill_service.dart';
import '../theme.dart';
import '../utils/money.dart';
import '../widgets/payment_widgets.dart';

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
    final bill = _bill!;
    final result = await showPaymentDialog(context, balance: bill.balance);
    if (result == null) return;
    await _run(() async {
      await _service.addPayment(
        bill.id,
        amount: result.amount,
        method: result.method,
        note: result.note,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment of ${formatMoney(result.amount)} recorded'),
          ),
        );
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
            const Text(
              'The items go back into stock. '
              'The bill stays in the history marked as cancelled.',
            ),
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
            child: const Text('Keep bill'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel bill'),
          ),
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
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .secondary,
                          ),
                          onPressed: _busy ? null : _recordPayment,
                          icon: const Icon(Icons.payments_outlined),
                          label: Text(
                            'Record payment • ${formatMoney(bill.balance)} due',
                          ),
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
                                : () => _run(
                                    () => printBill(bill),
                                    'Could not print',
                                  ),
                            icon: const Icon(Icons.print_outlined),
                            label: const Text('Print'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _run(
                                    () => shareBill(bill),
                                    'Could not share',
                                  ),
                            icon: _busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
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
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: style),
        ],
      ),
    );
    final customer = [
      bill.customerName,
      bill.customerPhone,
    ].whereType<String>().join(' • ');

    final white70 = const TextStyle(color: Colors.white70);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        if (widget.justCreated && !bill.cancelled)
          Card(
            color: const Color(0xFFE3F6EC),
            child: const ListTile(
              leading: Icon(Icons.check_circle, color: Brand.green),
              title: Text('Bill saved'),
              subtitle: Text(
                'Stock has been updated. Share or print it below.',
              ),
            ),
          ),
        if (bill.cancelled)
          Card(
            color: theme.colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.cancel_outlined),
              title: const Text('Cancelled'),
              subtitle: bill.cancelReason == null
                  ? null
                  : Text(bill.cancelReason!),
            ),
          ),
        BrandHeader(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.storefront, color: Colors.white70, size: 18),
                  const SizedBox(width: 6),
                  Expanded(child: Text(bill.branchName, style: white70)),
                  if (!bill.cancelled)
                    PaymentStatusChip(status: bill.paymentStatus),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                formatMoney(bill.total),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  decoration: bill.cancelled
                      ? TextDecoration.lineThrough
                      : null,
                  decorationColor: Colors.white,
                ),
              ),
              Text(formatDateTime(bill.createdAt), style: white70),
              if (bill.hasBalance) ...[
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
                    'Balance due ${formatMoney(bill.balance)}',
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
        if (customer.isNotEmpty || bill.bikeNo != null || bill.issuedBy != null)
          SectionCard(
            title: 'Customer',
            icon: Icons.person_outline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (customer.isNotEmpty)
                  Text(
                    customer,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (bill.bikeNo != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.two_wheeler,
                          size: 18,
                          color: Brand.muted,
                        ),
                        const SizedBox(width: 6),
                        Text(bill.bikeNo!),
                      ],
                    ),
                  ),
                if (bill.issuedBy != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Issued by ${bill.issuedBy}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        for (final (title, icon, items) in [
          ('Parts', Icons.inventory_2_outlined, bill.partItems),
          ('Service / labour', Icons.build_outlined, bill.serviceItems),
        ])
          if (items.isNotEmpty)
            SectionCard(
              title: title,
              icon: icon,
              child: Column(
                children: [
                  for (final item in items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(item.partName),
                      subtitle: Text(
                        item.isService && item.quantity == 1
                            ? 'Service'
                            : '${item.partNo == null ? '' : '${item.partNo} • '}'
                                  '${item.quantity} × ${formatMoney(item.unitPrice)}',
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
            children: [
              if (bill.partItems.isNotEmpty &&
                  bill.serviceItems.isNotEmpty) ...[
                row('Parts', formatMoney(bill.partsTotal)),
                row('Service', formatMoney(bill.servicesTotal)),
              ] else
                row('Subtotal', formatMoney(bill.subtotal)),
              if (bill.discount > 0)
                row('Discount', '- ${formatMoney(bill.discount)}'),
              const Divider(height: 16),
              row(
                'Total',
                formatMoney(bill.total),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  decoration: bill.cancelled
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
              row('Paid', formatMoney(bill.amountPaid)),
              if (bill.hasBalance)
                row(
                  'Balance due',
                  formatMoney(bill.balance),
                  style: const TextStyle(
                    color: Brand.red,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
        ),
        SectionCard(
          title: 'Payments',
          icon: Icons.payments_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (bill.payments.isEmpty)
                const Text(
                  'No payments yet',
                  style: TextStyle(color: Brand.muted),
                ),
              for (final p in bill.payments)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(0xFFE3F6EC),
                    child: Icon(Icons.check, size: 18, color: Brand.green),
                  ),
                  title: Text('${formatMoney(p.amount)} • ${p.method.label}'),
                  subtitle: Text(
                    [
                      formatDateTime(p.createdAt),
                      if (p.takenBy != null) p.takenBy!,
                      if (p.note != null) p.note!,
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
