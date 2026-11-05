import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/branch.dart';
import '../models/profile.dart';
import '../services/profile_service.dart';

/// Super admin: create a new login with its role and branch.
/// Returns true when a user was added.
class AddUserScreen extends StatefulWidget {
  const AddUserScreen({super.key, required this.branches});

  final List<Branch> branches;

  @override
  State<AddUserScreen> createState() => _AddUserScreenState();
}

class _AddUserScreenState extends State<AddUserScreen> {
  final _service = ProfileService();
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  UserRole _role = UserRole.admin;
  late String? _branchId = widget.branches
      .where((b) => !b.isMain)
      .followedBy(widget.branches)
      .firstOrNull
      ?.id;
  bool _showPassword = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// 10 characters, avoiding ones that are easy to mix up (0/O, 1/l/I).
  void _generatePassword() {
    const chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    setState(() {
      _password.text =
          List.generate(10, (_) => chars[rnd.nextInt(chars.length)]).join();
      _showPassword = true;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final email = _email.text.trim().toLowerCase();
    final password = _password.text;
    try {
      await _service.createUser(
        email: email,
        password: password,
        role: _role,
        branchId: _role == UserRole.admin ? _branchId : null,
      );
      if (!mounted) return;
      await _showCreated(email, password);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  /// Shows the login details once so they can be given to the staff member.
  Future<void> _showCreated(String email, String password) {
    final branch =
        widget.branches.where((b) => b.id == _branchId).firstOrNull?.name;
    final details = 'Email: $email\nPassword: $password';
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.check_circle_outline),
        title: const Text('User added'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_role == UserRole.admin
                ? 'Admin for ${branch ?? 'their branch'}.'
                : 'Super admin.'),
            const SizedBox(height: 12),
            SelectableText(details),
            const SizedBox(height: 12),
            const Text('Give these details to the staff member. '
                'The password is not shown again.'),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: details)),
            icon: const Icon(Icons.copy),
            label: const Text('Copy'),
          ),
          FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Add user')),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Email *'),
                validator: (v) =>
                    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v?.trim() ?? '')
                        ? null
                        : 'Enter a valid email',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _password,
                obscureText: !_showPassword,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Password *',
                  helperText: 'At least 8 characters',
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: _showPassword ? 'Hide' : 'Show',
                        icon: Icon(_showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                      ),
                      IconButton(
                        tooltip: 'Generate password',
                        icon: const Icon(Icons.auto_awesome_outlined),
                        onPressed: _generatePassword,
                      ),
                    ],
                  ),
                ),
                validator: (v) => (v?.length ?? 0) < 8
                    ? 'At least 8 characters'
                    : null,
              ),
              const SizedBox(height: 16),
              Text('Role', style: theme.textTheme.titleSmall),
              RadioGroup<UserRole>(
                groupValue: _role,
                onChanged: (r) => setState(() => _role = r!),
                child: const Column(
                  children: [
                    RadioListTile<UserRole>(
                      value: UserRole.admin,
                      title: Text('Admin'),
                      subtitle: Text('One branch: add and update parts, stock'),
                    ),
                    RadioListTile<UserRole>(
                      value: UserRole.superAdmin,
                      title: Text('Super admin'),
                      subtitle: Text('All branches, transfers, lists, users'),
                    ),
                  ],
                ),
              ),
              if (_role == UserRole.admin) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _branchId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Branch *'),
                  items: [
                    for (final b in widget.branches)
                      DropdownMenuItem(value: b.id, child: Text(b.name)),
                  ],
                  onChanged: (id) => setState(() => _branchId = id),
                  validator: (v) => v == null ? 'Choose a branch' : null,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.person_add_alt_1),
                label: Text(_saving ? 'Adding…' : 'Add user'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
