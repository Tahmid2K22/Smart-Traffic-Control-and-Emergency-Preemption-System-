import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'request_service.dart';
import 'supabase_service.dart';

class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

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

    // ── Write to Firebase Firestore ──────────────────────────
    final profile = <String, dynamic>{
      'name': name.trim(),
      'email': email.trim(),
      'phone': phone.trim(),
      'city': city,
      'role': role,
      'createdAt': FieldValue.serverTimestamp(),
    };

    if (role == 'driver') {
      profile.addAll({
        'drivingLicense': drivingLicense!.trim(),
        'vehicleType': vehicleType,
        'vehicleNumber': vehicleNumber!.trim(),
        'licenseImagePath': licenseImagePath,
        'isApproved': false,
      });
    }

    await _firestore.collection('users').doc(user.uid).set(profile);

    // ── Sync driver to Supabase drivers table ────────────────
    if (role == 'driver' && supabaseReady) {
      try {
        await RequestService.upsertDriverProfile(
          firebaseUid: user.uid,
          name: name.trim(),
          phone: phone.trim(),
          vehicleType: vehicleType ?? 'Basic Ambulance',
          vehicleNumber: vehicleNumber!.trim(),
        );
      } catch (e) {
        // Non-fatal: driver can still log in; profile will sync on next login
      }
    }

    return credential;
  }

  /// Called on login for drivers — ensures their Supabase row is up to date.
  static Future<void> syncDriverOnLogin({
    required String firebaseUid,
    required Map<String, dynamic> firestoreData,
  }) async {
    if (!supabaseReady) return;
    final role = firestoreData['role'] ?? 'user';
    if (role != 'driver') return;
    try {
      await RequestService.upsertDriverProfile(
        firebaseUid: firebaseUid,
        name: firestoreData['name'] ?? '',
        phone: firestoreData['phone'] ?? '',
        vehicleType: firestoreData['vehicleType'] ?? 'Basic Ambulance',
        vehicleNumber: firestoreData['vehicleNumber'] ?? '',
      );
    } catch (_) {}
  }
}
