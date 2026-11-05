import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bill.dart';

class BillService {
  BillService([SupabaseClient? client])
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  /// Saves a bill, takes the stock off [branchId] and returns the new bill id.
  /// Prices and totals are calculated by the database. [amountPaid] null means
  /// the full total; [PaymentMethod.credit] means nothing paid now.
  Future<String> createBill({
    required String branchId,
    required List<CartLine> lines,
    required PaymentMethod paymentMethod,
    double discount = 0,
    double? amountPaid,
    String? customerName,
    String? customerPhone,
  }) =>
      _guard(() async {
        final id = await _db.rpc('create_bill', params: {
          'p_branch_id': branchId,
          'p_items': [
            for (final l in lines)
              {'part_id': l.part.id, 'quantity': l.quantity},
          ],
          'p_customer_name': customerName,
          'p_customer_phone': customerPhone,
          'p_discount': discount,
          'p_payment_method': paymentMethod.value,
          'p_amount_paid': amountPaid,
        });
        return id as String;
      });

  /// Bills for one branch since [from] (all time if null), newest first.
  Future<List<Bill>> fetchBills({required String branchId, DateTime? from}) async {
    var query = _db.from('bills').select(Bill.listColumns).eq('branch_id', branchId);
    if (from != null) {
      query = query.gte('created_at', from.toUtc().toIso8601String());
    }
    final rows = await query.order('created_at', ascending: false).limit(500);
    return rows.map(Bill.fromJson).toList();
  }

  /// Bills of [branchId] that still have money to collect, oldest first.
  /// [search] matches customer name or phone.
  Future<List<Bill>> fetchOutstanding({
    required String branchId,
    String search = '',
  }) async {
    var query = _db
        .from('bills')
        .select(Bill.listColumns)
        .eq('branch_id', branchId)
        .eq('status', 'completed')
        .neq('payment_status', 'paid');
    final q = search.replaceAll(RegExp(r'[,()%*]'), ' ').trim();
    if (q.isNotEmpty) {
      query = query.or('customer_name.ilike.%$q%,customer_phone.ilike.%$q%');
    }
    final rows = await query.order('created_at').limit(1000);
    return rows.map(Bill.fromJson).toList();
  }

  /// Money received at [branchId] since [from] (all time if null),
  /// on bills that are not cancelled.
  Future<double> fetchCollected({required String branchId, DateTime? from}) async {
    var query = _db
        .from('bill_payments')
        .select('amount, bills!inner(status)')
        .eq('branch_id', branchId)
        .eq('bills.status', 'completed');
    if (from != null) {
      query = query.gte('created_at', from.toUtc().toIso8601String());
    }
    final rows = await query.limit(10000);
    return roundMoney(rows.fold(0.0, (sum, r) => sum + (r['amount'] as num)));
  }

  Future<Bill> fetchBill(String id) async {
    final row =
        await _db.from('bills').select(Bill.detailColumns).eq('id', id).single();
    return Bill.fromJson(row);
  }

  Future<void> addPayment(
    String billId, {
    required double amount,
    required PaymentMethod method,
    String? note,
  }) =>
      _guard(() => _db.rpc('add_bill_payment', params: {
            'p_bill_id': billId,
            'p_amount': amount,
            'p_method': method.value,
            'p_note': note,
          }));

  Future<void> cancelBill(String id, {String? reason}) => _guard(() =>
      _db.rpc('cancel_bill', params: {'p_bill_id': id, 'p_reason': reason}));

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }
}
