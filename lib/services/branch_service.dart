import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/branch.dart';
import 'lookup_service.dart';

/// Branches, stock per branch and stock transfers.
class BranchService {
  BranchService([SupabaseClient? client])
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;
  static const _selectedKey = 'selected_branch_id';

  /// Main branch first, then by name.
  Future<List<Branch>> fetchBranches() async {
    final rows = await _db
        .from('branches')
        .select('id, name, is_main, address, phone')
        .order('is_main', ascending: false)
        .order('name');
    return rows.map(Branch.fromJson).toList();
  }

  Future<void> addBranch(String name) => _guard(() =>
      _db.from('branches').insert({'name': LookupService.normalize(name)}));

  Future<void> updateBranch(Branch branch,
          {required String name, String? address, String? phone}) =>
      _guard(() => _db.from('branches').update({
            'name': LookupService.normalize(name),
            'address': _blankToNull(address),
            'phone': _blankToNull(phone),
          }).eq('id', branch.id));

  static String? _blankToNull(String? s) =>
      s == null || s.trim().isEmpty ? null : s.trim();

  /// The branch this device works in, remembered between app starts.
  Future<String?> loadSelectedBranchId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_selectedKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSelectedBranchId(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_selectedKey, id);
    } catch (_) {
      // Not critical: the main branch is used next time.
    }
  }

  /// Adds [delta] (can be negative) at one branch. Never goes below 0.
  Future<void> adjustStock(String partId, String branchId, int delta) =>
      _guard(() => _db.rpc('adjust_stock', params: {
            'p_part_id': partId,
            'p_branch_id': branchId,
            'p_delta': delta,
          }));

  Future<void> transfer({
    required String partId,
    required String fromBranchId,
    required String toBranchId,
    required int quantity,
    String? note,
  }) =>
      _guard(() => _db.rpc('transfer_stock', params: {
            'p_part_id': partId,
            'p_from_branch_id': fromBranchId,
            'p_to_branch_id': toBranchId,
            'p_quantity': quantity,
            'p_note': note,
          }));

  Future<List<StockTransfer>> fetchTransfers({int limit = 200}) async {
    final rows = await _db
        .from('stock_transfers')
        .select(StockTransfer.selectColumns)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(StockTransfer.fromJson).toList();
  }

  /// Turns database errors into short messages for the user.
  Future<void> _guard(Future<dynamic> Function() action) async {
    try {
      await action();
    } on PostgrestException catch (e) {
      throw Exception(e.code == '23505' ? 'Branch already exists' : e.message);
    }
  }
}
