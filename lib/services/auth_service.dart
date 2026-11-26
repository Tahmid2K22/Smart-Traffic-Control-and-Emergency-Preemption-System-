import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_profile.dart';
import 'request_service.dart';
import 'supabase_service.dart';
import 'user_service.dart';

/// Handles account creation and login sync.
/// Firebase Auth owns credentials/sessions; profile lives in Supabase `users` via [UserService].
class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  Future<UserCredential> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String city,
    required String role,
    String? drivingLicense,
    String? vehicleType,
    String? vehicleNumber,
    String? licenseImagePath,
  }) async {
    if (role == 'driver' &&
        (drivingLicense == null ||
            vehicleType == null ||
            vehicleNumber == null ||
            licenseImagePath == null)) {
      throw ArgumentError('All driver registration fields are required.');
    }

    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;

    if (user == null) {
      throw FirebaseAuthException(
        code: 'registration-failed',
        message: 'The account could not be created.',
      );
    }
    await user.updateDisplayName(name.trim());

    // ── User profile → Supabase ────────────────────────────────────────────
    final row = <String, dynamic>{
      'firebase_uid': user.uid,
      'name': name.trim(),
      'full_name': name.trim(),
      'email': email.trim(),
      'phone': phone.trim(),
      'city': city.trim().isEmpty ? null : city,
      'role': role,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (role == 'driver') {
      row.addAll({
        'driving_license': drivingLicense!.trim(),
        'vehicle_type': vehicleType,
        'vehicle_number': vehicleNumber!.trim(),
        'license_image_path': licenseImagePath,
        'is_approved': false,
      });
    }

    row.removeWhere((key, value) => value == null);

    try {
      await UserService.instance.upsert(row);
    } catch (error) {
      // Never leave a working login with no profile behind.
      try {
        await user.delete();
      } catch (_) {}
      throw StateError(
        'Could not save your profile: $error',
      );
    }

    // ── Driver row for dispatch (Supabase `drivers`) ───────────────────────
    if (role == 'driver' && supabaseReady) {
      try {
        await RequestService.upsertDriverProfile(
          firebaseUid: user.uid,
          name: name.trim(),
          phone: phone.trim(),
          vehicleType: vehicleType ?? 'Basic Ambulance',
          vehicleNumber: vehicleNumber!.trim(),
        );
      } catch (_) {
        // Non-fatal: driver can still log in; profile will sync on next login
      }
    }

    return credential;
  }

  /// Syncs driver row on login.
  static Future<void> syncDriverOnLogin({required UserProfile profile}) async {
    if (!supabaseReady || !profile.isDriver) return;
    try {
      await RequestService.upsertDriverProfile(
        firebaseUid: profile.uid,
        name: profile.name,
        phone: profile.phone,
        vehicleType: profile.vehicleType ?? 'Basic Ambulance',
        vehicleNumber: profile.vehicleNumber ?? '',
        isApproved: profile.isApproved,
      );
    } catch (_) {}
  }
}
