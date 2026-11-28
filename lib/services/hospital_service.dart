  //  Registration 
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:geocoding/geocoding.dart';

import '../models/models.dart';
import '../services/user_service.dart';

/// Hospital registration + approved-hospital queries.
class HospitalService {
  HospitalService({FirebaseFirestore? firestore})
    : _providedFirestore = firestore;

  final FirebaseFirestore? _providedFirestore;

  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;

  //  Registration 

  Future<UserCredential> registerHospitalAccount({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String address,
  }) async {
    final credential = await FirebaseAuth.instance
        .createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
    final user = credential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'hospital-registration-failed',
        message: 'The hospital account could not be created.',
      );
    }

    await UserService.instance.upsert({
      'firebase_uid': user.uid,
      'name': name.trim(),
      'full_name': name.trim(),
      'email': email.trim(),
      'phone': phone.trim(),
      'address': address.trim(),
      'role': 'hospital',
      'is_approved': false,
    });

    double lat = 0;
    double lon = 0;
    try {
      final locations = await Geocoding().locationFromAddress(
        '$address, Bangladesh',
      );
      if (locations.isNotEmpty) {
        lat = locations.first.latitude;
        lon = locations.first.longitude;
      }
    } catch (_) {}

    try {
      await _firestore.collection('hospitals').add({
        'name': name.trim(),
        'email': email.trim(),
        'phone': phone.trim(),
        'address': address.trim(),
        'lat': lat,
        'lon': lon,
        if (lat != 0 || lon != 0) 'location': GeoPoint(lat, lon),
        'services': <String>[],
        'diagnoses': <String>[],
        'beds': 0,
        'isApproved': false,
        'registeredBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on Exception {
      // Never leave a working login with no hospital record behind.
      try {
        await user.delete();
      } catch (_) {}
      rethrow;
    }

    // createUserWithEmailAndPassword signed the app in as the new hospital.
    // Hand the session back — the account is unusable until an admin approves.
    await FirebaseAuth.instance.signOut();

    return credential;
  }

  // ── Queries ────────────────────────────────────────────────────────────────

  /// Live stream of approved hospitals (booking screen).
  Stream<QuerySnapshot> approvedHospitalsStream() {
    if (Firebase.apps.isEmpty) {
      return const Stream.empty();
    }
    return _firestore
        .collection('hospitals')
        .where('isApproved', isEqualTo: true)
        .snapshots();
  }

  Future<List<HospitalModel>> approvedHospitalsOnce() async {
    if (Firebase.apps.isEmpty) return const [];
    final snapshot = await _firestore
        .collection('hospitals')
        .where('isApproved', isEqualTo: true)
        .get();
    return snapshot.docs.map(HospitalModel.fromDoc).toList();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> getHospitalForUser(
    String uid,
  ) async {
    final result = await _firestore
        .collection('hospitals')
        .where('registeredBy', isEqualTo: uid)
        .limit(1)
        .get();
    if (result.docs.isEmpty) {
      throw StateError('No hospital profile was found for this account.');
    }
    return result.docs.first;
  }

  Future<void> updateHospitalProfile({
    required String hospitalId,
    required String address,
    required int beds,
    required List<String> services,
    required List<String> specialties,
    double? latitude,
    double? longitude,
  }) async {
    final updates = <String, dynamic>{
      'address': address.trim(),
      'beds': beds,
      'services': services,
      'diagnoses': specialties,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (latitude != null && longitude != null) {
      updates['lat'] = latitude;
      updates['lon'] = longitude;
      updates['location'] = GeoPoint(latitude, longitude);
    }
    await _firestore.collection('hospitals').doc(hospitalId).update(updates);
  }
}