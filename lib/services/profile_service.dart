import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';

class ProfileService {
  ProfileService([SupabaseClient? client])
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  /// The signed-in user's role, or null if a super admin has not given one.
  Future<UserProfile?> fetchMyProfile() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return null;
    final row = await _db
        .from('profiles')
        .select('role, branch_id')
        .eq('user_id', userId)
        .maybeSingle();
    return row == null ? null : UserProfile.fromJson(row);
  }

  /// All sign-in accounts. Super admin only.
  Future<List<AppUser>> listUsers() async {
    final rows = await _db.rpc('list_users') as List<dynamic>;
    return rows.cast<Map<String, dynamic>>().map(AppUser.fromJson).toList();
  }

  /// Sets [userId]'s role. A null [role] removes their access.
  Future<void> setUserRole(String userId, UserRole? role,
      {String? branchId}) async {
    try {
      await _db.rpc('set_user_role', params: {
        'p_user_id': userId,
        'p_role': role?.value,
        'p_branch_id': branchId,
      });
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }
}
