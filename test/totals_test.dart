import 'package:flutter_test/flutter_test.dart';
import 'package:motor_stock/models/bill.dart';
import 'package:motor_stock/models/purchase.dart';
import 'package:motor_stock/models/stock_return.dart';
import 'package:motor_stock/models/totals.dart';

Bill _bill(double total,
        {double returned = 0, double parts = 0, double services = 0, bool cancelled = false}) =>
    Bill(
      id: 'b$total',
      billNo: 'IBB-1',
      branchId: 'ibb',
      branchName: 'IBBAGAMUWA',
      subtotal: parts + services,
      partsTotal: parts,
      servicesTotal: services,
      discount: 0,
      total: total,
      returnedTotal: returned,
      paymentMethod: PaymentMethod.cash,
      cancelled: cancelled,
      createdAt: DateTime(2026, 11, 22),
    );

Purchase _purchase(double total, {double returned = 0, bool cancelled = false}) =>
    Purchase(
      id: 'p$total',
      purchaseNo: 'PUR-IBB-1',
      branchId: 'ibb',
      branchName: 'IBBAGAMUWA',
      supplierId: 's1',
      supplierName: 'ABC',
      invoiceDate: DateTime(2026, 11, 22),
      subtotal: total,
      discount: 0,
      total: total,
      returnedTotal: returned,
      paymentMethod: PaymentMethod.cash,
      amountPaid: total,
      paymentStatus: PaymentStatus.paid,
      cancelled: cancelled,
      createdAt: DateTime(2026, 11, 22),
    );

void main() {
  test('bill totals read what bill_totals() sends', () {
    // As returned by the scenario run on a local copy of the database.
    final t = BillTotals.fromJson({
      'bills': 2,
      'parts': 2500.00,
      'sales': 1500.00,
      'services': 0,
      'cancelled': 1,
      'collected': 1200.00,
    });
    expect(t.bills, 2);
    expect(t.cancelled, 1);
    expect(t.sales, 1500);
    expect(t.parts, 2500);
    expect(t.services, 0);
    expect(t.collected, 1200);
  });

  test('bill totals on the phone match the old screen sums', () {
    final t = BillTotals.fromBills([
      _bill(2000, returned: 1000, parts: 2000),
      _bill(800.1, parts: 500.1, services: 300),
      _bill(1300, parts: 1000, services: 300, cancelled: true),
    ], collected: 1200);
    expect(t.bills, 2);
    expect(t.cancelled, 1);
    expect(t.sales, 1800.1); // after returns, cancelled left out
    expect(t.parts, 2500.1);
    expect(t.services, 300);
    expect(t.collected, 1200);
  });

  test('purchase totals', () {
    final fromDb = PurchaseTotals.fromJson(
        {'stock_ins': 2, 'purchased': 1050.00, 'paid': 650.00});
    expect(fromDb.stockIns, 2);
    expect(fromDb.purchased, 1050);
    expect(fromDb.paid, 650);

    final onPhone = PurchaseTotals.fromPurchases([
      _purchase(1000, returned: 200),
      _purchase(250),
      _purchase(999, cancelled: true),
    ], paid: 650);
    expect(onPhone.stockIns, 2);
    expect(onPhone.purchased, 1050);
    expect(onPhone.paid, 650);
  });

  test('return totals', () {
    final fromDb =
        ReturnTotals.fromJson({'returns': 1, 'value': 1000.00, 'refunded': 1000.00});
    expect(fromDb.returns, 1);
    expect(fromDb.value, 1000);
    expect(fromDb.refunded, 1000);

    StockReturn r(double value, double refund) => StockReturn(
          id: 'r$value',
          kind: ReturnKind.customer,
          reason: 'Faulty',
          value: value,
          refundAmount: refund,
          createdAt: DateTime(2026, 11, 22),
        );
    final onPhone = ReturnTotals.fromReturns([r(1000, 1000), r(200.2, 0)]);
    expect(onPhone.returns, 2);
    expect(onPhone.value, 1200.2);
    expect(onPhone.refunded, 1000);
  });

  test('missing numbers count as 0', () {
    final t = BillTotals.fromJson({});
    expect(t.sales, 0);
    expect(t.bills, 0);
  });
}
