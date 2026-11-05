enum UserRole {
  superAdmin('super_admin', 'Super admin'),
  admin('admin', 'Admin');

  const UserRole(this.value, this.label);

  /// Value stored in the database.
  final String value;
  final String label;

  static UserRole? parse(String? value) =>
      UserRole.values.where((r) => r.value == value).firstOrNull;
}

/// The signed-in user's role. Admins are tied to one branch.
class UserProfile {
  final UserRole role;
  final String? branchId;

  const UserProfile({required this.role, this.branchId});

  bool get isSuperAdmin => role == UserRole.superAdmin;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        role: UserRole.parse(json['role'] as String?) ?? UserRole.admin,
        branchId: json['branch_id'] as String?,
      );
}

/// A sign-in account as shown on the Users screen.
class AppUser {
  final String id;
  final String email;
  final UserRole? role; // null = no access
  final String? branchId;
  final String? branchName;
  final DateTime? lastSignInAt;

  const AppUser({
    required this.id,
    required this.email,
    this.role,
    this.branchId,
    this.branchName,
    this.lastSignInAt,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['user_id'] as String,
        email: json['email'] as String? ?? '(no email)',
        role: UserRole.parse(json['role'] as String?),
        branchId: json['branch_id'] as String?,
        branchName: json['branch_name'] as String?,
        lastSignInAt: json['last_sign_in_at'] == null
            ? null
            : DateTime.parse(json['last_sign_in_at'] as String).toLocal(),
      );
}
