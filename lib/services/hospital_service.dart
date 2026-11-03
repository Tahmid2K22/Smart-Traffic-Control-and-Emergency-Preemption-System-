import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Handles hospital registration and approved-hospital queries used by the
/// booking screen and home page.
class HospitalService {
  HospitalService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  // ── Registration ───────────────────────────────────────────────────────────

  Future<UserCredential> registerHospitalAccount({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String address,
  }) async {
    final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
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

    await _firestore.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'name': name.trim(),
      'fullName': name.trim(),
      'email': email.trim(),
      'phone': phone.trim(),
      'address': address.trim(),
      'role': 'hospital',
      'isApproved': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _firestore.collection('hospitals').add({
      'name': name.trim(),
      'email': email.trim(),
      'phone': phone.trim(),
      'address': address.trim(),
      'services': <String>[],
      'diagnoses': <String>[],
      'beds': 0,
      'isApproved': false,
      'registeredBy': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return credential;
  }

  Future<void> registerHospital({
    required String name,
    required String city,
    required double lat,
    required double lon,
    required int beds,
    required List<String> services,
    required List<String> diagnoses,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    await _firestore.collection('hospitals').add({
      'name': name,
      'city': city,
      'lat': lat,
      'lon': lon,
      'beds': beds,
      'services': services,
      'diagnoses': diagnoses,
      'isApproved': false,
      'registeredBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Queries ────────────────────────────────────────────────────────────────

  /// Live stream of approved hospitals only — used by the booking screen.
  Stream<QuerySnapshot> approvedHospitalsStream() => _firestore
      .collection('hospitals')
      .where('isApproved', isEqualTo: true)
      .snapshots();

  Future<DocumentSnapshot<Map<String, dynamic>>> getHospitalForUser(
      String uid) async {
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

  // ── Seed real Khulna hospitals ─────────────────────────────────────────────

  /// Inserts 5 real Khulna hospitals (all pre-approved).
  /// Safe to call multiple times — checks by name to avoid duplicates.
  Future<void> seedKhulnaHospitals() async {
    final seeds = [
      {
        'name': 'Khulna Medical College Hospital',
        'city': 'Khulna',
        'lat': 22.8456,
        'lon': 89.5403,
        'beds': 500,
        'services': ['Emergency', 'ICU', 'Surgery', 'OPD', 'Cardiology'],
        'diagnoses': ['General Medicine', 'Cardiology', 'Neurology', 'Oncology'],
        'isApproved': true,
        'registeredBy': 'seed',
        'createdAt': FieldValue.serverTimestamp(),
      },
      {
        'name': 'Shaheed Sheikh Abu Naser Specialized Hospital',
        'city': 'Khulna',
        'lat': 22.8269,
        'lon': 89.5536,
        'beds': 300,
        'services': ['Emergency', 'ICU', 'OPD', 'Burn Unit'],
        'diagnoses': ['General Medicine', 'Orthopedics', 'Gynecology', 'Pediatrics'],
        'isApproved': true,
        'registeredBy': 'seed',
        'createdAt': FieldValue.serverTimestamp(),
      },
      {
        'name': 'Gazi Medical College & Hospital',
        'city': 'Khulna',
        'lat': 22.8155,
        'lon': 89.5511,
        'beds': 250,
        'services': ['Emergency', 'Surgery', 'OPD', 'Diagnostics'],
        'diagnoses': ['General Medicine', 'Cardiology', 'Dermatology'],
        'isApproved': true,
        'registeredBy': 'seed',
        'createdAt': FieldValue.serverTimestamp(),
      },
      {
        'name': 'Ad-Din Akij Medical College Hospital',
        'city': 'Khulna',
        'lat': 22.8341,
        'lon': 89.5500,
        'beds': 200,
        'services': ['Emergency', 'OPD', 'Maternity', 'Neonatal ICU'],
        'diagnoses': ['Gynecology', 'Pediatrics', 'Obstetrics', 'Neonatology'],
        'isApproved': true,
        'registeredBy': 'seed',
        'createdAt': FieldValue.serverTimestamp(),
      },
      {
        'name': 'Popular Diagnostic Centre Khulna',
        'city': 'Khulna',
        'lat': 22.8298,
        'lon': 89.5573,
        'beds': 50,
        'services': ['Diagnostics', 'OPD', 'Laboratory', 'Imaging'],
        'diagnoses': ['General Medicine', 'Pathology', 'Radiology'],
        'isApproved': true,
        'registeredBy': 'seed',
        'createdAt': FieldValue.serverTimestamp(),
      },
    ];

    for (final hospital in seeds) {
      final name = hospital['name'] as String;
      // Check if already seeded
      final existing = await _firestore
          .collection('hospitals')
          .where('name', isEqualTo: name)
          .limit(1)
          .get();
      if (existing.docs.isEmpty) {
        await _firestore.collection('hospitals').add(hospital);
      }
    }
  }
}
