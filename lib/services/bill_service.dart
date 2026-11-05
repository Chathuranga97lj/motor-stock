import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bill.dart';

class BillService {
  BillService([SupabaseClient? client])
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  /// Saves a bill, takes the stock off [branchId] and returns the new bill id.
  /// Prices and totals are calculated by the database.
  Future<String> createBill({
    required String branchId,
    required List<CartLine> lines,
    required PaymentMethod paymentMethod,
    double discount = 0,
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

  Future<Bill> fetchBill(String id) async {
    final row =
        await _db.from('bills').select(Bill.detailColumns).eq('id', id).single();
    return Bill.fromJson(row);
  }

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
