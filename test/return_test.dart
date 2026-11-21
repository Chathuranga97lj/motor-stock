import 'package:flutter_test/flutter_test.dart';
import 'package:motor_stock/models/bill.dart';
import 'package:motor_stock/models/purchase.dart';
import 'package:motor_stock/models/stock_return.dart';
import 'package:motor_stock/services/bill_pdf.dart';

const _a = ReturnableLine(
    itemId: 'ia', name: 'Part A', quantity: 2, returnedQty: 0, unitPrice: 500);
const _b = ReturnableLine(
    itemId: 'ib', name: 'Part B', quantity: 1, returnedQty: 0, unitPrice: 300);

/// Bill: 2 x Part A @500, 1 x Part B @300, a 200 service, 100 discount,
/// 1 x Part A already returned (466.67 back by cash).
Map<String, dynamic> _billJson() => {
      'id': 'b1',
      'bill_no': 'IBB-000001',
      'branch_id': 'ibb',
      'customer_name': 'Kamal',
      'subtotal': 1500,
      'discount': 100,
      'total': 1400,
      'returned_total': 466.67,
      'payment_method': 'cash',
      'amount_paid': 933.33,
      'payment_status': 'paid',
      'status': 'completed',
      'created_at': '2026-11-21T08:00:00Z',
      'branch': {'name': 'IBBAGAMUWA'},
      'bill_items': [
        {'id': 'ia', 'part_id': 'pa', 'item_type': 'part', 'part_name': 'Part A',
         'quantity': 2, 'returned_qty': 1, 'unit_price': 500, 'line_total': 1000,
         'sort_order': 0},
        {'id': 'ib', 'part_id': 'pb', 'item_type': 'part', 'part_name': 'Part B',
         'quantity': 1, 'returned_qty': 0, 'unit_price': 300, 'line_total': 300,
         'sort_order': 1},
        {'id': 'is', 'part_id': null, 'item_type': 'service', 'part_name': 'Oil change',
         'quantity': 1, 'returned_qty': 0, 'unit_price': 200, 'line_total': 200,
         'sort_order': 2},
      ],
      'bill_payments': [
        {'amount': 1400, 'method': 'cash', 'created_at': '2026-11-21T08:00:00Z'},
      ],
      'bill_returns': [
        {
          'id': 'r1',
          'reason': 'Faulty',
          'return_value': 466.67,
          'refund_amount': 466.67,
          'refund_method': 'cash',
          'created_by_email': 'boss@shop.lk',
          'created_at': '2026-11-21T09:00:00Z',
          'bill_return_items': [
            {'part_name': 'Part A', 'part_no': null, 'quantity': 1, 'value': 466.67},
          ],
        },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReturnMoney (same cases as the database test)', () {
    test('paid bill with a discount: line less its share, refunded', () {
      final m = ReturnMoney.of(
        lines: const [_a, _b],
        chosen: {0: 1},
        subtotal: 1500,
        discount: 100,
        total: 1400,
        returnedTotal: 0,
        amountPaid: 1400,
        returnsEverything: false,
      );
      expect(m.value, 466.67);
      expect(m.refund, 466.67);
    });

    test('unpaid bill: comes off what is owed, nothing refunded', () {
      final m = ReturnMoney.of(
        lines: const [ReturnableLine(
            itemId: 'x', name: 'A', quantity: 2, returnedQty: 0, unitPrice: 500)],
        chosen: {0: 1},
        subtotal: 1000,
        discount: 0,
        total: 1000,
        returnedTotal: 0,
        amountPaid: 0,
        returnsEverything: false,
      );
      expect(m.value, 500);
      expect(m.refund, 0);
    });

    test('everything returned: the whole remaining total, no cents left', () {
      final m = ReturnMoney.of(
        lines: const [ReturnableLine(
            itemId: 'x', name: 'B', quantity: 3, returnedQty: 0, unitPrice: 300)],
        chosen: {0: 3},
        subtotal: 900,
        discount: 100,
        total: 800,
        returnedTotal: 0,
        amountPaid: 800,
        returnsEverything: true,
      );
      expect(m.value, 800);
      expect(m.refund, 800);
    });

    test('part paid: refund only what was paid above the new total', () {
      // Supplier stock-in 5 x 400 = 2000, 800 already returned, 1200 paid.
      final m = ReturnMoney.of(
        lines: const [ReturnableLine(
            itemId: 'x', name: 'A', quantity: 5, returnedQty: 2, unitPrice: 400)],
        chosen: {0: 1},
        subtotal: 2000,
        discount: 0,
        total: 2000,
        returnedTotal: 800,
        amountPaid: 1200,
        returnsEverything: false,
      );
      expect(m.value, 400);
      expect(m.refund, 400);
    });
  });

  test('ReturnableLine counts what can still go back', () {
    expect(const ReturnableLine(itemId: 'x', name: 'A', quantity: 3,
        returnedQty: 1, unitPrice: 1).returnable, 2);
    expect(const ReturnableLine(itemId: 'x', name: 'A', quantity: 3,
        returnedQty: 0, unitPrice: 1, partGone: true).returnable, 0);
  });

  test('Bill reads returns and nets them off', () {
    final bill = Bill.fromJson(_billJson());
    expect(bill.netTotal, 933.33);
    expect(bill.balance, 0);
    expect(bill.hasBalance, isFalse);
    expect(bill.hasReturns, isTrue);
    expect(bill.fullyReturned, isFalse); // Part B and a service are left
    expect(bill.canReturn, isTrue);
    expect(bill.returnableLines.map((l) => (l.itemId, l.returnable)),
        [('ia', 1), ('ib', 1)]); // services are not returnable
    final r = bill.returns.single;
    expect(r.kind, ReturnKind.customer);
    expect(r.refundMethod, PaymentMethod.cash);
    expect(r.items.single.name, 'Part A');
    expect(r.itemCount, 1);
  });

  test('a credit bill with a return owes only the rest', () {
    final json = _billJson()
      ..['amount_paid'] = 0
      ..['payment_status'] = 'unpaid'
      ..['bill_payments'] = <dynamic>[];
    final bill = Bill.fromJson(json);
    expect(bill.balance, 933.33);
    expect(bill.hasBalance, isTrue);
  });

  test('Purchase reads returns', () {
    final p = Purchase.fromJson({
      'id': 'p1',
      'purchase_no': 'PUR-IBB-000001',
      'branch_id': 'ibb',
      'supplier_id': 's1',
      'invoice_date': '2026-11-21',
      'subtotal': 2000,
      'discount': 0,
      'total': 2000,
      'returned_total': 800,
      'payment_method': 'credit',
      'amount_paid': 0,
      'payment_status': 'unpaid',
      'status': 'completed',
      'created_at': '2026-11-21T08:00:00Z',
      'supplier': {'name': 'Supplier S'},
      'purchase_items': [
        {'id': 'pi1', 'part_id': 'pa', 'part_name': 'Part A', 'quantity': 5,
         'returned_qty': 2, 'unit_cost': 400, 'line_total': 2000, 'sort_order': 0},
      ],
      'purchase_returns': [
        {'id': 'pr1', 'reason': 'Damaged', 'return_value': 800, 'refund_amount': 0,
         'refund_method': null, 'created_at': '2026-11-21T09:00:00Z',
         'purchase_return_items': [
           {'part_name': 'Part A', 'quantity': 2, 'value': 800},
         ]},
      ],
    });
    expect(p.netTotal, 1200);
    expect(p.balance, 1200);
    expect(p.returnableLines.single.returnable, 3);
    expect(p.returns.single.kind, ReturnKind.supplier);
    expect(p.returns.single.refundMethod, isNull);
  });

  test('history rows read the bill number and customer', () {
    final r = StockReturn.fromJson({
      'id': 'r1',
      'reason': 'Wrong part',
      'return_value': 500,
      'refund_amount': 0,
      'created_at': '2026-11-21T09:00:00Z',
      'bill_return_items': [
        {'part_name': 'Part A', 'quantity': 1, 'value': 500},
      ],
      'bill': {'id': 'b2', 'bill_no': 'IBB-000002', 'customer_name': 'Kamal'},
    }, ReturnKind.customer);
    expect(r.docId, 'b2');
    expect(r.docNo, 'IBB-000002');
    expect(r.otherParty, 'Kamal');

    final s = StockReturn.fromJson({
      'id': 'r2',
      'reason': 'Damaged',
      'return_value': 400,
      'refund_amount': 400,
      'refund_method': 'bank_transfer',
      'created_at': '2026-11-21T09:00:00Z',
      'purchase_return_items': <dynamic>[],
      'purchase': {'id': 'p1', 'purchase_no': 'PUR-IBB-000001',
                   'supplier': {'name': 'Supplier S'}},
    }, ReturnKind.supplier);
    expect(s.docNo, 'PUR-IBB-000001');
    expect(s.otherParty, 'Supplier S');
    expect(s.refundMethod, PaymentMethod.bankTransfer);
  });

  test('bill PDF with returns is generated', () async {
    final bytes = await buildBillPdf(Bill.fromJson(_billJson()));
    expect(bytes.length, greaterThan(1000));
  });
}
