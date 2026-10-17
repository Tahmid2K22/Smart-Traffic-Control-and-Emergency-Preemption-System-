import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

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
    String? policeId,
    String? assignedIntersection,
    XFile? badgeImage,
  }) async {
    if (role == 'driver' &&
        (drivingLicense == null ||
            vehicleType == null ||
            vehicleNumber == null ||
            licenseImagePath == null)) {
      throw ArgumentError('All driver registration fields are required.');
    }
    if (role == 'traffic_police' &&
        (policeId == null ||
            policeId.trim().isEmpty ||
            assignedIntersection == null ||
            assignedIntersection.trim().isEmpty ||
            badgeImage == null)) {
      throw ArgumentError('All traffic police registration fields are required.');
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
      'uid': user.uid,
      'name': name.trim(),
      'fullName': name.trim(),
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

    if (role == 'traffic_police') {
      final badgeRef = FirebaseStorage.instance
          .ref()
          .child('police_badges')
          .child('${user.uid}.jpg');
      await badgeRef.putData(
        await badgeImage!.readAsBytes(),
        SettableMetadata(contentType: 'image/jpeg'),
      );
      profile.addAll({
        'uid': user.uid,
        'fullName': name.trim(),
        'policeId': policeId!.trim(),
        'assignedIntersection': assignedIntersection!.trim(),
        'badgeImageUrl': await badgeRef.getDownloadURL(),
        'isVerified': false,
        'verificationStatus': 'PENDING',
        'isActive': false,
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

  /// Called on login for drivers — ensures their Supabase row is up to date,
  /// including the admin-set `isApproved` flag from Firestore.
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
        name: firestoreData['name'] as String? ?? '',
        phone: firestoreData['phone'] as String? ?? '',
        vehicleType: firestoreData['vehicleType'] as String? ?? 'Basic Ambulance',
        vehicleNumber: firestoreData['vehicleNumber'] as String? ?? '',
        isApproved: firestoreData['isApproved'] == true,
      );
    } catch (_) {}
  }
}
