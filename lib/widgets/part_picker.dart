import 'dart:async';

import 'package:flutter/material.dart';

import '../models/part.dart';
import '../services/parts_service.dart';
import '../utils/money.dart';
import 'barcode_scanner.dart';

/// Bottom sheet to search and pick a part. Shows stock at [branchId].
/// With [requireStock], parts with no stock there cannot be picked (billing).
/// [showCost] shows the buy price instead of the sell price (stock-in).
Future<Part?> showPartPicker(
  BuildContext context, {
  required String branchId,
  bool requireStock = false,
  bool showCost = false,
}) {
  return showModalBottomSheet<Part>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PartPicker(
        branchId: branchId, requireStock: requireStock, showCost: showCost),
  );
}

class _PartPicker extends StatefulWidget {
  const _PartPicker({
    required this.branchId,
    required this.requireStock,
    required this.showCost,
  });

  final String branchId;
  final bool requireStock;
  final bool showCost;

  @override
  State<_PartPicker> createState() => _PartPickerState();
}

class _PartPickerState extends State<_PartPicker> {
  final _service = PartsService();
  final _search = TextEditingController();
  Timer? _debounce;
  List<Part> _parts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Scan a code: picks the matching part straight away when it can be
  /// picked, otherwise shows the code as the search.
  Future<void> _scan() async {
    final code = await scanCode(context, title: 'Scan a part');
    if (code == null || !mounted) return;
    try {
      final part = await _service.findByBarcode(code);
      if (!mounted) return;
      if (part != null &&
          (!widget.requireStock || part.quantityAt(widget.branchId) > 0)) {
        Navigator.pop(context, part);
        return;
      }
    } catch (_) {
      // Fall back to searching for the code below.
    }
    _search.text = code;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final parts = await _service.fetchParts(search: _search.text);
      if (mounted) {
        setState(() {
          _parts = parts;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load parts: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.85;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _search,
                autofocus: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search name, part no or code',
                  isDense: true,
                  suffixIcon: IconButton(
                    tooltip: 'Scan barcode / QR',
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: _scan,
                  ),
                ),
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 350), _load);
                },
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            Expanded(
              child: _error != null
                  ? Center(child: Text(_error!, textAlign: TextAlign.center))
                  : ListView.builder(
                      itemCount: _parts.length,
                      itemBuilder: (context, i) {
                        final p = _parts[i];
                        final qty = p.quantityAt(widget.branchId);
                        final price = widget.showCost
                            ? 'cost ${formatMoney(p.buyPrice)}'
                            : formatMoney(p.sellPrice);
                        return ListTile(
                          enabled: !widget.requireStock || qty > 0,
                          title: Text(p.name),
                          subtitle: Text([
                            if (p.partNo != null) p.partNo!,
                            price,
                          ].join(' • ')),
                          trailing: Text(
                              qty > 0 ? '$qty in stock' : 'Out of stock'),
                          onTap: () => Navigator.pop(context, p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
