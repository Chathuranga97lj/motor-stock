import 'package:flutter/material.dart';

import '../models/bill.dart';
import '../models/stock_return.dart';
import '../services/return_service.dart';
import '../theme.dart';
import '../utils/money.dart';

/// Return parts from a bill (customer return) or a stock-in (supplier
/// return): choose quantities and a reason, see the money, save.
/// Pops with true when a return was saved.
class ReturnScreen extends StatefulWidget {
  const ReturnScreen({
    super.key,
    required this.kind,
    required this.docId,
    required this.docNo,
    this.otherParty,
    required this.lines,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.returnedTotal,
    required this.amountPaid,
    this.hasServiceLines = false,
  });

  final ReturnKind kind;
  final String docId;
  final String docNo;

  /// Customer or supplier name.
  final String? otherParty;
  final List<ReturnableLine> lines;
  final double subtotal;
  final double discount;
  final double total;
  final double returnedTotal;
  final double amountPaid;

  /// Bills with service lines can never be "everything returned".
  final bool hasServiceLines;

  @override
  State<ReturnScreen> createState() => _ReturnScreenState();
}

class _ReturnScreenState extends State<ReturnScreen> {
  final _reason = TextEditingController();
  final Map<int, int> _qty = {};
  PaymentMethod _refundMethod = PaymentMethod.cash;
  bool _saving = false;

  bool get _customer => widget.kind == ReturnKind.customer;

  List<String> get _reasons => _customer
      ? const ['Faulty', 'Wrong part', 'Not needed', 'Changed mind']
      : const ['Faulty', 'Damaged', 'Wrong part', 'Extra stock'];

  int get _chosenCount => _qty.values.fold(0, (s, q) => s + q);

  bool get _returnsEverything {
    if (widget.hasServiceLines) return false;
    for (var i = 0; i < widget.lines.length; i++) {
      final l = widget.lines[i];
      if (l.returnedQty + (_qty[i] ?? 0) < l.quantity) return false;
    }
    return true;
  }

  ReturnMoney get _money => ReturnMoney.of(
        lines: widget.lines,
        chosen: _qty,
        subtotal: widget.subtotal,
        discount: widget.discount,
        total: widget.total,
        returnedTotal: widget.returnedTotal,
        amountPaid: widget.amountPaid,
        returnsEverything: _returnsEverything,
      );

  bool get _canSave =>
      !_saving && _chosenCount > 0 && _reason.text.trim().isNotEmpty;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _set(int i, int q) {
    final max = widget.lines[i].returnable;
    setState(() => _qty[i] = q.clamp(0, max));
  }

  Future<void> _save() async {
    final money = _money;
    final owedCut = roundMoney(money.value - money.refund);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Save this return?'),
        content: Text([
          '$_chosenCount ${_chosenCount == 1 ? 'item' : 'items'} worth '
              '${formatMoney(money.value)}.',
          _customer
              ? 'The parts go back into stock.'
              : 'The parts are taken out of stock.',
          if (owedCut > 0)
            _customer
                ? '${formatMoney(owedCut)} comes off what the customer owes.'
                : '${formatMoney(owedCut)} comes off what you owe the supplier.',
          if (money.refund > 0)
            _customer
                ? 'Give the customer ${formatMoney(money.refund)} back '
                    '(${_refundMethod.label}).'
                : 'The supplier gives you ${formatMoney(money.refund)} back '
                    '(${_refundMethod.label}).',
          'This cannot be undone.',
        ].join('\n\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save return'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await ReturnService().save(
        widget.kind,
        docId: widget.docId,
        quantities: {
          for (final e in _qty.entries)
            if (e.value > 0) widget.lines[e.key].itemId: e.value,
        },
        reason: _reason.text.trim(),
        refundMethod: _refundMethod,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Could not save the return: ${'$e'.replaceFirst('Exception: ', '')}'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = _money;
    final owedCut = roundMoney(money.value - money.refund);
    return Scaffold(
      appBar: AppBar(
        title: Text(_customer ? 'Return items' : 'Return to supplier'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          SectionCard(
            title: widget.docNo,
            icon: _customer ? Icons.receipt_long : Icons.inventory_2_outlined,
            child: Text(
              [
                if (widget.otherParty != null) widget.otherParty!,
                _customer
                    ? 'Returned parts go back into stock at this branch.'
                    : 'Returned parts are taken out of stock at this branch.',
              ].join('\n'),
              style: const TextStyle(color: Brand.muted),
            ),
          ),
          SectionCard(
            title: 'What is coming back?',
            icon: Icons.assignment_return_outlined,
            child: Column(
              children: [
                for (var i = 0; i < widget.lines.length; i++) _lineRow(i),
              ],
            ),
          ),
          SectionCard(
            title: 'Reason',
            icon: Icons.edit_note,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final r in _reasons)
                      ChoiceChip(
                        label: Text(r),
                        selected: _reason.text == r,
                        onSelected: (_) => setState(() => _reason.text = r),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _reason,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Reason *',
                    hintText: 'Pick one above or type your own',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
          SectionCard(
            title: 'Money',
            icon: Icons.payments_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _moneyRow('Return value', formatMoney(money.value), bold: true),
                if (widget.discount > 0)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Less its share of the discount.',
                      style: TextStyle(color: Brand.muted, fontSize: 12),
                    ),
                  ),
                if (owedCut > 0)
                  _moneyRow(
                    _customer ? 'Off what the customer owes' : 'Off what you owe',
                    formatMoney(owedCut),
                  ),
                if (money.refund > 0) ...[
                  _moneyRow(
                    _customer ? 'Give back to customer' : 'Supplier gives back',
                    formatMoney(money.refund),
                    color: Brand.red,
                    bold: true,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<PaymentMethod>(
                    initialValue: _refundMethod,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: _customer ? 'Give it back by' : 'Received by',
                    ),
                    items: [
                      for (final m in PaymentMethod.receiving)
                        DropdownMenuItem(value: m, child: Text(m.label)),
                    ],
                    onChanged: (m) =>
                        setState(() => _refundMethod = m ?? PaymentMethod.cash),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: FilledButton.icon(
            onPressed: _canSave ? _save : null,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.assignment_return),
            label: Text(_chosenCount == 0
                ? 'Choose what is coming back'
                : _reason.text.trim().isEmpty
                    ? 'Enter a reason'
                    : 'Save return • ${formatMoney(money.value)}'),
          ),
        ),
      ),
    );
  }

  Widget _moneyRow(String label, String value,
          {Color? color, bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              value,
              style: TextStyle(
                color: color ?? Brand.ink,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      );

  Widget _lineRow(int i) {
    final l = widget.lines[i];
    final q = _qty[i] ?? 0;
    final done = l.returnable == 0;
    final status = l.partGone
        ? 'Part was deleted, cannot return'
        : done
            ? 'All ${l.quantity} already returned'
            : '${_customer ? 'Sold' : 'Received'} ${l.quantity}'
                '${l.returnedQty > 0 ? ' • ${l.returnedQty} returned' : ''}'
                ' • ${formatMoney(l.unitPrice)} each';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: done ? Brand.muted : Brand.ink,
                  ),
                ),
                if (l.partNo != null)
                  Text(l.partNo!,
                      style: const TextStyle(color: Brand.muted, fontSize: 12)),
                Text(status,
                    style: const TextStyle(color: Brand.muted, fontSize: 12)),
              ],
            ),
          ),
          if (!done) ...[
            IconButton(
              tooltip: 'Less',
              onPressed: q > 0 ? () => _set(i, q - 1) : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            SizedBox(
              width: 28,
              child: Text(
                '$q',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: 'More',
              onPressed: q < l.returnable ? () => _set(i, q + 1) : null,
              icon: const Icon(Icons.add_circle_outline, color: Brand.blue),
            ),
          ],
        ],
      ),
    );
  }
}
