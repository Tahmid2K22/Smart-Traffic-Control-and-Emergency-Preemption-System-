import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Handles hospital registration and approved-hospital queries used by the
/// booking screen and home page.
class HospitalService {
  HospitalService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  // ── Registration ───────────────────────────────────────────────────────────

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
