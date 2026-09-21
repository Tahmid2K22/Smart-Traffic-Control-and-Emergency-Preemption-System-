import 'package:cloud_firestore/cloud_firestore.dart';

// handles all admin firestore stuff
class AdminService {
  AdminService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  // live stream of all drivers
  Stream<QuerySnapshot> allDriversStream() => _firestore
      .collection('users')
      .where('role', isEqualTo: 'driver')
      .orderBy('createdAt', descending: true)
      .snapshots();

  // only drivers waiting for approval
  Stream<QuerySnapshot> pendingDriversStream() => _firestore
      .collection('users')
      .where('role', isEqualTo: 'driver')
      .where('isApproved', isEqualTo: false)
      .snapshots();

  // regular users and admins
  Stream<QuerySnapshot> allUsersStream() => _firestore
      .collection('users')
      .where('role', whereIn: ['user', 'admin'])
      .orderBy('createdAt', descending: true)
      .snapshots();

  // approve driver
  Future<void> verifyDriver(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .update({'isApproved': true});

  // un-approve driver
  Future<void> rejectDriver(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .update({'isApproved': false});

  // give someone admin powers
  Future<void> makeAdmin(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .update({'role': 'admin'});

  // take admin powers away
  Future<void> removeAdmin(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .update({'role': 'user'});

  // removes the user doc — auth account stays but they can't use the app
  Future<void> deleteUser(String uid) =>
      _firestore.collection('users').doc(uid).delete();

  // grabs total counts for the overview cards
  Future<Map<String, int>> fetchStats() async {
    final results = await Future.wait([
      _firestore
          .collection('users')
          .where('role', isEqualTo: 'user')
          .count()
          .get(),
      _firestore
          .collection('users')
          .where('role', isEqualTo: 'driver')
          .count()
          .get(),
      _firestore
          .collection('users')
          .where('role', isEqualTo: 'driver')
          .where('isApproved', isEqualTo: false)
          .count()
          .get(),
      _firestore
          .collection('users')
          .where('role', isEqualTo: 'admin')
          .count()
          .get(),
    ]);

    return {
      'totalUsers': results[0].count ?? 0,
      'totalDrivers': results[1].count ?? 0,
      'pendingDrivers': results[2].count ?? 0,
      'totalAdmins': results[3].count ?? 0,
    };
  }
}
