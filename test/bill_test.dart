import 'package:flutter_test/flutter_test.dart';
import 'package:motor_stock/models/bill.dart';
import 'package:motor_stock/models/part.dart';
import 'package:motor_stock/services/bill_pdf.dart';
import 'package:motor_stock/utils/money.dart';

Map<String, dynamic> _billJson({String status = 'completed'}) => {
      'id': 'b1',
      'bill_no': 'MEL-000042',
      'branch_id': 'mel',
      'customer_name': 'Nimal',
      'customer_phone': null,
      'subtotal': 1850,
      'discount': 50,
      'total': 1800,
      'payment_method': 'bank_transfer',
      'status': status,
      'cancel_reason': null,
      'created_by_email': 'admin@shop.lk',
      'created_at': '2026-11-05T08:30:00Z',
      'branch': {'name': 'MELSIRIPURA', 'address': 'Main Street', 'phone': '037 123 4567'},
      'bill_items': [
        {'part_name': 'Spark plug', 'part_no': null, 'quantity': 1,
         'unit_price': 650, 'line_total': 650, 'sort_order': 1},
        {'part_name': 'Brake pad', 'part_no': 'BP-100', 'quantity': 2,
         'unit_price': 600, 'line_total': 1200, 'sort_order': 0},
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('formatMoney groups thousands and keeps 2 decimals', () {
    expect(formatMoney(0), 'Rs. 0.00');
    expect(formatMoney(650), 'Rs. 650.00');
    expect(formatMoney(1234567.5), 'Rs. 1,234,567.50');
    expect(formatMoney(1000, symbol: false), '1,000.00');
    expect(formatMoney(-25.5), 'Rs. -25.50');
  });

  test('cart subtotal adds line totals', () {
    final lines = [
      CartLine(const Part(id: 'a', name: 'A', sellPrice: 600), 2),
      CartLine(const Part(id: 'b', name: 'B', sellPrice: 0.1), 3),
    ];
    expect(lines[1].lineTotal, 0.3);
    expect(cartSubtotal(lines), 1200.3);
  });

  test('Bill.fromJson reads branch, items in order and status', () {
    final bill = Bill.fromJson(_billJson());
    expect(bill.billNo, 'MEL-000042');
    expect(bill.branchPhone, '037 123 4567');
    expect(bill.paymentMethod, PaymentMethod.bankTransfer);
    expect(bill.items.map((i) => i.partName), ['Brake pad', 'Spark plug']);
    expect(bill.itemCount, 3);
    expect(bill.cancelled, isFalse);
    expect(Bill.fromJson(_billJson(status: 'cancelled')).cancelled, isTrue);
  });

  test('bills from before payments count as paid in full', () {
    final bill = Bill.fromJson(_billJson());
    expect(bill.amountPaid, 1800);
    expect(bill.balance, 0);
    expect(bill.hasBalance, isFalse);
  });

  test('part-paid bill has a balance and sorted payments', () {
    final bill = Bill.fromJson({
      ..._billJson(),
      'payment_method': 'cash',
      'amount_paid': 1000,
      'payment_status': 'partial',
      'bill_payments': [
        {'amount': 300, 'method': 'bank_transfer', 'note': null,
         'created_by_email': 'a@b.c', 'created_at': '2026-11-06T09:00:00Z'},
        {'amount': 700, 'method': 'cash', 'note': 'at counter',
         'created_by_email': 'a@b.c', 'created_at': '2026-11-05T08:30:00Z'},
      ],
    });
    expect(bill.paymentStatus, PaymentStatus.partial);
    expect(bill.balance, 800);
    expect(bill.hasBalance, isTrue);
    expect(bill.payments.map((p) => p.amount), [700, 300]);
    expect(bill.payments.last.method, PaymentMethod.bankTransfer);
  });

  test('cancelled bill has nothing to collect', () {
    final bill = Bill.fromJson({
      ..._billJson(status: 'cancelled'),
      'amount_paid': 0,
      'payment_status': 'unpaid',
      'payment_method': 'credit',
    });
    expect(bill.paymentMethod, PaymentMethod.credit);
    expect(bill.balance, 1800);
    expect(bill.hasBalance, isFalse);
  });

  test('receiving methods exclude credit', () {
    expect(PaymentMethod.receiving, isNot(contains(PaymentMethod.credit)));
  });

  test('PDF with a balance due is generated', () async {
    final bytes = await buildBillPdf(Bill.fromJson({
      ..._billJson(),
      'amount_paid': 500,
      'payment_status': 'partial',
      'bill_payments': [
        {'amount': 500, 'method': 'cash', 'note': null,
         'created_by_email': null, 'created_at': '2026-11-05T08:30:00Z'},
      ],
    }));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('part price on a bill starts at the sell price and can be changed', () {
    final line = CartLine(const Part(id: 'a', name: 'Chain kit', sellPrice: 3200), 2);
    expect(line.unitPrice, 3200);
    expect(line.priceChanged, isFalse);
    expect(line.lineTotal, 6400);

    line.unitPrice = 2950;
    expect(line.priceChanged, isTrue);
    expect(line.lineTotal, 5900);
    expect(cartSubtotal([line]), 5900);
  });

  test('service lines add to the subtotal without a part', () {
    final services = [
      ServiceLine(serviceId: 's1', name: 'Full service', price: 2500),
      ServiceLine(name: 'Clutch cable fitting', price: 350.5, quantity: 2),
    ];
    expect(services[1].lineTotal, 701);
    expect(servicesSubtotal(services), 3201);
  });

  test('bill with parts and services splits items and totals', () {
    final bill = Bill.fromJson({
      ..._billJson(),
      'bike_no': 'WP BCD-1234',
      'subtotal': 4850,
      'parts_total': 1850,
      'services_total': 3000,
      'bill_items': [
        {'item_type': 'part', 'part_name': 'Brake pad', 'part_no': 'BP-100',
         'quantity': 2, 'unit_price': 600, 'line_total': 1200, 'sort_order': 1},
        {'item_type': 'service', 'part_name': 'Full service', 'part_no': null,
         'quantity': 1, 'unit_price': 2500, 'line_total': 2500, 'sort_order': 2},
        {'item_type': 'service', 'part_name': 'Brake adjustment', 'part_no': null,
         'quantity': 1, 'unit_price': 500, 'line_total': 500, 'sort_order': 3},
      ],
    });
    expect(bill.bikeNo, 'WP BCD-1234');
    expect(bill.partItems.map((i) => i.partName), ['Brake pad']);
    expect(bill.serviceItems.map((i) => i.partName),
        ['Full service', 'Brake adjustment']);
    expect(bill.servicesTotal, 3000);
  });

  test('older bills without a type are parts only', () {
    final bill = Bill.fromJson(_billJson());
    expect(bill.serviceItems, isEmpty);
    expect(bill.partsTotal, bill.subtotal);
    expect(bill.servicesTotal, 0);
  });

  test('PDF with parts and services is generated', () async {
    final bytes = await buildBillPdf(Bill.fromJson({
      ..._billJson(),
      'bike_no': 'WP BCD-1234',
      'parts_total': 1850,
      'services_total': 2500,
      'subtotal': 4350,
      'bill_items': [
        {'item_type': 'part', 'part_name': 'Brake pad', 'part_no': null,
         'quantity': 1, 'unit_price': 1850, 'line_total': 1850, 'sort_order': 0},
        {'item_type': 'service', 'part_name': 'Full service', 'part_no': null,
         'quantity': 1, 'unit_price': 2500, 'line_total': 2500, 'sort_order': 1},
      ],
    }));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('bill PDF is generated', () async {
    final bytes = await buildBillPdf(Bill.fromJson(_billJson(status: 'cancelled')));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });
}
