import 'package:supabase_flutter/supabase_flutter.dart';

/// An error as a short message for the user ("Exception: " taken off).
String errorMessage(Object error) =>
    '$error'.replaceFirst('Exception: ', '');

/// The database has no such function yet: a migration has not been run.
bool isMissingFunction(PostgrestException e) => e.code == 'PGRST202';
