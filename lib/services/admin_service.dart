import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';
import 'user_service.dart';

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

  /// All admin logs, newest first.
  Stream<QuerySnapshot> adminLogsStream() => _firestore
      .collection('admin_logs')
      .orderBy('timestamp', descending: true)
      .limit(200)
      .snapshots();

  // ── Driver management ──────────────────────────────────────────────────────

  Stream<List<UserProfile>> pendingDriversStream() =>
      UserService.instance.watchUsers(roles: const ['driver'], isApproved: false);

  Stream<List<UserProfile>> allUsersStream() =>
      UserService.instance.watchUsers(
        roles: const ['patient', 'user', 'admin', 'traffic_police'],
      );

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

  Future<void> removeTrafficPolice(String uid, {String name = ''}) async {
    await UserService.instance.update(uid, {
      'role': 'user',
      'is_verified': false,
      'verification_status': 'NONE',
    });
    await _writeLog(
      action: 'remove_traffic_police',
      targetType: 'user',
      targetId: uid,
      targetName: name,
    );
  }

  Future<void> verifyDriver(String uid, {String name = ''}) async {
    await UserService.instance.update(uid, {'is_approved': true});
    await _writeLog(
      action: 'approve_driver',
      targetType: 'driver',
      targetId: uid,
      targetName: name,
    );
  }

  Future<void> rejectDriver(String uid, {String name = ''}) async {
    await UserService.instance.update(uid, {'is_approved': false});
    await _writeLog(
      action: 'reject_driver',
      targetType: 'driver',
      targetId: uid,
      targetName: name,
    );
  }

  Future<void> makeAdmin(String uid, {String name = ''}) async {
    await UserService.instance.update(uid, {'role': 'admin'});
    await _writeLog(
      action: 'make_admin',
      targetType: 'user',
      targetId: uid,
      targetName: name,
    );
  }

  Future<void> removeAdmin(String uid, {String name = ''}) async {
    await UserService.instance.update(uid, {'role': 'user'});
    await _writeLog(
      action: 'remove_admin',
      targetType: 'user',
      targetId: uid,
      targetName: name,
    );
  }

  // deletes profile only; auth account stays but unusable
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

  /// All hospitals.
  Stream<QuerySnapshot> allHospitalsStream() => _firestore
      .collection('hospitals')
      .orderBy('createdAt', descending: true)
      .snapshots();

  /// Pending hospitals.
  Stream<QuerySnapshot> pendingHospitalsStream() => _firestore
      .collection('hospitals')
      .where('isApproved', isEqualTo: false)
      .snapshots();

  /// Approved hospitals (booking screen).
  Stream<QuerySnapshot> approvedHospitalsStream() => _firestore
      .collection('hospitals')
      .where('isApproved', isEqualTo: true)
      .snapshots();

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

  /// Revoke an approved hospital — flips approval flags without deleting data.
  Future<void> revokeHospital(String id, {String name = ''}) async {
    final hospital = await _firestore.collection('hospitals').doc(id).get();
    await _firestore
        .collection('hospitals')
        .doc(id)
        .update({'isApproved': false});
    final registeredBy = hospital.data()?['registeredBy'] as String?;
    if (registeredBy != null && registeredBy.isNotEmpty) {
      await UserService.instance.update(registeredBy, {'is_approved': false});
    }
    await _writeLog(
      action: 'revoke_hospital',
      targetType: 'hospital',
      targetId: id,
      targetName: name,
    );
  }

  /// Hard-delete a hospital registration (used by the Delete button only).
  Future<void> deleteHospital(String id, {String name = ''}) async {
    await _firestore.collection('hospitals').doc(id).delete();
    await _writeLog(
      action: 'delete_hospital',
      targetType: 'hospital',
      targetId: id,
      targetName: name,
    );
  }

  // ── Stats ──────────────────────────────────────────────────────────────────

  // totals for overview cards
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
