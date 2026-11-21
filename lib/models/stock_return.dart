import 'bill.dart';

/// Customer return (against a bill) or supplier return (against a stock-in).
enum ReturnKind {
  customer('Customer return', 'bill_returns', 'bill_return_items'),
  supplier('Supplier return', 'purchase_returns', 'purchase_return_items');

  const ReturnKind(this.label, this.table, this.itemsTable);
  final String label;
  final String table;
  final String itemsTable;
}

/// A line of a bill or stock-in that can be returned.
class ReturnableLine {
  const ReturnableLine({
    required this.itemId,
    required this.name,
    this.partNo,
    required this.quantity,
    required this.returnedQty,
    required this.unitPrice,
    this.partGone = false,
  });

  final String itemId;
  final String name;
  final String? partNo;

  /// Sold (bill) or received (stock-in).
  final int quantity;
  final int returnedQty;

  /// Unit price on the bill, or unit cost on the stock-in.
  final double unitPrice;

  /// The part was deleted from the app, so stock can't move.
  final bool partGone;

  int get returnable => partGone ? 0 : quantity - returnedQty;
}

/// What a return is worth and how much money goes back. Mirrors
/// return_bill_items / return_purchase_items in supabase/012_returns.sql.
class ReturnMoney {
  const ReturnMoney({required this.value, required this.refund});

  final double value;
  final double refund;

  /// [chosen] is line index -> quantity to return now.
  /// [returnsEverything] is true when, after this return, every line of the
  /// bill / stock-in is fully returned (and there are no service lines).
  static ReturnMoney of({
    required List<ReturnableLine> lines,
    required Map<int, int> chosen,
    required double subtotal,
    required double discount,
    required double total,
    required double returnedTotal,
    required double amountPaid,
    required bool returnsEverything,
  }) {
    final ratio = subtotal > 0 ? 1 - discount / subtotal : 1.0;
    var value = 0.0;
    chosen.forEach((i, qty) {
      if (qty > 0) value += roundMoney(lines[i].unitPrice * qty * ratio);
    });
    value = roundMoney(value);
    final left = roundMoney(total - returnedTotal);
    if (returnsEverything || value > left) value = left;
    final net = roundMoney(total - returnedTotal - value);
    final refund = amountPaid > net ? roundMoney(amountPaid - net) : 0.0;
    return ReturnMoney(value: value, refund: refund);
  }
}

/// One returned line, as saved.
class ReturnedItem {
  const ReturnedItem({
    required this.name,
    this.partNo,
    required this.quantity,
    required this.value,
  });

  final String name;
  final String? partNo;
  final int quantity;
  final double value;

  factory ReturnedItem.fromJson(Map<String, dynamic> json) => ReturnedItem(
        name: json['part_name'] as String,
        partNo: json['part_no'] as String?,
        quantity: (json['quantity'] as num).toInt(),
        value: (json['value'] as num).toDouble(),
      );
}

/// A saved return.
class StockReturn {
  const StockReturn({
    required this.id,
    required this.kind,
    required this.reason,
    required this.value,
    required this.refundAmount,
    this.refundMethod,
    this.by,
    required this.createdAt,
    this.items = const [],
    this.docId,
    this.docNo,
    this.otherParty,
  });

  final String id;
  final ReturnKind kind;
  final String reason;

  /// What the returned parts were worth.
  final double value;

  /// Money given back (to the customer, or by the supplier).
  final double refundAmount;
  final PaymentMethod? refundMethod;
  final String? by;
  final DateTime createdAt;
  final List<ReturnedItem> items;

  /// Bill / stock-in id and number, and customer / supplier name (history).
  final String? docId;
  final String? docNo;
  final String? otherParty;

  int get itemCount => items.fold(0, (s, i) => s + i.quantity);

  /// Columns for a return embedded in a bill or stock-in.
  static String embedded(ReturnKind kind) => '${kind.table}(id, reason, '
      'return_value, refund_amount, refund_method, created_by_email, created_at, '
      '${kind.itemsTable}(part_name, part_no, quantity, value))';

  /// Columns for the returns history.
  static String historyColumns(ReturnKind kind) => switch (kind) {
        ReturnKind.customer => 'id, reason, return_value, refund_amount, '
            'refund_method, created_by_email, created_at, '
            'bill_return_items(part_name, part_no, quantity, value), '
            'bill:bill_id(id, bill_no, customer_name)',
        ReturnKind.supplier => 'id, reason, return_value, refund_amount, '
            'refund_method, created_by_email, created_at, '
            'purchase_return_items(part_name, part_no, quantity, value), '
            'purchase:purchase_id(id, purchase_no, supplier:supplier_id(name))',
      };

  factory StockReturn.fromJson(Map<String, dynamic> json, ReturnKind kind) {
    final doc = (json['bill'] ?? json['purchase']) as Map<String, dynamic>?;
    final supplier = doc?['supplier'] as Map<String, dynamic>?;
    final method = json['refund_method'] as String?;
    return StockReturn(
      id: json['id'] as String,
      kind: kind,
      reason: json['reason'] as String? ?? '',
      value: (json['return_value'] as num).toDouble(),
      refundAmount: (json['refund_amount'] as num?)?.toDouble() ?? 0,
      refundMethod: method == null ? null : PaymentMethod.parse(method),
      by: json['created_by_email'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      items: (json[kind.itemsTable] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(ReturnedItem.fromJson)
          .toList(),
      docId: doc?['id'] as String?,
      docNo: (doc?['bill_no'] ?? doc?['purchase_no']) as String?,
      otherParty: (doc?['customer_name'] ?? supplier?['name']) as String?,
    );
  }

  static List<StockReturn> listFrom(dynamic raw, ReturnKind kind) =>
      (raw as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map((j) => StockReturn.fromJson(j, kind))
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
}
