import 'package:supabase_flutter/supabase_flutter.dart';

/// True when Supabase is initialised. Guard calls with this.
bool get supabaseReady {
  try {
    Supabase.instance.client; // throws StateError if not initialised
    return true;
  } catch (_) {
    return false;
  }
}

/// Supabase client accessor (check [supabaseReady] first).
SupabaseClient get sb => Supabase.instance.client;

/// Table name constants.
class SupabaseTables {
  SupabaseTables._();
  static const String drivers     = 'drivers';
  static const String requests    = 'requests';
  static const String messages    = 'messages';
  static const String nidRecords  = 'nid_records';
  static const String users       = 'users';
}
