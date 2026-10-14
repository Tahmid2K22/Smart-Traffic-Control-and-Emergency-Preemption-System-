import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

// handles all admin firestore stuff
class AdminService {
  AdminService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  // ── Admin identity helpers ─────────────────────────────────────────────────

  Future<String> _adminUid() async =>
      FirebaseAuth.instance.currentUser?.uid ?? 'unknown';

  Future<String> _adminName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('userName') ?? 'Admin';
  }

  // ── Admin activity log ─────────────────────────────────────────────────────

  Future<void> _writeLog({
    required String action,
    required String targetType,
    required String targetId,
    required String targetName,
  }) async {
    try {
      await _firestore.collection('admin_logs').add({
        'adminUid': await _adminUid(),
        'adminName': await _adminName(),
        'action': action,
        'targetType': targetType,
        'targetId': targetId,
        'targetName': targetName,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Logging failure must never block the actual admin action.
    }
  }

  /// Stream of all admin logs, newest first.
  Stream<QuerySnapshot> adminLogsStream() => _firestore
      .collection('admin_logs')
      .orderBy('timestamp', descending: true)
      .limit(200)
      .snapshots();

  // ── Driver management ──────────────────────────────────────────────────────

  // live stream of all drivers
  Stream<QuerySnapshot> allDriversStream() => _firestore
      .collection('users')
      .where('role', isEqualTo: 'driver')
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
      .where('role', whereIn: ['user', 'admin']).snapshots();

  // approve driver
  Future<void> verifyDriver(String uid, {String name = ''}) async {
    await _firestore.collection('users').doc(uid).update({'isApproved': true});
    await _writeLog(
      action: 'approve_driver',
      targetType: 'driver',
      targetId: uid,
      targetName: name,
    );
  }

  // un-approve driver
  Future<void> rejectDriver(String uid, {String name = ''}) async {
    await _firestore.collection('users').doc(uid).update({'isApproved': false});
    await _writeLog(
      action: 'reject_driver',
      targetType: 'driver',
      targetId: uid,
      targetName: name,
    );
  }

  // give someone admin powers
  Future<void> makeAdmin(String uid, {String name = ''}) async {
    await _firestore.collection('users').doc(uid).update({'role': 'admin'});
    await _writeLog(
      action: 'make_admin',
      targetType: 'user',
      targetId: uid,
      targetName: name,
    );
  }

  // take admin powers away
  Future<void> removeAdmin(String uid, {String name = ''}) async {
    await _firestore.collection('users').doc(uid).update({'role': 'user'});
    await _writeLog(
      action: 'remove_admin',
      targetType: 'user',
      targetId: uid,
      targetName: name,
    );
  }

  // removes the user doc — auth account stays but they can't use the app
  Future<void> deleteUser(String uid, {String name = ''}) async {
    await _firestore.collection('users').doc(uid).delete();
    await _writeLog(
      action: 'delete_user',
      targetType: 'user',
      targetId: uid,
      targetName: name,
    );
  }

  // ── Hospital management ────────────────────────────────────────────────────

  /// All hospitals (for admin management view)
  Stream<QuerySnapshot> allHospitalsStream() => _firestore
      .collection('hospitals')
      .orderBy('createdAt', descending: true)
      .snapshots();

  /// Hospitals pending approval
  Stream<QuerySnapshot> pendingHospitalsStream() => _firestore
      .collection('hospitals')
      .where('isApproved', isEqualTo: false)
      .snapshots();

  /// Only approved hospitals (used by booking screen)
  Stream<QuerySnapshot> approvedHospitalsStream() => _firestore
      .collection('hospitals')
      .where('isApproved', isEqualTo: true)
      .snapshots();

  /// Approve a hospital
  Future<void> approveHospital(String id, {String name = ''}) async {
    await _firestore
        .collection('hospitals')
        .doc(id)
        .update({'isApproved': true});
    await _writeLog(
      action: 'approve_hospital',
      targetType: 'hospital',
      targetId: id,
      targetName: name,
    );
  }

  /// Reject (delete) a hospital registration
  Future<void> rejectHospital(String id, {String name = ''}) async {
    await _firestore.collection('hospitals').doc(id).delete();
    await _writeLog(
      action: 'reject_hospital',
      targetType: 'hospital',
      targetId: id,
      targetName: name,
    );
  }

  // ── Stats ──────────────────────────────────────────────────────────────────

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
      _firestore.collection('hospitals').count().get(),
      _firestore
          .collection('hospitals')
          .where('isApproved', isEqualTo: false)
          .count()
          .get(),
    ]);

    return {
      'totalUsers': results[0].count ?? 0,
      'totalDrivers': results[1].count ?? 0,
      'pendingDrivers': results[2].count ?? 0,
      'totalAdmins': results[3].count ?? 0,
      'totalHospitals': results[4].count ?? 0,
      'pendingHospitals': results[5].count ?? 0,
    };
  }
}
