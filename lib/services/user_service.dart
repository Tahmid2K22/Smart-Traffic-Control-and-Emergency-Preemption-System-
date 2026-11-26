import 'package:cloud_firestore/cloud_firestore.dart'
    show FirebaseFirestore, GeoPoint, Timestamp;

import '../models/user_profile.dart';
import 'supabase_service.dart';

/// Reads/writes user profiles in Supabase `users`; Firebase Auth owns identity.
class UserService {
  UserService._();

  static final UserService instance = UserService._();

  static const String _table = SupabaseTables.users;
  static const List<String> _key = ['firebase_uid'];

  Future<UserProfile?> fetch(String firebaseUid) async {
    if (!supabaseReady || firebaseUid.isEmpty) return null;
    final row = await sb
        .from(_table)
        .select()
        .eq('firebase_uid', firebaseUid)
        .maybeSingle();
    return row == null ? null : UserProfile.fromMap(row);
  }

  /// Reads the profile, migrating from Firestore once for pre-migration accounts.
  Future<UserProfile?> fetchOrMigrate(
    String firebaseUid, {
    String? fallbackName,
    String? fallbackEmail,
  }) async {
    if (!supabaseReady || firebaseUid.isEmpty) return null;

    final existing = await fetch(firebaseUid);
    if (existing != null) return existing;

    final legacy = await _legacyRowFromFirestore(firebaseUid);
    final row =
        legacy ??
        <String, dynamic>{
          'firebase_uid': firebaseUid,
          'name': fallbackName?.trim() ?? '',
          'full_name': fallbackName?.trim() ?? '',
          'email': fallbackEmail?.trim() ?? '',
          'role': 'user',
        };

    await upsert(row);
    return fetch(firebaseUid);
  }

  /// Live profile stream (role/approval routing).
  Stream<UserProfile?> watchProfile(String firebaseUid) {
    if (!supabaseReady || firebaseUid.isEmpty) {
      return Stream<UserProfile?>.value(null);
    }
    return sb
        .from(_table)
        .stream(primaryKey: _key)
        .eq('firebase_uid', firebaseUid)
        .map((rows) => rows.isEmpty ? null : UserProfile.fromMap(rows.first));
  }

  /// Live list of profiles (optional role/approval filters).
  Stream<List<UserProfile>> watchUsers({
    List<String>? roles,
    bool? isApproved,
  }) {
    if (!supabaseReady) return Stream<List<UserProfile>>.value(const []);
    final builder = sb.from(_table).stream(primaryKey: _key);
    if (roles != null && roles.isNotEmpty) {
      builder.inFilter('role', roles);
    }
    if (isApproved != null) {
      builder.eq('is_approved', isApproved);
    }
    return builder.map((rows) {
      final profiles = rows.map(UserProfile.fromMap).toList()
        ..sort((a, b) => a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        ));
      return profiles;
    });
  }

  /// Upsert by `firebase_uid`.
  Future<void> upsert(Map<String, dynamic> row) async {
    if (!supabaseReady) {
      throw StateError('Supabase is not configured. Add SUPABASE_URL and '
          'SUPABASE_ANON_KEY to .env.');
    }
    await sb.from(_table).upsert(row, onConflict: 'firebase_uid');
  }

  /// Partial update (snake_case columns).
  Future<void> update(String firebaseUid, Map<String, dynamic> fields) async {
    if (!supabaseReady || fields.isEmpty) return;
    await sb.from(_table).update(fields).eq('firebase_uid', firebaseUid);
  }

  Future<void> delete(String firebaseUid) async {
    if (!supabaseReady) return;
    await sb.from(_table).delete().eq('firebase_uid', firebaseUid);
  }

  Future<int> countUsers({
    String? role,
    List<String>? roles,
    bool? isApproved,
    String? roleNot,
    String? verificationStatus,
  }) async {
    if (!supabaseReady) return 0;
    var query = sb.from(_table).select('id');
    if (role != null) query = query.eq('role', role);
    if (roles != null && roles.isNotEmpty) query = query.inFilter('role', roles);
    if (isApproved != null) query = query.eq('is_approved', isApproved);
    if (roleNot != null) query = query.neq('role', roleNot);
    if (verificationStatus != null) {
      query = query.eq('verification_status', verificationStatus);
    }
    final rows = await query;
    return rows.length;
  }

  /// Verified traffic police profiles.
  Future<List<UserProfile>> fetchOfficers() async {
    if (!supabaseReady) return const [];
    final rows = await sb
        .from(_table)
        .select()
        .eq('role', 'traffic_police')
        .eq('is_verified', true);
    return rows.map(UserProfile.fromMap).toList();
  }

  Future<bool> isAdmin(String firebaseUid) async {
    final profile = await fetch(firebaseUid);
    return profile?.isAdmin ?? false;
  }

  /// Stores an FCM token for push delivery.
  Future<void> addFcmToken(
    String firebaseUid,
    String token, {
    required String platform,
  }) async {
    if (!supabaseReady || firebaseUid.isEmpty || token.isEmpty) return;
    final profile = await fetch(firebaseUid);
    final tokens = Map<String, dynamic>.from(profile?.fcmTokens ?? const {});
    tokens[token] = {
      'platform': platform,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await update(firebaseUid, {'fcm_tokens': tokens});
  }

  // ── Legacy Firestore import (one-time, safe to delete later) ─────────────

  Future<Map<String, dynamic>?> _legacyRowFromFirestore(
    String firebaseUid,
  ) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(firebaseUid)
          .get();
      if (!doc.exists) return null;
      final data = doc.data() ?? const <String, dynamic>{};
      final location = data['intersectionLocation'];
      final createdAt = data['createdAt'];

      final row = <String, dynamic>{
        'firebase_uid': firebaseUid,
        'name': (data['name'] ?? '').toString(),
        'full_name': (data['fullName'] ?? data['name'] ?? '').toString(),
        'email': (data['email'] ?? '').toString(),
        'phone': (data['phone'] ?? '').toString(),
        'city': data['city']?.toString(),
        'address': data['address']?.toString(),
        'role': (data['role'] ?? 'user').toString(),
        'is_approved': data['isApproved'] == true,
        'is_verified': data['isVerified'] == true,
        'verification_status': (data['verificationStatus'] ?? 'NONE').toString(),
        'is_active': data['isActive'] == true,
        'police_id': data['policeId']?.toString(),
        'assigned_intersection': data['assignedIntersection']?.toString(),
        'assigned_intersection_id': data['assignedIntersectionId']?.toString(),
        'intersection_lat': location is GeoPoint
            ? location.latitude
            : (data['intersectionLatitude'] as num?)?.toDouble(),
        'intersection_lng': location is GeoPoint
            ? location.longitude
            : (data['intersectionLongitude'] as num?)?.toDouble(),
        'driving_license': data['drivingLicense']?.toString(),
        'vehicle_type': data['vehicleType']?.toString(),
        'vehicle_number': data['vehicleNumber']?.toString(),
        'license_image_path': data['licenseImagePath']?.toString(),
        'fcm_tokens': data['fcmTokens'] is Map ? data['fcmTokens'] : <String, dynamic>{},
        'created_at': createdAt is Timestamp
            ? createdAt.toDate().toUtc().toIso8601String()
            : null,
      }..removeWhere((key, value) => value == null);

      return row;
    } catch (_) {
      return null;
    }
  }
}
