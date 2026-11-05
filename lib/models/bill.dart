import 'part.dart';

enum PaymentMethod {
  cash('cash', 'Cash'),
  card('card', 'Card'),
  bankTransfer('bank_transfer', 'Bank transfer');

  const PaymentMethod(this.value, this.label);

  final String value;
  final String label;

  static PaymentMethod parse(String? value) =>
      PaymentMethod.values.where((m) => m.value == value).firstOrNull ??
      PaymentMethod.cash;
}

/// A part on a bill that has not been saved yet.
class CartLine {
  final Part part;
  int quantity;

  CartLine(this.part, [this.quantity = 1]);

  double get lineTotal => roundMoney(part.sellPrice * quantity);
}

double roundMoney(double v) => (v * 100).roundToDouble() / 100;

double cartSubtotal(Iterable<CartLine> lines) =>
    roundMoney(lines.fold(0.0, (sum, l) => sum + l.lineTotal));

class BillItem {
  final String partName;
  final String? partNo;
  final int quantity;
  final double unitPrice;
  final double lineTotal;

  const BillItem({
    required this.partName,
    this.partNo,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  factory BillItem.fromJson(Map<String, dynamic> json) => BillItem(
        partName: json['part_name'] as String,
        partNo: json['part_no'] as String?,
        quantity: (json['quantity'] as num).toInt(),
        unitPrice: (json['unit_price'] as num).toDouble(),
        lineTotal: (json['line_total'] as num).toDouble(),
      );
}

class Bill {
  final String id;
  final String billNo;
  final String branchId;
  final String branchName;
  final String? branchAddress;
  final String? branchPhone;
  final String? customerName;
  final String? customerPhone;
  final double subtotal;
  final double discount;
  final double total;
  final PaymentMethod paymentMethod;
  final bool cancelled;
  final String? cancelReason;
  final String? issuedBy;
  final DateTime createdAt;
  final List<BillItem> items;

  const Bill({
    required this.id,
    required this.billNo,
    required this.branchId,
    required this.branchName,
    this.branchAddress,
    this.branchPhone,
    this.customerName,
    this.customerPhone,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.paymentMethod,
    this.cancelled = false,
    this.cancelReason,
    this.issuedBy,
    required this.createdAt,
    this.items = const [],
  });

  static const listColumns = 'id, bill_no, branch_id, customer_name, '
      'customer_phone, subtotal, discount, total, payment_method, status, '
      'cancel_reason, created_by_email, created_at, '
      'branch:branch_id(name, address, phone)';

  static const detailColumns = '$listColumns, '
      'bill_items(part_name, part_no, quantity, unit_price, line_total, sort_order)';

  int get itemCount => items.fold(0, (sum, i) => sum + i.quantity);

  factory Bill.fromJson(Map<String, dynamic> json) {
    final branch = json['branch'] as Map<String, dynamic>?;
    final rawItems = (json['bill_items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .toList()
      ..sort((a, b) =>
          ((a['sort_order'] as num?) ?? 0).compareTo((b['sort_order'] as num?) ?? 0));
    return Bill(
      id: json['id'] as String,
      billNo: json['bill_no'] as String,
      branchId: json['branch_id'] as String,
      branchName: branch?['name'] as String? ?? '',
      branchAddress: branch?['address'] as String?,
      branchPhone: branch?['phone'] as String?,
      customerName: json['customer_name'] as String?,
      customerPhone: json['customer_phone'] as String?,
      subtotal: (json['subtotal'] as num).toDouble(),
      discount: (json['discount'] as num?)?.toDouble() ?? 0,
      total: (json['total'] as num).toDouble(),
      paymentMethod: PaymentMethod.parse(json['payment_method'] as String?),
      cancelled: json['status'] == 'cancelled',
      cancelReason: json['cancel_reason'] as String?,
      issuedBy: json['created_by_email'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      items: rawItems.map(BillItem.fromJson).toList(),
    );
  }
}
