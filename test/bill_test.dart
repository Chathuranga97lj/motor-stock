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

  test('bill PDF is generated', () async {
    final bytes = await buildBillPdf(Bill.fromJson(_billJson(status: 'cancelled')));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });
}
