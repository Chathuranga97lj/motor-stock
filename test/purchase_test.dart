import 'package:flutter_test/flutter_test.dart';
import 'package:motor_stock/models/bill.dart';
import 'package:motor_stock/models/part.dart';
import 'package:motor_stock/models/purchase.dart';

void main() {
  test('stock-in line defaults cost to the part buy price', () {
    final line = PurchaseLine(const Part(id: 'p', name: 'Brake pad', buyPrice: 450));
    expect(line.unitCost, 450);
    line.quantity = 10;
    expect(line.lineTotal, 4500);

    final lines = [
      line,
      PurchaseLine(const Part(id: 'q', name: 'Oil'), quantity: 3, unitCost: 0.35),
    ];
    expect(purchaseSubtotal(lines), 4501.05);
  });

  test('Purchase.fromJson reads supplier, items, payments and balance', () {
    final p = Purchase.fromJson({
      'id': 'pu1',
      'purchase_no': 'PUR-IBB-000007',
      'branch_id': 'ibb',
      'supplier_id': 's1',
      'invoice_no': 'INV-889',
      'invoice_date': '2026-11-04',
      'note': null,
      'subtotal': 10000,
      'discount': 500,
      'total': 9500,
      'payment_method': 'cash',
      'amount_paid': 4000,
      'payment_status': 'partial',
      'status': 'completed',
      'cancel_reason': null,
      'created_by_email': 'owner@shop.lk',
      'created_at': '2026-11-05T08:30:00Z',
      'branch': {'name': 'IBBAGAMUWA'},
      'supplier': {'name': 'Lanka Moto Parts', 'phone': '011 555 1234'},
      'purchase_items': [
        {'part_name': 'Chain kit', 'part_no': 'CK-1', 'quantity': 2,
         'unit_cost': 3000, 'line_total': 6000, 'sort_order': 2},
        {'part_name': 'Brake pad', 'part_no': null, 'quantity': 10,
         'unit_cost': 400, 'line_total': 4000, 'sort_order': 1},
      ],
      'purchase_payments': [
        {'amount': 4000, 'method': 'cash', 'note': null,
         'created_by_email': null, 'created_at': '2026-11-05T08:30:00Z'},
      ],
    });
    expect(p.supplierName, 'Lanka Moto Parts');
    expect(p.invoiceDate, DateTime(2026, 11, 4));
    expect(p.items.map((i) => i.partName), ['Brake pad', 'Chain kit']);
    expect(p.itemCount, 12);
    expect(p.balance, 5500);
    expect(p.hasBalance, isTrue);
    expect(p.paymentStatus, PaymentStatus.partial);
    expect(p.payments.single.amount, 4000);
  });
}
