import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

/// Simple traffic-light control over Firebase Realtime Database.
///
/// Firebase usage stays minimal:
///  - the app never polls; it listens to `status` (one stream),
///  - the app writes only when a button is pressed,
///  - the ESP32 holds the command node open with a single SSE stream.
///
/// Data model (see the sketch header for the full contract):
///   `traffic/<intersectionId>/command` — app writes, ESP32 consumes
///   `traffic/<intersectionId>/status`  — ESP32 writes, app listens

class TrafficRtdbState {
  const TrafficRtdbState({
    required this.mode,
    required this.phase,
    required this.lights,
    required this.updated,
  });

  final String mode; // auto | manual
  final String phase; // green | yellow | all_red
  final Map<String, String> lights;
  final DateTime? updated;

  factory TrafficRtdbState.fromMap(Map<Object?, Object?> map) {
    String str(String key, String fallback) {
      final v = map[key];
      return v is String && v.isNotEmpty ? v : fallback;
    }

    final rawLights = map['lights'];
    final lights = <String, String>{};
    if (rawLights is Map) {
      rawLights.forEach((key, value) {
        if (key is String && value is String) lights[key] = value;
      });
    }
    final updated = map['updated'];
    return TrafficRtdbState(
      mode: str('mode', 'unknown'),
      phase: str('phase', 'unknown'),
      lights: lights,
      updated:
          updated is int ? DateTime.fromMillisecondsSinceEpoch(updated * 1000) : null,
    );
  }

  /// The board reports a heartbeat every ~5 s; older than 15 s = offline.
  bool get isFresh =>
      updated != null &&
      DateTime.now().difference(updated!) <= const Duration(seconds: 15);
}

class TrafficRtdbService {
  TrafficRtdbService._();

  static final TrafficRtdbService instance = TrafficRtdbService._();

  /// Must match INTERSECTION_ID in the ESP32 sketch.
  static const String intersectionId = 'khulna_royal_mor';

  DatabaseReference get _ref =>
      FirebaseDatabase.instance.ref('traffic/$intersectionId');

  /// Live status from the board.
  Stream<TrafficRtdbState> get statusStream =>
      _ref.child('status').onValue.map((event) {
        final value = event.snapshot.value;
        if (value is Map) return TrafficRtdbState.fromMap(value);
        return const TrafficRtdbState(
          mode: 'unknown',
          phase: 'unknown',
          lights: {},
          updated: null,
        );
      });

  Future<void> setGreen(String direction) => _send({
        'action': 'green',
        'direction': direction,
        'id': ServerValue.timestamp,
      });

  Future<void> allRed() => _send({'action': 'allred', 'id': ServerValue.timestamp});

  /// Starts the auto cycle with the given phase durations in seconds.
  /// Ranges enforced by the firmware: green 5-300, yellow 3-60, all-red 2-60.
  Future<void> auto({int greenSec = 30, int yellowSec = 3, int allRedSec = 2}) =>
      _send({
        'action': 'auto',
        'green_sec': greenSec,
        'yellow_sec': yellowSec,
        'all_red_sec': allRedSec,
        'id': ServerValue.timestamp,
      });

  Future<void> _send(Map<String, Object?> payload) => _ref.child('command').set(payload);
}
