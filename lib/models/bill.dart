import 'part.dart';

enum PaymentMethod {
  cash('cash', 'Cash', 'Cash'),
  card('card', 'Card', 'Card'),
  bankTransfer('bank_transfer', 'Bank transfer', 'Bank'),
  // Nothing paid when the bill was issued.
  credit('credit', 'Credit (pay later)', 'Credit');

  const PaymentMethod(this.value, this.label, this.shortLabel);

  final String value;
  final String label;
  final String shortLabel;

  /// Methods money can actually be received by.
  static const receiving = [cash, card, bankTransfer];

  static PaymentMethod parse(String? value) =>
      PaymentMethod.values.where((m) => m.value == value).firstOrNull ??
      PaymentMethod.cash;
}

enum PaymentStatus {
  paid('paid', 'Paid'),
  partial('partial', 'Part paid'),
  unpaid('unpaid', 'Unpaid');

  const PaymentStatus(this.value, this.label);

  final String value;
  final String label;

  static PaymentStatus parse(String? value) =>
      PaymentStatus.values.where((s) => s.value == value).firstOrNull ??
      PaymentStatus.paid;
}

/// One amount received against a bill.
class BillPayment {
  final double amount;
  final PaymentMethod method;
  final String? note;
  final String? takenBy;
  final DateTime createdAt;

  const BillPayment({
    required this.amount,
    required this.method,
    this.note,
    this.takenBy,
    required this.createdAt,
  });

  factory BillPayment.fromJson(Map<String, dynamic> json) => BillPayment(
        amount: (json['amount'] as num).toDouble(),
        method: PaymentMethod.parse(json['method'] as String?),
        note: json['note'] as String?,
        takenBy: json['created_by_email'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );
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

/// A service from the shop's service list (Lists & branches > Services).
class ServiceItem {
  final String id;
  final String name;
  final double defaultPrice;
  final bool active;

  const ServiceItem({
    required this.id,
    required this.name,
    this.defaultPrice = 0,
    this.active = true,
  });

  factory ServiceItem.fromJson(Map<String, dynamic> json) => ServiceItem(
        id: json['id'] as String,
        name: json['name'] as String,
        defaultPrice: (json['default_price'] as num?)?.toDouble() ?? 0,
        active: json['active'] as bool? ?? true,
      );
}

/// A service charge on a bill that has not been saved yet. Does not use stock.
class ServiceLine {
  final String? serviceId; // null for "Other"
  String name;
  double price;
  int quantity;

  ServiceLine({this.serviceId, required this.name, required this.price, this.quantity = 1});

  double get lineTotal => roundMoney(price * quantity);
}

double servicesSubtotal(Iterable<ServiceLine> lines) =>
    roundMoney(lines.fold(0.0, (sum, l) => sum + l.lineTotal));

class BillItem {
  /// Part name, or the service description for service lines.
  final String partName;
  final String? partNo;
  final bool isService;
  final int quantity;
  final double unitPrice;
  final double lineTotal;

  const BillItem({
    required this.partName,
    this.partNo,
    this.isService = false,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  factory BillItem.fromJson(Map<String, dynamic> json) => BillItem(
        partName: json['part_name'] as String,
        partNo: json['part_no'] as String?,
        isService: json['item_type'] == 'service',
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
  final String? bikeNo;
  final double subtotal;
  // Split of the subtotal (before discount).
  final double partsTotal;
  final double servicesTotal;
  final double discount;
  final double total;
  final PaymentMethod paymentMethod;
  final double amountPaid;
  final PaymentStatus paymentStatus;
  final bool cancelled;
  final String? cancelReason;
  final String? issuedBy;
  final DateTime createdAt;
  final List<BillItem> items;
  final List<BillPayment> payments;

  const Bill({
    required this.id,
    required this.billNo,
    required this.branchId,
    required this.branchName,
    this.branchAddress,
    this.branchPhone,
    this.customerName,
    this.customerPhone,
    this.bikeNo,
    required this.subtotal,
    this.partsTotal = 0,
    this.servicesTotal = 0,
    required this.discount,
    required this.total,
    required this.paymentMethod,
    this.amountPaid = 0,
    this.paymentStatus = PaymentStatus.paid,
    this.cancelled = false,
    this.cancelReason,
    this.issuedBy,
    required this.createdAt,
    this.items = const [],
    this.payments = const [],
  });

  static const listColumns = 'id, bill_no, branch_id, customer_name, '
      'customer_phone, bike_no, subtotal, parts_total, services_total, '
      'discount, total, payment_method, status, '
      'amount_paid, payment_status, '
      'cancel_reason, created_by_email, created_at, '
      'branch:branch_id(name, address, phone)';

  static const detailColumns = '$listColumns, '
      'bill_items(item_type, part_name, part_no, quantity, unit_price, line_total, sort_order), '
      'bill_payments(amount, method, note, created_by_email, created_at)';

  int get itemCount => items.fold(0, (sum, i) => sum + i.quantity);

  List<BillItem> get partItems => items.where((i) => !i.isService).toList();
  List<BillItem> get serviceItems => items.where((i) => i.isService).toList();

  double get balance => roundMoney(total - amountPaid);

  /// Money still to be collected (0 for cancelled bills).
  bool get hasBalance => !cancelled && balance > 0;

  int get daysOld => DateTime.now().difference(createdAt).inDays;

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
      bikeNo: json['bike_no'] as String?,
      subtotal: (json['subtotal'] as num).toDouble(),
      // Bills from before services existed were parts only.
      partsTotal: (json['parts_total'] as num?)?.toDouble() ??
          (json['subtotal'] as num).toDouble(),
      servicesTotal: (json['services_total'] as num?)?.toDouble() ?? 0,
      discount: (json['discount'] as num?)?.toDouble() ?? 0,
      total: (json['total'] as num).toDouble(),
      paymentMethod: PaymentMethod.parse(json['payment_method'] as String?),
      // Bills from before payments were tracked count as paid in full.
      amountPaid: (json['amount_paid'] as num?)?.toDouble() ??
          (json['total'] as num).toDouble(),
      paymentStatus: PaymentStatus.parse(json['payment_status'] as String?),
      cancelled: json['status'] == 'cancelled',
      cancelReason: json['cancel_reason'] as String?,
      issuedBy: json['created_by_email'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      items: rawItems.map(BillItem.fromJson).toList(),
      payments: (json['bill_payments'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(BillPayment.fromJson)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
    );
  }
}
