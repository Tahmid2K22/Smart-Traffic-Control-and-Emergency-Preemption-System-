import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';
import 'user_service.dart';

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

  // only drivers waiting for approval
  Stream<List<UserProfile>> pendingDriversStream() =>
      UserService.instance.watchUsers(roles: const ['driver'], isApproved: false);

  // regular users, admins, and traffic police
  Stream<List<UserProfile>> allUsersStream() =>
      UserService.instance.watchUsers(
        roles: const ['patient', 'user', 'admin', 'traffic_police'],
      );

  // make a user traffic police
  Future<void> makeTrafficPolice(
    String uid, {
    String name = '',
    String policeId = '',
    String assignedIntersection = '',
  }) async {
    await UserService.instance.update(uid, {
      'role': 'traffic_police',
      'is_verified': true,
      'verification_status': 'APPROVED',
      'is_active': false,
      if (policeId.isNotEmpty) 'police_id': policeId,
      if (assignedIntersection.isNotEmpty)
        'assigned_intersection': assignedIntersection,
    });
    await _writeLog(
      action: 'make_traffic_police',
      targetType: 'user',
      targetId: uid,
      targetName: name,
    );
  }

  // revoke traffic police powers back to standard user
  Future<void> removeTrafficPolice(String uid, {String name = ''}) async {
    await UserService.instance.update(uid, {
      'role': 'user',
      'is_verified': false,
      'verification_status': 'NONE',
      'is_active': false,
    });
    await _writeLog(
      action: 'remove_traffic_police',
      targetType: 'user',
      targetId: uid,
      targetName: name,
    );
  }

  // approve driver
  Future<void> verifyDriver(String uid, {String name = ''}) async {
    await UserService.instance.update(uid, {'is_approved': true});
    await _writeLog(
      action: 'approve_driver',
      targetType: 'driver',
      targetId: uid,
      targetName: name,
    );
  }

  // un-approve driver
  Future<void> rejectDriver(String uid, {String name = ''}) async {
    await UserService.instance.update(uid, {'is_approved': false});
    await _writeLog(
      action: 'reject_driver',
      targetType: 'driver',
      targetId: uid,
      targetName: name,
    );
  }

  // give someone admin powers
  Future<void> makeAdmin(String uid, {String name = ''}) async {
    await UserService.instance.update(uid, {'role': 'admin'});
    await _writeLog(
      action: 'make_admin',
      targetType: 'user',
      targetId: uid,
      targetName: name,
    );
  }

  // take admin powers away
  Future<void> removeAdmin(String uid, {String name = ''}) async {
    await UserService.instance.update(uid, {'role': 'user'});
    await _writeLog(
      action: 'remove_admin',
      targetType: 'user',
      targetId: uid,
      targetName: name,
    );
  }

  // removes the user profile — auth account stays but they can't use the app
  Future<void> deleteUser(String uid, {String name = ''}) async {
    await UserService.instance.delete(uid);
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
    final hospital = await _firestore.collection('hospitals').doc(id).get();
    await _firestore.collection('hospitals').doc(id).update({'isApproved': true});
    final registeredBy = hospital.data()?['registeredBy'] as String?;
    if (registeredBy != null && registeredBy.isNotEmpty) {
      await UserService.instance.update(registeredBy, {'is_approved': true});
    }
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
      UserService.instance.countUsers(
        role: 'traffic_police',
        verificationStatus: 'PENDING',
      ),
      UserService.instance.countUsers(roles: const ['user', 'patient']),
      UserService.instance.countUsers(role: 'driver'),
      UserService.instance.countUsers(role: 'driver', isApproved: false),
      UserService.instance.countUsers(role: 'admin'),
      _firestore.collection('hospitals').count().get().then((r) => r.count ?? 0),
      _firestore
          .collection('hospitals')
          .where('isApproved', isEqualTo: false)
          .count()
          .get()
          .then((r) => r.count ?? 0),
    ]);

    return {
      'pendingTrafficPolice': results[0],
      'totalUsers': results[1],
      'totalDrivers': results[2],
      'pendingDrivers': results[3],
      'totalAdmins': results[4],
      'totalHospitals': results[5],
      'pendingHospitals': results[6],
    };
  }
}
