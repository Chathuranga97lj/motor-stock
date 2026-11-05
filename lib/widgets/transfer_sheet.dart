import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/branch.dart';
import '../models/part.dart';
import '../services/branch_service.dart';

/// What a completed transfer moved.
typedef TransferResult = ({String fromBranchId, String toBranchId, int quantity});

/// Moves stock of [part] between branches. Returns null if cancelled.
Future<TransferResult?> showTransferSheet(
  BuildContext context, {
  required Part part,
  required List<Branch> branches,
  String? fromBranchId,
}) {
  return showModalBottomSheet<TransferResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      // Keep the form above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _TransferForm(
          part: part, branches: branches, fromBranchId: fromBranchId),
    ),
  );
}

class _TransferForm extends StatefulWidget {
  const _TransferForm({
    required this.part,
    required this.branches,
    this.fromBranchId,
  });

  final Part part;
  final List<Branch> branches;
  final String? fromBranchId;

  @override
  State<_TransferForm> createState() => _TransferFormState();
}

class _TransferFormState extends State<_TransferForm> {
  final _service = BranchService();
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController(text: '1');
  final _note = TextEditingController();
  late String _fromId;
  late String _toId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final ids = widget.branches.map((b) => b.id).toList();
    _fromId = ids.contains(widget.fromBranchId) ? widget.fromBranchId! : ids.first;
    _toId = ids.firstWhere((id) => id != _fromId);
  }

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  int get _available => widget.part.quantityAt(_fromId);

  void _setFrom(String id) => setState(() {
        if (id == _toId) _toId = _fromId; // swap
        _fromId = id;
      });

  void _setTo(String id) => setState(() {
        if (id == _fromId) _fromId = _toId; // swap
        _toId = id;
      });

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final quantity = int.parse(_quantity.text);
      await _service.transfer(
        partId: widget.part.id!,
        fromBranchId: _fromId,
        toBranchId: _toId,
        quantity: quantity,
        note: _note.text,
      );
      if (mounted) {
        Navigator.pop<TransferResult>(context,
            (fromBranchId: _fromId, toBranchId: _toId, quantity: quantity));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    DropdownButtonFormField<String> branchField(
            String label, String value, ValueChanged<String> onChanged) =>
        DropdownButtonFormField<String>(
          key: ValueKey('$label|$value'),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            for (final b in widget.branches)
              DropdownMenuItem(
                value: b.id,
                child: Text('${b.name}  (${widget.part.quantityAt(b.id)})',
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: _saving ? null : (id) => onChanged(id!),
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Transfer stock', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                [widget.part.name, widget.part.partNo]
                    .whereType<String>()
                    .join(' • '),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: branchField('From', _fromId, _setFrom)),
                  IconButton(
                    tooltip: 'Swap',
                    icon: const Icon(Icons.swap_horiz),
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                              final from = _fromId;
                              _fromId = _toId;
                              _toId = from;
                            }),
                  ),
                  Expanded(child: branchField('To', _toId, _setTo)),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _quantity,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Quantity',
                  helperText: '$_available available at the sending branch',
                ),
                validator: (v) {
                  final n = int.tryParse(v ?? '') ?? 0;
                  if (n <= 0) return 'Enter a quantity';
                  if (n > _available) return 'Only $_available available';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _note,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.local_shipping_outlined),
                label: const Text('Transfer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
