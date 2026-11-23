import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
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
    required this.priority,
    required this.updated,
    this.receivedAt,
  });

  final String mode; // auto | manual
  final String phase; // green | yellow | all_red
  final Map<String, String> lights;
  final String priority; // 'ambulance' while preemption is latched, else ''
  final DateTime? updated;
  /// Local time the last status event was received — used for liveness so a
  /// board whose clock is unsynced (updated == 0/epoch) is not shown offline.
  final DateTime? receivedAt;

  /// Colour the given approach arm currently shows ('red'|'yellow'|'green').
  String lightFor(String direction) => lights[direction] ?? 'unknown';

  /// True when the board reports the ambulance preemption latch is active
  /// AND its heartbeat is recent (board online).
  DateTime get _livenessTime => receivedAt ?? updated ?? DateTime.now();

  bool get ambulanceLatched =>
      priority == 'ambulance' &&
      DateTime.now().difference(_livenessTime) <= const Duration(seconds: 15);

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
      priority: str('priority', ''),
      updated:
          updated is int ? DateTime.fromMillisecondsSinceEpoch(updated * 1000) : null,
      receivedAt: DateTime.now(),
    );
  }

  /// The board reports a heartbeat every ~5 s; older than 15 s = offline.
  bool get isFresh =>
      DateTime.now().difference(_livenessTime) <= const Duration(seconds: 15);
}

class TrafficRtdbService {
  /// Must match INTERSECTION_ID in the ESP32 sketch for the intersection.
  static const String defaultIntersectionId = 'khulna_royal_mor';

  /// Must match DB_URL in `traffic_light_firmware.ino`. Passing it explicitly
  /// means commands work even if a platform config lacks `databaseURL`
  /// (which was why the board never received commands before).
  static const String databaseUrl =
      'https://e-ambulance-system-001-default-rtdb.firebaseio.com';

  TrafficRtdbService({this.intersectionId = defaultIntersectionId});

  final String intersectionId;

  FirebaseDatabase? _database;

  FirebaseDatabase get _db => _database ??= FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: databaseUrl,
  );

  DatabaseReference get _ref => _db.ref('traffic/$intersectionId');

  /// Live status from the board.
  Stream<TrafficRtdbState> get statusStream =>
      _ref.child('status').onValue.map((event) {
        final value = event.snapshot.value;
        if (value is Map) return TrafficRtdbState.fromMap(value);
        return const TrafficRtdbState(
          mode: 'unknown',
          phase: 'unknown',
          lights: {},
          priority: '',
          updated: null,
        );
      });

  /// One-shot status read — used to confirm the board actually received and
  /// applied a command (the command write itself gives no acknowledgement).
  Future<TrafficRtdbState?> readStatus() async {
    final snapshot = await _ref.child('status').get();
    final value = snapshot.value;
    if (value is Map) return TrafficRtdbState.fromMap(value);
    return null;
  }

  /// Police preemption: force one direction to a specific colour
  /// ('green', 'yellow' or 'red'). Safety rules live in the firmware.
  Future<void> setColor(String direction, String color) => _send({
        'action': 'set',
        'direction': direction,
        'color': color,
        'id': ServerValue.timestamp,
      });

  /// Toggles the board between AUTO cycle and MANUAL (click-only) mode.
  /// Turning AUTO on gets every light to red, then starts the N-E-S-W cycle.
  Future<void> setMode(bool autoOn) =>
      _send({'action': autoOn ? 'auto' : 'manual', 'id': ServerValue.timestamp});

  /// Driver emergency preemption: forces the board into MANUAL-style control
  /// with the ambulance's approach green and everything else red, frozen
  /// until [releaseAmbulance]. Highest priority — police commands are
  /// ignored by the firmware while it is latched.
  Future<void> ambulancePreempt(String direction) => _send({
        'action': 'ambulance',
        'direction': direction,
        'id': ServerValue.timestamp,
      });

  /// Ends the ambulance preemption; the board returns to the AUTO cycle.
  Future<void> releaseAmbulance() =>
      _send({'action': 'release', 'id': ServerValue.timestamp});

  /// Starts the auto cycle with the given phase durations in seconds.
  /// Any positive value is accepted (no upper limit).
  Future<void> auto({int greenSec = 3, int yellowSec = 3, int allRedSec = 3}) =>
      _send({
        'action': 'auto',
        'green_sec': greenSec,
        'yellow_sec': yellowSec,
        'all_red_sec': allRedSec,
        'id': ServerValue.timestamp,
      });

  Future<void> _send(Map<String, Object?> payload) => _ref.child('command').set(payload);
}
