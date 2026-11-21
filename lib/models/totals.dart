import 'bill.dart';
import 'purchase.dart';
import 'stock_return.dart';

double _money(Object? v) => roundMoney((v as num?)?.toDouble() ?? 0);
int _count(Object? v) => (v as num?)?.toInt() ?? 0;

/// The cards on the Bills screen for one period (bill_totals() in
/// supabase/013_period_totals.sql).
class BillTotals {
  const BillTotals({
    this.bills = 0,
    this.cancelled = 0,
    this.sales = 0,
    this.parts = 0,
    this.services = 0,
    this.collected = 0,
  });

  /// Bills that are not cancelled, and cancelled ones.
  final int bills;
  final int cancelled;

  /// Total after returns of bills that are not cancelled.
  final double sales;

  /// Parts and service before bill discounts.
  final double parts;
  final double services;

  /// Money received, less refunds for returns.
  final double collected;

  factory BillTotals.fromJson(Map<String, dynamic> json) => BillTotals(
        bills: _count(json['bills']),
        cancelled: _count(json['cancelled']),
        sales: _money(json['sales']),
        parts: _money(json['parts']),
        services: _money(json['services']),
        collected: _money(json['collected']),
      );

  /// Added up on the phone, for a database without migration 013. Only
  /// right while [list] has every bill of the period.
  factory BillTotals.fromBills(Iterable<Bill> list, {required double collected}) {
    final done = list.where((b) => !b.cancelled);
    return BillTotals(
      bills: done.length,
      cancelled: list.length - done.length,
      sales: roundMoney(done.fold(0.0, (s, b) => s + b.netTotal)),
      parts: roundMoney(done.fold(0.0, (s, b) => s + b.partsTotal)),
      services: roundMoney(done.fold(0.0, (s, b) => s + b.servicesTotal)),
      collected: collected,
    );
  }
}

/// The cards on the Stock-ins screen (purchase_totals()).
class PurchaseTotals {
  const PurchaseTotals({this.stockIns = 0, this.purchased = 0, this.paid = 0});

  /// Stock-ins that are not cancelled.
  final int stockIns;

  /// Total after returns of stock-ins that are not cancelled.
  final double purchased;

  /// Paid to suppliers, less refunds they gave back.
  final double paid;

  factory PurchaseTotals.fromJson(Map<String, dynamic> json) => PurchaseTotals(
        stockIns: _count(json['stock_ins']),
        purchased: _money(json['purchased']),
        paid: _money(json['paid']),
      );

  /// Added up on the phone, for a database without migration 013.
  factory PurchaseTotals.fromPurchases(Iterable<Purchase> list,
          {required double paid}) =>
      PurchaseTotals(
        stockIns: list.where((p) => !p.cancelled).length,
        purchased: roundMoney(list
            .where((p) => !p.cancelled)
            .fold(0.0, (s, p) => s + p.netTotal)),
        paid: paid,
      );
}

/// The cards on the Returns screen (return_totals()).
class ReturnTotals {
  const ReturnTotals({this.returns = 0, this.value = 0, this.refunded = 0});

  final int returns;

  /// What the returned parts were worth, and the money that went back.
  final double value;
  final double refunded;

  factory ReturnTotals.fromJson(Map<String, dynamic> json) => ReturnTotals(
        returns: _count(json['returns']),
        value: _money(json['value']),
        refunded: _money(json['refunded']),
      );

  /// Added up on the phone, for a database without migration 013.
  factory ReturnTotals.fromReturns(List<StockReturn> list) => ReturnTotals(
        returns: list.length,
        value: roundMoney(list.fold(0.0, (s, r) => s + r.value)),
        refunded: roundMoney(list.fold(0.0, (s, r) => s + r.refundAmount)),
      );
}
