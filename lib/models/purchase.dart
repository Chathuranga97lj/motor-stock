import 'bill.dart';
import 'part.dart';

class Supplier {
  final String id;
  final String name;
  final String? phone;
  final String? address;
  final String? note;

  const Supplier({
    required this.id,
    required this.name,
    this.phone,
    this.address,
    this.note,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
        id: json['id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String?,
        address: json['address'] as String?,
        note: json['note'] as String?,
      );
}

/// A part on a stock-in that has not been saved yet.
class PurchaseLine {
  final Part part;
  int quantity;
  double unitCost;

  PurchaseLine(this.part, {this.quantity = 1, double? unitCost})
      : unitCost = unitCost ?? part.buyPrice;

  double get lineTotal => roundMoney(unitCost * quantity);
}

double purchaseSubtotal(Iterable<PurchaseLine> lines) =>
    roundMoney(lines.fold(0.0, (sum, l) => sum + l.lineTotal));

class PurchaseItem {
  final String partName;
  final String? partNo;
  final int quantity;
  final double unitCost;
  final double lineTotal;

  const PurchaseItem({
    required this.partName,
    this.partNo,
    required this.quantity,
    required this.unitCost,
    required this.lineTotal,
  });

  factory PurchaseItem.fromJson(Map<String, dynamic> json) => PurchaseItem(
        partName: json['part_name'] as String,
        partNo: json['part_no'] as String?,
        quantity: (json['quantity'] as num).toInt(),
        unitCost: (json['unit_cost'] as num).toDouble(),
        lineTotal: (json['line_total'] as num).toDouble(),
      );
}

/// A saved stock-in from a supplier.
class Purchase {
  final String id;
  final String purchaseNo;
  final String branchId;
  final String branchName;
  final String supplierId;
  final String supplierName;
  final String? supplierPhone;
  final String? invoiceNo;
  final DateTime invoiceDate;
  final String? note;
  final double subtotal;
  final double discount;
  final double total;
  final PaymentMethod paymentMethod;
  final double amountPaid;
  final PaymentStatus paymentStatus;
  final bool cancelled;
  final String? cancelReason;
  final String? enteredBy;
  final DateTime createdAt;
  final List<PurchaseItem> items;
  final List<BillPayment> payments;

  const Purchase({
    required this.id,
    required this.purchaseNo,
    required this.branchId,
    required this.branchName,
    required this.supplierId,
    required this.supplierName,
    this.supplierPhone,
    this.invoiceNo,
    required this.invoiceDate,
    this.note,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.paymentMethod,
    required this.amountPaid,
    required this.paymentStatus,
    this.cancelled = false,
    this.cancelReason,
    this.enteredBy,
    required this.createdAt,
    this.items = const [],
    this.payments = const [],
  });

  static const listColumns = 'id, purchase_no, branch_id, supplier_id, '
      'invoice_no, invoice_date, note, subtotal, discount, total, '
      'payment_method, amount_paid, payment_status, status, cancel_reason, '
      'created_by_email, created_at, '
      'branch:branch_id(name), supplier:supplier_id(name, phone)';

  static const detailColumns = '$listColumns, '
      'purchase_items(part_name, part_no, quantity, unit_cost, line_total, sort_order), '
      'purchase_payments(amount, method, note, created_by_email, created_at)';

  double get balance => roundMoney(total - amountPaid);

  /// Money still owed to the supplier (0 for cancelled stock-ins).
  bool get hasBalance => !cancelled && balance > 0;

  int get itemCount => items.fold(0, (sum, i) => sum + i.quantity);

  int get daysOld => DateTime.now().difference(createdAt).inDays;

  factory Purchase.fromJson(Map<String, dynamic> json) {
    final supplier = json['supplier'] as Map<String, dynamic>?;
    final branch = json['branch'] as Map<String, dynamic>?;
    final rawItems = (json['purchase_items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .toList()
      ..sort((a, b) =>
          ((a['sort_order'] as num?) ?? 0).compareTo((b['sort_order'] as num?) ?? 0));
    return Purchase(
      id: json['id'] as String,
      purchaseNo: json['purchase_no'] as String,
      branchId: json['branch_id'] as String,
      branchName: branch?['name'] as String? ?? '',
      supplierId: json['supplier_id'] as String,
      supplierName: supplier?['name'] as String? ?? '?',
      supplierPhone: supplier?['phone'] as String?,
      invoiceNo: json['invoice_no'] as String?,
      invoiceDate: DateTime.parse(json['invoice_date'] as String),
      note: json['note'] as String?,
      subtotal: (json['subtotal'] as num).toDouble(),
      discount: (json['discount'] as num?)?.toDouble() ?? 0,
      total: (json['total'] as num).toDouble(),
      paymentMethod: PaymentMethod.parse(json['payment_method'] as String?),
      amountPaid: (json['amount_paid'] as num).toDouble(),
      paymentStatus: PaymentStatus.parse(json['payment_status'] as String?),
      cancelled: json['status'] == 'cancelled',
      cancelReason: json['cancel_reason'] as String?,
      enteredBy: json['created_by_email'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      items: rawItems.map(PurchaseItem.fromJson).toList(),
      payments: (json['purchase_payments'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(BillPayment.fromJson)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
    );
  }
}
