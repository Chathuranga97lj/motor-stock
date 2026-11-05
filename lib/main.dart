import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/profile.dart';
import 'screens/login_screen.dart';
import 'screens/parts_list_screen.dart';
import 'services/profile_service.dart';
import 'theme.dart';

// Pass these at build/run time, e.g.
// flutter run --dart-define-from-file=env.json
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
    runApp(const _MissingConfigApp());
    return;
  }
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  runApp(const MotorStockApp());
}

class MotorStockApp extends StatelessWidget {
  const MotorStockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OSHU Stock',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const _AuthGate(),
    );
  }
}

/// Shows the login screen or the stock list depending on the session.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) {
        final user = auth.currentSession?.user;
        // Keyed by user so switching accounts reloads the role.
        return user == null
            ? const LoginScreen()
            : _RoleGate(key: ValueKey(user.id));
      },
    );
  }
}

/// Loads the signed-in user's role before showing the app.
class _RoleGate extends StatefulWidget {
  const _RoleGate({super.key});

  @override
  State<_RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<_RoleGate> {
  late Future<UserProfile?> _profile = ProfileService().fetchMyProfile();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfile?>(
      future: _profile,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final profile = snapshot.data;
        if (profile != null) return PartsListScreen(profile: profile);
        return _NoAccessScreen(
          message: snapshot.hasError
              ? 'Could not load your account.\n${snapshot.error}'
              : 'Your account does not have a role yet.\n'
                  'Ask the super admin to give you access.',
          onRetry: () => setState(
              () => _profile = ProfileService().fetchMyProfile()),
        );
      },
    );
  }
}

class _NoAccessScreen extends StatelessWidget {
  const _NoAccessScreen({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 56),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              if (email != null) ...[
                const SizedBox(height: 8),
                Text('Signed in as $email',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                children: [
                  OutlinedButton(
                      onPressed: onRetry, child: const Text('Try again')),
                  FilledButton(
                    onPressed: () =>
                        Supabase.instance.client.auth.signOut(),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Supabase is not configured.\n\n'
              'Run with: flutter run --dart-define-from-file=env.json',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
