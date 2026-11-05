import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/branch.dart';
import '../models/profile.dart';
import '../services/branch_service.dart';
import '../services/profile_service.dart';
import '../theme.dart';
import 'add_user_screen.dart';

/// Super admin: add sign-in accounts and give each a role and, for admins,
/// a branch.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final _service = ProfileService();
  final _branchService = BranchService();
  List<AppUser> _users = [];
  List<Branch> _branches = [];
  bool _loading = true;
  String? _error;

  String? get _myId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (users, branches) = await (
        _service.listUsers(),
        _branchService.fetchBranches(),
      ).wait;
      if (mounted) {
        setState(() {
          _users = users;
          _branches = branches;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load users: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(AppUser user) async {
    final result = await showDialog<_RoleChoice>(
      context: context,
      builder: (context) => _RoleDialog(user: user, branches: _branches),
    );
    if (result == null) return;
    try {
      await _service.setUserRole(
        user.id,
        result.role,
        branchId: result.branchId,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _add() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddUserScreen(branches: _branches)),
    );
    if (added == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      floatingActionButton: _loading || _error != null
          ? null
          : FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add user'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 88),
                children: [
                  for (final u in _users) ...[TileCard(child: _tile(u))],
                ],
              ),
            ),
    );
  }

  Widget _tile(AppUser u) {
    final scheme = Theme.of(context).colorScheme;
    final isMe = u.id == _myId;
    final (icon, color) = switch (u.role) {
      UserRole.superAdmin => (Icons.shield_outlined, scheme.primary),
      UserRole.admin => (Icons.person_outline, scheme.secondary),
      null => (Icons.block, scheme.outline),
    };
    final roleText = switch (u.role) {
      UserRole.superAdmin => 'Super admin • all branches',
      UserRole.admin => 'Admin • ${u.branchName ?? '?'}',
      null => 'No access',
    };
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(isMe ? '${u.email} (you)' : u.email),
      subtitle: Text(roleText),
      trailing: isMe ? null : const Icon(Icons.edit_outlined),
      // You cannot change your own role, so you can't lock yourself out.
      onTap: isMe ? null : () => _edit(u),
    );
  }
}

typedef _RoleChoice = ({UserRole? role, String? branchId});

class _RoleDialog extends StatefulWidget {
  const _RoleDialog({required this.user, required this.branches});

  final AppUser user;
  final List<Branch> branches;

  @override
  State<_RoleDialog> createState() => _RoleDialogState();
}

class _RoleDialogState extends State<_RoleDialog> {
  late UserRole? _role = widget.user.role;
  late String? _branchId =
      widget.user.branchId ??
      widget.branches.where((b) => b.isMain).firstOrNull?.id;

  @override
  Widget build(BuildContext context) {
    final canSave = _role != UserRole.admin || _branchId != null;
    return AlertDialog(
      title: Text(widget.user.email, overflow: TextOverflow.ellipsis),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioGroup<UserRole?>(
              groupValue: _role,
              onChanged: (r) => setState(() => _role = r),
              child: const Column(
                children: [
                  RadioListTile<UserRole?>(
                    value: UserRole.superAdmin,
                    title: Text('Super admin'),
                    subtitle: Text('All branches, transfers, lists, users'),
                  ),
                  RadioListTile<UserRole?>(
                    value: UserRole.admin,
                    title: Text('Admin'),
                    subtitle: Text('One branch: add and update parts, stock'),
                  ),
                  RadioListTile<UserRole?>(
                    value: null,
                    title: Text('No access'),
                  ),
                ],
              ),
            ),
            if (_role == UserRole.admin) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _branchId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Branch'),
                items: [
                  for (final b in widget.branches)
                    DropdownMenuItem(value: b.id, child: Text(b.name)),
                ],
                onChanged: (id) => setState(() => _branchId = id),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: canSave
              ? () => Navigator.pop<_RoleChoice>(context, (
                  role: _role,
                  branchId: _role == UserRole.admin ? _branchId : null,
                ))
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
