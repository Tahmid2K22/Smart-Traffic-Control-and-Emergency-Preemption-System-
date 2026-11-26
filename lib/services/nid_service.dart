import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Verifies a Bangladeshi NID against Supabase `nid_records`.
class NidService {
  /// A Bangladeshi NID is 10, 13 or 17 digits.
  static bool isValidNidFormat(String nid) =>
      RegExp(r'^\d{10}$|^\d{13}$|^\d{17}$').hasMatch(nid.trim());

  /// Matches details against a stored record. Returns false if Supabase unconfigured.
  static Future<bool> verifyNid({
    required String nidNumber,
    required String fullName,
    required DateTime dateOfBirth,
  }) async {
    if (!supabaseReady) return false;
    if (!isValidNidFormat(nidNumber)) return false;
    try {
      final response = await sb
          .from(SupabaseTables.nidRecords)
          .select()
          .eq('nid_number', nidNumber.trim())
          .eq('full_name', fullName.trim())
          .eq('date_of_birth', dateOfBirth.toIso8601String().split('T').first)
          .maybeSingle();
      return response != null;
    } on PostgrestException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
