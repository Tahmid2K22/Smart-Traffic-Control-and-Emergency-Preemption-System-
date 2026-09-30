import 'package:supabase_flutter/supabase_flutter.dart';

/// Returns true only when Supabase has been successfully initialised.
/// Use this guard before every Supabase call so the app never crashes
/// when the user hasn't configured their Supabase keys yet.
bool get supabaseReady {
  try {
    Supabase.instance.client; // throws StateError if not initialised
    return true;
  } catch (_) {
    return false;
  }
}

/// Convenient accessor — only call after checking [supabaseReady].
SupabaseClient get sb => Supabase.instance.client;

/// Table name constants — avoids hard-coded strings throughout the codebase.
class SupabaseTables {
  SupabaseTables._();
  static const String drivers  = 'drivers';
  static const String requests = 'requests';
  static const String messages = 'messages';
}
