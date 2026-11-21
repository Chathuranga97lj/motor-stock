import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bill.dart';
import '../models/stock_return.dart';
import '../models/totals.dart';
import '../utils/errors.dart';

/// Customer and supplier returns (supabase/012_returns.sql).
class ReturnService {
  ReturnService([SupabaseClient? client])
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  /// Saves a return of [quantities] (bill or stock-in line id -> quantity).
  /// [refundMethod] is used only when money goes back. Returns the return id.
  Future<String> save(
    ReturnKind kind, {
    required String docId,
    required Map<String, int> quantities,
    required String reason,
    PaymentMethod refundMethod = PaymentMethod.cash,
  }) async {
    final itemKey =
        kind == ReturnKind.customer ? 'bill_item_id' : 'purchase_item_id';
    try {
      final id = await _db.rpc(
        kind == ReturnKind.customer ? 'return_bill_items' : 'return_purchase_items',
        params: {
          kind == ReturnKind.customer ? 'p_bill_id' : 'p_purchase_id': docId,
          'p_items': [
            for (final e in quantities.entries)
              if (e.value > 0) {itemKey: e.key, 'quantity': e.value},
          ],
          'p_reason': reason,
          'p_refund_method': refundMethod.value,
        },
      );
      return id as String;
    } on PostgrestException catch (e) {
      throw Exception(_friendly(e));
    }
  }

  /// Returns of [branchId] since [from] (all time if null), newest first.
  Future<List<StockReturn>> fetchReturns(
    ReturnKind kind, {
    required String branchId,
    DateTime? from,
  }) async {
    try {
      var query = _db
          .from(kind.table)
          .select(StockReturn.historyColumns(kind))
          .eq('branch_id', branchId);
      if (from != null) {
        query = query.gte('created_at', from.toUtc().toIso8601String());
      }
      final rows = await query.order('created_at', ascending: false).limit(500);
      return rows.map((r) => StockReturn.fromJson(r, kind)).toList();
    } on PostgrestException catch (e) {
      throw Exception(_friendly(e));
    }
  }

  /// Count, value and refunds of [branchId]'s returns since [from] (all
  /// time if null), added up in the database. Null when
  /// supabase/013_period_totals.sql has not been run yet.
  Future<ReturnTotals?> fetchTotals(
    ReturnKind kind, {
    required String branchId,
    DateTime? from,
  }) async {
    try {
      final result = await _db.rpc('return_totals', params: {
        'p_kind': kind.name,
        'p_branch_id': branchId,
        'p_from': from?.toUtc().toIso8601String(),
      });
      return ReturnTotals.fromJson(Map<String, dynamic>.from(result as Map));
    } on PostgrestException catch (e) {
      if (isMissingFunction(e)) return null;
      throw Exception(_friendly(e));
    }
  }

  static String _friendly(PostgrestException e) =>
      // PGRST202 / 42P01: function or table not there yet.
      e.code == 'PGRST202' || e.code == '42P01' || e.code == 'PGRST205'
          ? 'Returns are not set up in the database yet. Run '
              'supabase/012_returns.sql in the Supabase SQL Editor.'
          : e.message;
}
