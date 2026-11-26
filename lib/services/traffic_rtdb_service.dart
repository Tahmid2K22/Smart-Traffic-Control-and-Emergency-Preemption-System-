import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

/// Traffic-light control over RTDB. App listens to `status`, writes on button press; ESP32 consumes `command`.
/// `traffic/<id>/command` (app→board), `traffic/<id>/status` (board→app).

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
  /// Last status received locally (liveness; unsynced board clocks).
  final DateTime? receivedAt;

  /// Colour of an approach arm ('red'|'yellow'|'green').
  String lightFor(String direction) => lights[direction] ?? 'unknown';

  /// Last time used for liveness (receivedAt ?? updated).
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

  /// Heartbeat every ~5s; older than 15s = offline.
  bool get isFresh =>
      DateTime.now().difference(_livenessTime) <= const Duration(seconds: 15);
}

class TrafficRtdbService {
  /// Must match INTERSECTION_ID in the ESP32 sketch.
  static const String defaultIntersectionId = 'khulna_royal_mor';

  /// Must match DB_URL in firmware; passed explicitly so commands work without platform databaseURL.
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

  /// Live status stream from the board.
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

  /// One-shot status read (command writes give no ack).
  Future<TrafficRtdbState?> readStatus() async {
    final snapshot = await _ref.child('status').get();
    final value = snapshot.value;
    if (value is Map) return TrafficRtdbState.fromMap(value);
    return null;
  }

  /// Police preemption: force a direction to a colour ('green'/'yellow'/'red'); safety in firmware.
  Future<void> setColor(String direction, String color) => _send({
        'action': 'set',
        'direction': direction,
        'color': color,
        'id': ServerValue.timestamp,
      });

  /// Toggle AUTO/MANUAL mode (AUTO resets to red then cycles N-E-S-W).
  Future<void> setMode(bool autoOn) =>
      _send({'action': autoOn ? 'auto' : 'manual', 'id': ServerValue.timestamp});

  /// Emergency preemption: approach green, rest red, frozen until release. Highest priority.
  Future<void> ambulancePreempt(String direction) => _send({
        'action': 'ambulance',
        'direction': direction,
        'id': ServerValue.timestamp,
      });

  /// End preemption; board returns to AUTO.
  Future<void> releaseAmbulance() =>
      _send({'action': 'release', 'id': ServerValue.timestamp});

  /// Start auto cycle with phase durations (any positive value).
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
