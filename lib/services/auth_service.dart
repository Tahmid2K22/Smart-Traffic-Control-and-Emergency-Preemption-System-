import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
    return credential;
  }
}
