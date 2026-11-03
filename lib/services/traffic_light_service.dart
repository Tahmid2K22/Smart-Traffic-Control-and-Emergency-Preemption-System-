import 'package:cloud_firestore/cloud_firestore.dart';

/// Service for managing traffic light documents in Firestore.
///
/// Firestore collection: `traffic_lights/{intersectionId}`
/// Fields:
///   status          : String  — "green" | "red" | "yellow" | "auto"
///   mode            : String  — "manual" | "auto"
///   autoGreenSeconds  : int
///   autoRedSeconds    : int
///   autoYellowSeconds : int
///   location        : String  — human-readable name
///   lastUpdatedBy   : String  — UID
///   lastUpdatedAt   : Timestamp
///   isOnline        : bool    — ESP32 heartbeat flag
///   lastHeartbeat   : Timestamp
class TrafficLightService {
  TrafficLightService._();

  static final _col =
      FirebaseFirestore.instance.collection('traffic_lights');

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Stream every intersection document in real time.
  static Stream<QuerySnapshot> watchAllLights() =>
      _col.orderBy('location').snapshots();

  /// Stream a single intersection document.
  static Stream<DocumentSnapshot> watchLight(String id) =>
      _col.doc(id).snapshots();

  // ── Authorization ─────────────────────────────────────────────────────────

  /// Verifies if a user has permission to modify traffic light states.
  /// Only verified Traffic Police officers and Administrators are permitted.
  static Future<bool> isAuthorized(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data() ?? {};
      final role = data['role'] as String? ?? 'user';
      final isVerified = (data['isVerified'] == true && data['verificationStatus'] == 'APPROVED') || role == 'admin';
      return (role == 'traffic_police' && isVerified) || role == 'admin';
    } catch (_) {
      return false;
    }
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Switch to manual mode and set the light colour.
  /// [status] must be one of: `"red"`, `"yellow"`, `"green"`.
  static Future<void> setLightStatus(
    String id,
    String status,
    String uid,
  ) async {
    final allowed = await isAuthorized(uid);
    if (!allowed) {
      throw Exception('Permission denied: Only verified Traffic Police or Admin can update traffic lights.');
    }

    await _col.doc(id).update({
      'status': status,
      'mode': 'manual',
      'lastUpdatedBy': uid,
      'lastUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Switch to auto mode and update the phase durations.
  static Future<void> setAutoMode(
    String id,
    int greenSec,
    int redSec,
    int yellowSec,
    String uid,
  ) async {
    final allowed = await isAuthorized(uid);
    if (!allowed) {
      throw Exception('Permission denied: Only verified Traffic Police or Admin can update traffic lights.');
    }

    await _col.doc(id).update({
      'mode': 'auto',
      'status': 'auto',
      'autoGreenSeconds': greenSec,
      'autoRedSeconds': redSec,
      'autoYellowSeconds': yellowSec,
      'lastUpdatedBy': uid,
      'lastUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Admin-only ────────────────────────────────────────────────────────────

  /// Create a new intersection document with sensible defaults.
  static Future<void> addIntersection(String id, String location) =>
      _col.doc(id).set({
        'location': location,
        'status': 'red',
        'mode': 'manual',
        'autoGreenSeconds': 30,
        'autoRedSeconds': 30,
        'autoYellowSeconds': 5,
        'lastUpdatedBy': '',
        'lastUpdatedAt': FieldValue.serverTimestamp(),
        'isOnline': false,
        'lastHeartbeat': FieldValue.serverTimestamp(),
      });

  /// Delete an intersection document permanently.
  static Future<void> deleteIntersection(String id) =>
      _col.doc(id).delete();
}
