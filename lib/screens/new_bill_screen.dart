import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/bill.dart';
import '../models/branch.dart';
import '../models/part.dart';
import '../services/bill_service.dart';
import '../utils/money.dart';
import '../widgets/part_picker.dart';
import 'bill_detail_screen.dart';

/// Builds a bill for [branch], saves it and opens the saved bill.
class NewBillScreen extends StatefulWidget {
  const NewBillScreen({super.key, required this.branch, this.isSuperAdmin = false});

  final Branch branch;
  final bool isSuperAdmin;

  @override
  State<NewBillScreen> createState() => _NewBillScreenState();
}

class _NewBillScreenState extends State<NewBillScreen> {
  final _billService = BillService();
  final _lines = <CartLine>[];
  final _customerName = TextEditingController();
  final _customerPhone = TextEditingController();
  final _discount = TextEditingController();
  // Empty means the full total is paid now.
  final _amountPaid = TextEditingController();
  PaymentMethod _payment = PaymentMethod.cash;
  bool _saving = false;
  bool _triedSave = false;

  @override
  void dispose() {
    _customerName.dispose();
    _customerPhone.dispose();
    _discount.dispose();
    _amountPaid.dispose();
    super.dispose();
  }

  double get _subtotal => cartSubtotal(_lines);
  double get _discountValue => double.tryParse(_discount.text) ?? 0;
  double get _total {
    final t = roundMoney(_subtotal - _discountValue);
    return t < 0 ? 0 : t;
  }

  String? get _discountError =>
      _discountValue > _subtotal ? 'More than the subtotal' : null;

  double get _paidNow {
    if (_payment == PaymentMethod.credit) return 0;
    final text = _amountPaid.text.trim();
    return text.isEmpty ? _total : roundMoney(double.tryParse(text) ?? 0);
  }

  double get _balance => roundMoney(_total - _paidNow);
  String? get _paidError => _paidNow > _total ? 'More than the total' : null;

  // A bill that is not fully paid needs to say who owes the money.
  bool get _needsCustomer => _balance > 0;
  String? _requiredError(TextEditingController c) =>
      _triedSave && _needsCustomer && c.text.trim().isEmpty
          ? 'Required when there is a balance'
          : null;

  bool get _canSave =>
      _lines.isNotEmpty && _discountError == null && _paidError == null;

  int _available(Part p) => p.quantityAt(widget.branch.id);

  Future<void> _addPart() async {
    final part = await showPartPicker(context,
        branchId: widget.branch.id, requireStock: true);
    if (part == null) return;
    setState(() {
      final existing = _lines.where((l) => l.part.id == part.id).firstOrNull;
      if (existing == null) {
        _lines.add(CartLine(part));
      } else if (existing.quantity < _available(existing.part)) {
        existing.quantity++;
      }
    });
  }

  void _changeQty(CartLine line, int delta) => setState(() {
        line.quantity += delta;
        if (line.quantity <= 0) _lines.remove(line);
      });

  Future<void> _save() async {
    setState(() => _triedSave = true);
    if (!_canSave ||
        _requiredError(_customerName) != null ||
        _requiredError(_customerPhone) != null) {
      return;
    }
    setState(() => _saving = true);
    try {
      final id = await _billService.createBill(
        branchId: widget.branch.id,
        lines: _lines,
        paymentMethod: _payment,
        discount: _discountValue,
        amountPaid: _paidNow,
        customerName: _customerName.text,
        customerPhone: _customerPhone.text,
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => BillDetailScreen(
            billId: id, isSuperAdmin: widget.isSuperAdmin, justCreated: true),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$e'.replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      // Ask before throwing away a bill that has items.
      canPop: _lines.isEmpty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard this bill?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Keep editing')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Discard')),
            ],
          ),
        );
        if (leave == true && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text('New bill • ${widget.branch.name}')),
        body: AbsorbPointer(
          absorbing: _saving,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Row(
                children: [
                  Expanded(
                      child: Text('Items', style: theme.textTheme.titleMedium)),
                  FilledButton.tonalIcon(
                    onPressed: _addPart,
                    icon: const Icon(Icons.add),
                    label: const Text('Add part'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_lines.isEmpty)
                Card.outlined(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('No items yet. Tap "Add part".',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium),
                  ),
                ),
              for (final line in _lines) _lineTile(line),
              const SizedBox(height: 16),
              Text(_needsCustomer ? 'Customer' : 'Customer (optional)',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              TextField(
                controller: _customerName,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: _needsCustomer ? 'Name *' : 'Name',
                  errorText: _requiredError(_customerName),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _customerPhone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: _needsCustomer ? 'Phone *' : 'Phone',
                  errorText: _requiredError(_customerPhone),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              Text('Payment', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<PaymentMethod>(
                segments: [
                  for (final m in PaymentMethod.values)
                    ButtonSegment(value: m, label: Text(m.shortLabel)),
                ],
                selected: {_payment},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _payment = s.first),
              ),
              const SizedBox(height: 12),
              if (_payment == PaymentMethod.credit)
                Text('Nothing is paid now. The full total is added to '
                    'To collect.',
                    style: theme.textTheme.bodySmall)
              else
                TextField(
                  controller: _amountPaid,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Amount paid now ($currencySymbol)',
                    hintText: 'Full amount',
                    helperText: 'Leave empty if paying in full',
                    errorText: _paidError,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _discount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                  labelText: 'Discount on whole bill ($currencySymbol)',
                  errorText: _discountError,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _totalsBar(theme),
      ),
    );
  }

  Widget _lineTile(CartLine line) {
    final available = _available(line.part);
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.part.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    '${line.part.partNo == null ? '' : '${line.part.partNo} • '}'
                    '${formatMoney(line.part.sellPrice)} each • $available in stock',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 2),
                  Text(formatMoney(line.lineTotal),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'One less',
              icon: Icon(line.quantity == 1
                  ? Icons.delete_outline
                  : Icons.remove_circle_outline),
              onPressed: () => _changeQty(line, -1),
            ),
            Text('${line.quantity}',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            IconButton(
              tooltip: 'One more',
              icon: const Icon(Icons.add_circle_outline),
              onPressed:
                  line.quantity < available ? () => _changeQty(line, 1) : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalsBar(ThemeData theme) {
    Widget row(String label, String value, {bool bold = false}) => Row(
          children: [
            Expanded(child: Text(label)),
            Text(value,
                style: bold
                    ? theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)
                    : null),
          ],
        );
    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              row('Subtotal', formatMoney(_subtotal)),
              if (_discountValue > 0)
                row('Discount', '- ${formatMoney(_discountValue)}'),
              row('Total', formatMoney(_total), bold: true),
              if (_balance > 0 && _lines.isNotEmpty) ...[
                row('Paid now', formatMoney(_paidNow)),
                Row(
                  children: [
                    Expanded(
                        child: Text('Balance to collect',
                            style: TextStyle(color: theme.colorScheme.error))),
                    Text(formatMoney(_balance),
                        style: TextStyle(
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: !_canSave || _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.receipt_long),
                  label: Text(_saving ? 'Saving…' : 'Save bill'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
