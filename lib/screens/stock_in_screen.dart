import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/bill.dart';
import '../models/branch.dart';
import '../models/purchase.dart';
import '../services/parts_service.dart';
import '../services/purchase_service.dart';
import '../utils/money.dart';
import '../widgets/part_picker.dart';
import 'part_form_screen.dart';
import 'purchase_detail_screen.dart';

final _moneyInput = FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'));

/// Stock arriving from a supplier: supplier, invoice, parts with costs,
/// and how much was paid now. Saving adds the stock to [branch].
class StockInScreen extends StatefulWidget {
  const StockInScreen({super.key, required this.branch, this.isSuperAdmin = false});

  final Branch branch;
  final bool isSuperAdmin;

  @override
  State<StockInScreen> createState() => _StockInScreenState();
}

class _StockInScreenState extends State<StockInScreen> {
  final _service = PurchaseService();
  final _partsService = PartsService();
  final _lines = <PurchaseLine>[];
  final _invoiceNo = TextEditingController();
  final _discount = TextEditingController();
  final _amountPaid = TextEditingController();
  final _note = TextEditingController();
  List<Supplier> _suppliers = [];
  String? _supplierId;
  DateTime _invoiceDate = DateTime.now();
  PaymentMethod _payment = PaymentMethod.cash;
  bool _updateBuyPrice = true;
  bool _saving = false;
  bool _triedSave = false;

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  @override
  void dispose() {
    for (final c in [_invoiceNo, _discount, _amountPaid, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    try {
      final suppliers = await _service.fetchSuppliers();
      if (mounted) setState(() => _suppliers = suppliers);
    } catch (e) {
      _snack('Could not load suppliers: $e');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------- Totals ----------

  double get _subtotal => purchaseSubtotal(_lines);
  double get _discountValue => double.tryParse(_discount.text) ?? 0;
  double get _total {
    final t = roundMoney(_subtotal - _discountValue);
    return t < 0 ? 0 : t;
  }

  double get _paidNow {
    if (_payment == PaymentMethod.credit) return 0;
    final text = _amountPaid.text.trim();
    return text.isEmpty ? _total : roundMoney(double.tryParse(text) ?? 0);
  }

  double get _balance => roundMoney(_total - _paidNow);
  String? get _discountError =>
      _discountValue > _subtotal ? 'More than the subtotal' : null;
  String? get _paidError => _paidNow > _total ? 'More than the total' : null;
  String? get _supplierError =>
      _triedSave && _supplierId == null ? 'Choose a supplier' : null;

  bool get _canSave =>
      _lines.isNotEmpty &&
      _lines.every((l) => l.quantity > 0) &&
      _discountError == null &&
      _paidError == null;

  // ---------- Actions ----------

  Future<void> _addSupplier() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New supplier'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add')),
        ],
      ),
    );
    final values = (name.text, phone.text);
    name.dispose();
    phone.dispose();
    if (ok != true || values.$1.trim().isEmpty) return;
    try {
      final s = await _service.addSupplier(name: values.$1, phone: values.$2);
      await _loadSuppliers();
      setState(() => _supplierId = s.id);
    } catch (e) {
      _snack('$e'.replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _invoiceDate,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (picked != null) setState(() => _invoiceDate = picked);
  }

  Future<void> _addExistingPart() async {
    final part = await showPartPicker(context,
        branchId: widget.branch.id, showCost: true);
    if (part == null) return;
    setState(() => _lines.add(PurchaseLine(part)));
  }

  Future<void> _addNewPart() async {
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => PartFormScreen(
        branches: const [],
        isSuperAdmin: widget.isSuperAdmin,
        forStockIn: true,
      ),
    ));
    if (id == null) return;
    try {
      final part = await _partsService.fetchPart(id);
      setState(() => _lines.add(PurchaseLine(part)));
    } catch (e) {
      _snack('Part saved, but could not add it here: $e');
    }
  }

  Future<void> _save() async {
    setState(() => _triedSave = true);
    final supplierId = _supplierId;
    if (supplierId == null || !_canSave) return;

    // Warn before entering the same supplier invoice twice.
    final invoice = _invoiceNo.text.trim();
    if (invoice.isNotEmpty) {
      try {
        final existing = await _service.findByInvoice(supplierId, invoice);
        if (existing != null && mounted) {
          final goOn = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Invoice already entered?'),
              content: Text('Invoice $invoice from this supplier was already '
                  'stocked in as $existing. Save it again?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Go back')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Save anyway')),
              ],
            ),
          );
          if (goOn != true) return;
        }
      } catch (_) {
        // The check is a convenience; saving still works without it.
      }
    }

    setState(() => _saving = true);
    try {
      final id = await _service.createPurchase(
        branchId: widget.branch.id,
        supplierId: supplierId,
        lines: _lines,
        paymentMethod: _payment,
        invoiceNo: invoice,
        invoiceDate: _invoiceDate,
        discount: _discountValue,
        amountPaid: _paidNow,
        updateBuyPrice: _updateBuyPrice,
        note: _note.text,
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => PurchaseDetailScreen(
            purchaseId: id, isSuperAdmin: widget.isSuperAdmin, justCreated: true),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('$e'.replaceFirst('Exception: ', ''));
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: _lines.isEmpty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard this stock-in?'),
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
        appBar: AppBar(title: Text('Stock in • ${widget.branch.name}')),
        body: AbsorbPointer(
          absorbing: _saving,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Text('Supplier', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('supplier|$_supplierId|${_suppliers.length}'),
                      initialValue: _supplierId,
                      isExpanded: true,
                      decoration: InputDecoration(
                          labelText: 'Supplier *', errorText: _supplierError),
                      items: [
                        for (final s in _suppliers)
                          DropdownMenuItem(
                              value: s.id,
                              child:
                                  Text(s.name, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (id) => setState(() => _supplierId = id),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: IconButton.filledTonal(
                      tooltip: 'New supplier',
                      icon: const Icon(Icons.add),
                      onPressed: _addSupplier,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _invoiceNo,
                      textCapitalization: TextCapitalization.characters,
                      decoration:
                          const InputDecoration(labelText: 'Invoice no'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: _pickDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                            labelText: 'Invoice date',
                            suffixIcon: Icon(Icons.calendar_today, size: 18)),
                        child: Text(formatDateTime(_invoiceDate).substring(0, 10)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                      child: Text('Items', style: theme.textTheme.titleMedium)),
                  TextButton.icon(
                    onPressed: _addNewPart,
                    icon: const Icon(Icons.add_box_outlined),
                    label: const Text('New part'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _addExistingPart,
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
                    child: Text(
                      'No items yet. Tap "Add part" for a part already in the '
                      'list, or "New part" for one that is not.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
              for (final line in _lines)
                _LineCard(
                  key: ObjectKey(line),
                  line: line,
                  branchId: widget.branch.id,
                  onChanged: () => setState(() {}),
                  onRemove: () => setState(() => _lines.remove(line)),
                ),
              if (_lines.isNotEmpty)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _updateBuyPrice,
                  onChanged: (v) => setState(() => _updateBuyPrice = v ?? true),
                  title: const Text('Update buy price of these parts'),
                  subtitle: const Text('Saves each unit cost as the part\'s buy price'),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _discount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [_moneyInput],
                decoration: InputDecoration(
                  labelText: 'Discount on invoice ($currencySymbol)',
                  errorText: _discountError,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              Text('Payment to supplier', style: theme.textTheme.titleMedium),
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
                Text('Nothing is paid now. The full total is added to To pay.',
                    style: theme.textTheme.bodySmall)
              else
                TextField(
                  controller: _amountPaid,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [_moneyInput],
                  decoration: InputDecoration(
                    labelText: 'Amount paid now ($currencySymbol)',
                    hintText: 'Full amount',
                    helperText: 'Leave empty if paid in full',
                    errorText: _paidError,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _note,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _totalsBar(theme),
      ),
    );
  }

  Widget _totalsBar(ThemeData theme) {
    Widget row(String label, String value, {TextStyle? style}) => Row(
          children: [
            Expanded(child: Text(label, style: style)),
            Text(value, style: style),
          ],
        );
    final warn = TextStyle(
        color: theme.colorScheme.error, fontWeight: FontWeight.bold);
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
              if (_discountValue > 0) ...[
                row('Subtotal', formatMoney(_subtotal)),
                row('Discount', '- ${formatMoney(_discountValue)}'),
              ],
              row('Total cost', formatMoney(_total),
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              if (_balance > 0 && _lines.isNotEmpty) ...[
                row('Paid now', formatMoney(_paidNow)),
                row('Still to pay supplier', formatMoney(_balance), style: warn),
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
                      : const Icon(Icons.inventory_2_outlined),
                  label: Text(_saving ? 'Saving…' : 'Save stock-in'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One part on the stock-in with editable quantity and unit cost.
class _LineCard extends StatefulWidget {
  const _LineCard({
    super.key,
    required this.line,
    required this.branchId,
    required this.onChanged,
    required this.onRemove,
  });

  final PurchaseLine line;
  final String branchId;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  State<_LineCard> createState() => _LineCardState();
}

class _LineCardState extends State<_LineCard> {
  late final _qty = TextEditingController(text: '${widget.line.quantity}');
  late final _cost =
      TextEditingController(text: widget.line.unitCost.toStringAsFixed(2));

  @override
  void dispose() {
    _qty.dispose();
    _cost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final theme = Theme.of(context);
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line.part.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        '${line.part.partNo == null ? '' : '${line.part.partNo} • '}'
                        '${line.part.quantityAt(widget.branchId)} in stock now',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: widget.onRemove,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _qty,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'Quantity',
                        isDense: true,
                        errorText: line.quantity <= 0 ? 'Enter qty' : null,
                      ),
                      onChanged: (v) {
                        line.quantity = int.tryParse(v) ?? 0;
                        widget.onChanged();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _cost,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [_moneyInput],
                      decoration: const InputDecoration(
                          labelText: 'Unit cost', isDense: true),
                      onChanged: (v) {
                        line.unitCost = roundMoney(double.tryParse(v) ?? 0);
                        widget.onChanged();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 92,
                    child: Text(
                      formatMoney(line.lineTotal),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
