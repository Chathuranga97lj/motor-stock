import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/bill.dart';
import '../utils/money.dart';

/// Asks for a payment against [balance]: amount (defaults to all of it),
/// method and note. Returns null if cancelled.
Future<PaymentInput?> showPaymentDialog(BuildContext context,
        {required double balance}) =>
    showDialog<PaymentInput>(
      context: context,
      builder: (_) => _PaymentDialog(balance: balance),
    );
class PaymentStatusChip extends StatelessWidget {
  const PaymentStatusChip({super.key, required this.status});

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

typedef PaymentInput = ({double amount, PaymentMethod method, String? note});

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
              : () => Navigator.pop<PaymentInput>(context, (
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
