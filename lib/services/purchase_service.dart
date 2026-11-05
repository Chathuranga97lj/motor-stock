import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bill.dart';
import '../models/purchase.dart';

/// Suppliers and stock-ins (purchases).
class PurchaseService {
  PurchaseService([SupabaseClient? client])
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  // ---------- Suppliers ----------

  Future<List<Supplier>> fetchSuppliers() async {
    final rows = await _db
        .from('suppliers')
        .select('id, name, phone, address, note')
        .order('name');
    return rows.map(Supplier.fromJson).toList();
  }

  Future<Supplier> addSupplier({
    required String name,
    String? phone,
    String? address,
    String? note,
  }) =>
      _guard(() async {
        final row = await _db
            .from('suppliers')
            .insert({
              'name': name.trim(),
              'phone': _blank(phone),
              'address': _blank(address),
              'note': _blank(note),
            })
            .select()
            .single();
        return Supplier.fromJson(row);
      });

  Future<void> updateSupplier(
    Supplier s, {
    required String name,
    String? phone,
    String? address,
    String? note,
  }) =>
      _guard(() => _db.from('suppliers').update({
            'name': name.trim(),
            'phone': _blank(phone),
            'address': _blank(address),
            'note': _blank(note),
          }).eq('id', s.id));

  Future<void> deleteSupplier(Supplier s) => _guard(
      () => _db.from('suppliers').delete().eq('id', s.id),
      foreignKeyMessage: 'This supplier has stock-ins and cannot be deleted');

  // ---------- Stock-ins ----------

  /// Saves a stock-in, adds the stock to [branchId] and returns its id.
  Future<String> createPurchase({
    required String branchId,
    required String supplierId,
    required List<PurchaseLine> lines,
    required PaymentMethod paymentMethod,
    String? invoiceNo,
    DateTime? invoiceDate,
    double discount = 0,
    double? amountPaid,
    bool updateBuyPrice = true,
    String? note,
  }) =>
      _guard(() async {
        final id = await _db.rpc('create_purchase', params: {
          'p_branch_id': branchId,
          'p_supplier_id': supplierId,
          'p_items': [
            for (final l in lines)
              {
                'part_id': l.part.id,
                'quantity': l.quantity,
                'unit_cost': l.unitCost,
              },
          ],
          'p_invoice_no': invoiceNo,
          'p_invoice_date': invoiceDate == null ? null : _date(invoiceDate),
          'p_discount': discount,
          'p_payment_method': paymentMethod.value,
          'p_amount_paid': amountPaid,
          'p_update_buy_price': updateBuyPrice,
          'p_note': note,
        });
        return id as String;
      });

  /// The stock-in number that already used this supplier + invoice, if any.
  Future<String?> findByInvoice(String supplierId, String invoiceNo) async {
    if (invoiceNo.trim().isEmpty) return null;
    final result = await _db.rpc('find_purchase_by_invoice', params: {
      'p_supplier_id': supplierId,
      'p_invoice_no': invoiceNo,
    });
    return result as String?;
  }

  /// Stock-ins of [branchId] since [from] (all time if null), newest first.
  Future<List<Purchase>> fetchPurchases({
    required String branchId,
    DateTime? from,
    String? supplierId,
  }) async {
    var query = _db
        .from('purchases')
        .select(Purchase.listColumns)
        .eq('branch_id', branchId);
    if (from != null) {
      query = query.gte('created_at', from.toUtc().toIso8601String());
    }
    if (supplierId != null) query = query.eq('supplier_id', supplierId);
    final rows = await query.order('created_at', ascending: false).limit(500);
    return rows.map(Purchase.fromJson).toList();
  }

  /// Money paid to suppliers from [branchId] since [from] (all time if null),
  /// optionally to one supplier.
  Future<double> fetchPaid({
    required String branchId,
    DateTime? from,
    String? supplierId,
  }) async {
    var query = _db
        .from('purchase_payments')
        .select('amount, purchases!inner(status, supplier_id)')
        .eq('branch_id', branchId)
        .eq('purchases.status', 'completed');
    if (supplierId != null) {
      query = query.eq('purchases.supplier_id', supplierId);
    }
    if (from != null) {
      query = query.gte('created_at', from.toUtc().toIso8601String());
    }
    final rows = await query.limit(10000);
    return roundMoney(rows.fold(0.0, (sum, r) => sum + (r['amount'] as num)));
  }

  /// All branches' stock-ins still owed to suppliers, oldest first.
  Future<List<Purchase>> fetchToPay() async {
    final rows = await _db
        .from('purchases')
        .select(Purchase.listColumns)
        .eq('status', 'completed')
        .neq('payment_status', 'paid')
        .order('created_at')
        .limit(1000);
    return rows.map(Purchase.fromJson).toList();
  }

  Future<Purchase> fetchPurchase(String id) async {
    final row = await _db
        .from('purchases')
        .select(Purchase.detailColumns)
        .eq('id', id)
        .single();
    return Purchase.fromJson(row);
  }

  Future<void> addPayment(
    String purchaseId, {
    required double amount,
    required PaymentMethod method,
    String? note,
  }) =>
      _guard(() => _db.rpc('add_purchase_payment', params: {
            'p_purchase_id': purchaseId,
            'p_amount': amount,
            'p_method': method.value,
            'p_note': note,
          }));

  Future<void> cancelPurchase(String id, {String? reason}) => _guard(() => _db
      .rpc('cancel_purchase', params: {'p_purchase_id': id, 'p_reason': reason}));

  static String? _blank(String? s) =>
      s == null || s.trim().isEmpty ? null : s.trim();

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<T> _guard<T>(Future<T> Function() action,
      {String? foreignKeyMessage}) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      throw Exception(switch (e.code) {
        '23505' => 'A supplier with this name already exists',
        '23503' => foreignKeyMessage ?? e.message,
        _ => e.message,
      });
    }
  }
}
