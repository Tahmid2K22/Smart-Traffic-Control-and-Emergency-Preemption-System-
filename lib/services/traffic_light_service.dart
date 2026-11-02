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

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Switch to manual mode and set the light colour.
  /// [status] must be one of: `"red"`, `"yellow"`, `"green"`.
  static Future<void> setLightStatus(
    String id,
    String status,
    String uid,
  ) =>
      _col.doc(id).update({
        'status': status,
        'mode': 'manual',
        'lastUpdatedBy': uid,
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      });

  /// Switch to auto mode and update the phase durations.
  static Future<void> setAutoMode(
    String id,
    int greenSec,
    int redSec,
    int yellowSec,
    String uid,
  ) =>
      _col.doc(id).update({
        'mode': 'auto',
        'status': 'auto',
        'autoGreenSeconds': greenSec,
        'autoRedSeconds': redSec,
        'autoYellowSeconds': yellowSec,
        'lastUpdatedBy': uid,
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      });

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
