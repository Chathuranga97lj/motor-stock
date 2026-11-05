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
  final _services = <ServiceLine>[];
  List<ServiceItem> _serviceCatalog = [];
  final _customerName = TextEditingController();
  final _customerPhone = TextEditingController();
  final _bikeNo = TextEditingController();
  final _discount = TextEditingController();
  // Empty means the full total is paid now.
  final _amountPaid = TextEditingController();
  PaymentMethod _payment = PaymentMethod.cash;
  bool _saving = false;
  bool _triedSave = false;

  @override
  void initState() {
    super.initState();
    _billService.fetchServices().then((s) {
      if (mounted) setState(() => _serviceCatalog = s);
    }).catchError((_) {
      // The list can still be filled with "Other" services.
    });
  }

  @override
  void dispose() {
    for (final c in [_customerName, _customerPhone, _bikeNo, _discount, _amountPaid]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _hasItems => _lines.isNotEmpty || _services.isNotEmpty;
  double get _partsSubtotal => cartSubtotal(_lines);
  double get _servicesSubtotal => servicesSubtotal(_services);
  double get _subtotal => roundMoney(_partsSubtotal + _servicesSubtotal);
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
      _hasItems &&
      _services.every((s) => s.name.trim().isNotEmpty) &&
      _discountError == null &&
      _paidError == null;

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

  /// Pick a service from the list (its standard price can be changed on the
  /// line), or "Other" for work that is not on the list.
  Future<void> _addService() async {
    final picked = await showModalBottomSheet<({ServiceItem? item})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Add service')),
              for (final s in _serviceCatalog)
                ListTile(
                  leading: const Icon(Icons.build_outlined),
                  title: Text(s.name),
                  trailing: Text(formatMoney(s.defaultPrice)),
                  onTap: () => Navigator.pop(context, (item: s)),
                ),
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: const Text('Other'),
                subtitle: const Text('Type a description and charge'),
                onTap: () => Navigator.pop(context, (item: null)),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    final item = picked.item;
    setState(() => _services.add(item == null
        ? ServiceLine(name: '', price: 0)
        : ServiceLine(serviceId: item.id, name: item.name, price: item.defaultPrice)));
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
        services: _services,
        paymentMethod: _payment,
        discount: _discountValue,
        amountPaid: _paidNow,
        customerName: _customerName.text,
        customerPhone: _customerPhone.text,
        bikeNo: _bikeNo.text,
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
      canPop: !_hasItems || _saving,
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
                    child: FilledButton.tonalIcon(
                      onPressed: _addPart,
                      icon: const Icon(Icons.add),
                      label: const Text('Add part'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _addService,
                      icon: const Icon(Icons.build_outlined),
                      label: const Text('Add service'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!_hasItems)
                Card.outlined(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                        'No items yet. Add parts, a service, or both.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium),
                  ),
                ),
              if (_lines.isNotEmpty) ...[
                Text('Parts', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                for (final line in _lines) _lineTile(line),
              ],
              if (_services.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Service / labour', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                for (final s in _services)
                  _ServiceLineCard(
                    key: ObjectKey(s),
                    line: s,
                    showError: _triedSave,
                    onChanged: () => setState(() {}),
                    onRemove: () => setState(() => _services.remove(s)),
                  ),
              ],
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
              const SizedBox(height: 12),
              TextField(
                controller: _bikeNo,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Bike number (optional)',
                  hintText: 'e.g. WP BCD-1234',
                ),
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
              if (_lines.isNotEmpty && _services.isNotEmpty) ...[
                row('Parts', formatMoney(_partsSubtotal)),
                row('Service', formatMoney(_servicesSubtotal)),
              ] else
                row('Subtotal', formatMoney(_subtotal)),
              if (_discountValue > 0)
                row('Discount', '- ${formatMoney(_discountValue)}'),
              row('Total', formatMoney(_total), bold: true),
              if (_balance > 0 && _hasItems) ...[
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

/// One service charge with an editable description and charge.
class _ServiceLineCard extends StatefulWidget {
  const _ServiceLineCard({
    super.key,
    required this.line,
    required this.showError,
    required this.onChanged,
    required this.onRemove,
  });

  final ServiceLine line;
  final bool showError;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  State<_ServiceLineCard> createState() => _ServiceLineCardState();
}

class _ServiceLineCardState extends State<_ServiceLineCard> {
  late final _name = TextEditingController(text: widget.line.name);
  late final _price = TextEditingController(
      text: widget.line.price == 0 ? '' : widget.line.price.toStringAsFixed(2));

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final fromList = line.serviceId != null;
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: fromList
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(line.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    )
                  : TextField(
                      controller: _name,
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: 'Service description',
                        isDense: true,
                        errorText: widget.showError && line.name.trim().isEmpty
                            ? 'Required'
                            : null,
                      ),
                      onChanged: (v) {
                        line.name = v;
                        widget.onChanged();
                      },
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _price,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                    labelText: 'Charge ($currencySymbol)', isDense: true),
                onChanged: (v) {
                  line.price = roundMoney(double.tryParse(v) ?? 0);
                  widget.onChanged();
                },
              ),
            ),
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline),
              onPressed: widget.onRemove,
            ),
          ],
        ),
      ),
    );
  }
}
