import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:geocoding/geocoding.dart';

import '../models/models.dart';

/// Handles hospital registration and approved-hospital queries used by the
/// booking screen and home page.
class HospitalService {
  HospitalService({FirebaseFirestore? firestore})
    : _providedFirestore = firestore;

  final FirebaseFirestore? _providedFirestore;

  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;

  // ── Registration ───────────────────────────────────────────────────────────

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

  // ── Seed real hospitals ───────────────────────────────────────────────────

  /// Seeds default verified hospitals (both Dhaka and Khulna) into Firestore if missing.
  Future<void> seedDefaultHospitals() async {
    final seeds = [
      // Dhaka
      {
        'name': 'Dhaka Medical College Hospital',
        'city': 'Dhaka',
        'address': 'Secretariat Road, Ramna, Dhaka',
        'lat': 23.7257,
        'lon': 90.3976,
        'beds': 2600,
        'services': [
          'Emergency 24/7',
          'ICU',
          'Burn Unit',
          'Surgery',
          'Blood Bank',
        ],
        'diagnoses': [
          'Cardiology',
          'Neurology',
          'Orthopedics',
          'General Medicine',
          'Trauma',
        ],
        'isApproved': true,
        'registeredBy': 'system_seed',
        'createdAt': FieldValue.serverTimestamp(),
      },
      {
        'name': 'Bangabandhu Sheikh Mujib Medical University (BSMMU)',
        'city': 'Dhaka',
        'address': 'Shahbag, Dhaka',
        'lat': 23.7388,
        'lon': 90.3957,
        'beds': 1900,
        'services': [
          'Emergency 24/7',
          'ICU',
          'CCU',
          'Transplant',
          'Diagnostics',
        ],
        'diagnoses': ['Cardiology', 'Nephrology', 'Oncology', 'Neurology'],
        'isApproved': true,
        'registeredBy': 'system_seed',
        'createdAt': FieldValue.serverTimestamp(),
      },
      {
        'name': 'Square Hospital',
        'city': 'Dhaka',
        'address': '18/F Bir Uttam Qazi Nuruzzaman Sarak, Panthapath, Dhaka',
        'lat': 23.7533,
        'lon': 90.3816,
        'beds': 400,
        'services': [
          'Emergency 24/7',
          'ICU',
          'NICU',
          'Cardiac Center',
          'Ambulance',
        ],
        'diagnoses': ['Cardiology', 'Critical Care', 'Surgery', 'Pediatrics'],
        'isApproved': true,
        'registeredBy': 'system_seed',
        'createdAt': FieldValue.serverTimestamp(),
      },
      {
        'name': 'United Hospital',
        'city': 'Dhaka',
        'address': 'Plot 15, Road 71, Gulshan-2, Dhaka',
        'lat': 23.7997,
        'lon': 90.4194,
        'beds': 500,
        'services': [
          'Emergency 24/7',
          'Trauma Center',
          'ICU',
          'Helipad',
          'Cardiac Center',
        ],
        'diagnoses': [
          'Cardiology',
          'Neurology',
          'Oncology',
          'Gastroenterology',
        ],
        'isApproved': true,
        'registeredBy': 'system_seed',
        'createdAt': FieldValue.serverTimestamp(),
      },
      {
        'name': 'Evercare Hospital Dhaka',
        'city': 'Dhaka',
        'address': 'Plot 81, Block E, Bashundhara R/A, Dhaka',
        'lat': 23.8105,
        'lon': 90.4312,
        'beds': 425,
        'services': [
          'Emergency 24/7',
          'ICU',
          'Surgery',
          'Pediatrics',
          'Ambulance',
        ],
        'diagnoses': ['Cardiology', 'Neurology', 'Orthopedics', 'Pediatrics'],
        'isApproved': true,
        'registeredBy': 'system_seed',
        'createdAt': FieldValue.serverTimestamp(),
      },
      {
        'name': 'Kurmitola General Hospital',
        'city': 'Dhaka',
        'address': 'Dhaka - Mymensingh Highway, Dhaka Cantt, Dhaka',
        'lat': 23.8247,
        'lon': 90.4079,
        'beds': 500,
        'services': ['Emergency 24/7', 'ICU', 'OPD', 'Surgery', 'Diagnostics'],
        'diagnoses': ['General Medicine', 'Surgery', 'Orthopedics'],
        'isApproved': true,
        'registeredBy': 'system_seed',
        'createdAt': FieldValue.serverTimestamp(),
      },
      {
        'name': 'Shaheed Suhrawardy Medical College Hospital',
        'city': 'Dhaka',
        'address': 'Sher-e-Bangla Nagar, Dhaka',
        'lat': 23.7701,
        'lon': 90.3712,
        'beds': 875,
        'services': ['Emergency 24/7', 'ICU', 'Burn Unit', 'Blood Bank'],
        'diagnoses': [
          'General Medicine',
          'Cardiology',
          'Pediatrics',
          'Orthopedics',
        ],
        'isApproved': true,
        'registeredBy': 'system_seed',
        'createdAt': FieldValue.serverTimestamp(),
      },
      {
        'name': 'National Institute of Cardiovascular Diseases (NICVD)',
        'city': 'Dhaka',
        'address': 'Sher-e-Bangla Nagar, Dhaka',
        'lat': 23.7711,
        'lon': 90.3702,
        'beds': 414,
        'services': ['Cardiac Emergency 24/7', 'ICU', 'CCU', 'Cath Lab'],
        'diagnoses': ['Cardiology', 'Cardiac Surgery', 'Vascular Surgery'],
        'isApproved': true,
        'registeredBy': 'system_seed',
        'createdAt': FieldValue.serverTimestamp(),
      },
      // Khulna
      {
        'name': 'Khulna Medical College Hospital',
        'city': 'Khulna',
        'address': 'Boyra, Khulna',
        'lat': 22.8456,
        'lon': 89.5403,
        'beds': 500,
        'services': ['Emergency', 'ICU', 'Surgery', 'OPD', 'Cardiology'],
        'diagnoses': [
          'General Medicine',
          'Cardiology',
          'Neurology',
          'Oncology',
        ],
        'isApproved': true,
        'registeredBy': 'system_seed',
        'createdAt': FieldValue.serverTimestamp(),
      },
      {
        'name': 'Shaheed Sheikh Abu Naser Specialized Hospital',
        'city': 'Khulna',
        'address': 'Mujgunni, Khulna',
        'lat': 22.8269,
        'lon': 89.5536,
        'beds': 300,
        'services': ['Emergency', 'ICU', 'OPD', 'Burn Unit'],
        'diagnoses': [
          'General Medicine',
          'Orthopedics',
          'Gynecology',
          'Pediatrics',
        ],
        'isApproved': true,
        'registeredBy': 'system_seed',
        'createdAt': FieldValue.serverTimestamp(),
      },
      {
        'name': 'Gazi Medical College & Hospital',
        'city': 'Khulna',
        'address': 'A21-23 Majgunni R/A, Sonadanga, Khulna',
        'lat': 22.8155,
        'lon': 89.5511,
        'beds': 250,
        'services': ['Emergency', 'Surgery', 'OPD', 'Diagnostics'],
        'diagnoses': ['General Medicine', 'Cardiology', 'Dermatology'],
        'isApproved': true,
        'registeredBy': 'system_seed',
        'createdAt': FieldValue.serverTimestamp(),
      },
      {
        'name': 'Ad-Din Akij Medical College Hospital',
        'city': 'Khulna',
        'address': 'Boyra, Khulna',
        'lat': 22.8341,
        'lon': 89.5500,
        'beds': 200,
        'services': ['Emergency', 'OPD', 'Maternity', 'Neonatal ICU'],
        'diagnoses': ['Gynecology', 'Pediatrics', 'Obstetrics', 'Neonatology'],
        'isApproved': true,
        'registeredBy': 'system_seed',
        'createdAt': FieldValue.serverTimestamp(),
      },
      {
        'name': 'Popular Diagnostic Centre Khulna',
        'city': 'Khulna',
        'address': 'Shibbari More, Khulna',
        'lat': 22.8298,
        'lon': 89.5573,
        'beds': 50,
        'services': ['Diagnostics', 'OPD', 'Laboratory', 'Imaging'],
        'diagnoses': ['General Medicine', 'Pathology', 'Radiology'],
        'isApproved': true,
        'registeredBy': 'system_seed',
        'createdAt': FieldValue.serverTimestamp(),
      },
    ];

    try {
      for (final hospital in seeds) {
        final name = hospital['name'] as String;
        final existing = await _firestore
            .collection('hospitals')
            .where('name', isEqualTo: name)
            .limit(1)
            .get();
        if (existing.docs.isEmpty) {
          await _firestore.collection('hospitals').add(hospital);
        }
      }
    } catch (_) {}
  }

  /// Backward compatibility alias
  Future<void> seedKhulnaHospitals() async {
    await seedDefaultHospitals();
  }
}
