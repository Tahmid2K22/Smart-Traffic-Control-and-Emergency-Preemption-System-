import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/traffic_light_status.dart';

enum TrafficControlRoute { bluetooth, internet, unavailable }

TrafficControlRoute selectTrafficRoute({
  required bool bleConnected,
  required bool bleConnecting,
  required bool bleReady,
  required bool remoteReady,
}) {
  if (bleConnecting) return TrafficControlRoute.unavailable;
  if (bleConnected) {
    return bleReady
        ? TrafficControlRoute.bluetooth
        : TrafficControlRoute.unavailable;
  }
  return remoteReady
      ? TrafficControlRoute.internet
      : TrafficControlRoute.unavailable;
}

/// Only server-confirmed controller documents can establish internet readiness.
/// Legacy cloud documents without a loop-captured `sampledAt` are incompatible
/// and fail closed: a new server publication time cannot freshen an old sample.
class RemoteTrafficTelemetry {
  const RemoteTrafficTelemetry({
    required this.status,
    required this.reportedAt,
    required this.sampledAt,
    required this.deviceUid,
    required this.transport,
    required this.blePriority,
    required this.fromServer,
  });

  final TrafficLightStatus status;
  final DateTime reportedAt;
  final DateTime sampledAt;
  final String deviceUid;
  final String transport;
  final bool blePriority;
  final bool fromServer;

  bool isFreshFor(String intersection, DateTime now) {
    final age = now.difference(reportedAt);
    final sampleAge = now.difference(sampledAt);
    return fromServer &&
        deviceUid.isNotEmpty &&
        const ['ble', 'firebase', 'idle'].contains(transport) &&
        status.supportsFourWay &&
        status.intersectionId == intersection &&
        intersection != 'UNCONFIGURED' &&
        age >= const Duration(seconds: -2) &&
        age <= const Duration(seconds: 6) &&
        sampleAge >= const Duration(seconds: -2) &&
        sampleAge <= const Duration(seconds: 6);
  }

  bool isReadyFor(String intersection, DateTime now) =>
      !blePriority && isFreshFor(intersection, now);

  factory RemoteTrafficTelemetry.fromDocument(
    Map<String, dynamic> data, {
    required bool fromServer,
  }) {
    if (data['sampledAt'] is! Timestamp || data['reportedAt'] is! Timestamp) {
      throw const FormatException(
        'Controller telemetry requires sampledAt and reportedAt timestamps; older cloud data is incompatible.',
      );
    }
    if (data['deviceUid'] is! String ||
        data['transport'] is! String ||
        data['blePriority'] is! bool) {
      throw const FormatException('Invalid controller document.');
    }
    return RemoteTrafficTelemetry(
      status: decodeTrafficStatus(data['statusJson']),
      reportedAt: (data['reportedAt'] as Timestamp).toDate(),
      sampledAt: (data['sampledAt'] as Timestamp).toDate(),
      deviceUid: data['deviceUid'] as String,
      transport: data['transport'] as String,
      blePriority: data['blePriority'] as bool,
      fromServer: fromServer,
    );
  }
}

TrafficLightStatus decodeTrafficStatus(Object? json) {
  if (json is! String) throw const FormatException('Missing status JSON.');
  final decoded = jsonDecode(json);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Invalid status JSON.');
  }
  final status = TrafficLightStatus.fromJson(decoded);
  if (!status.supportsFourWay) {
    throw const FormatException('Four-way v2 status required.');
  }
  return status;
}

Map<String, dynamic> remoteCommandEnvelope({
  required String requestId,
  required String intersection,
  required String uid,
  required Map<String, dynamic> command,
  required DateTime now,
}) {
  if (!RegExp(r'^[A-Za-z0-9_-]{1,32}$').hasMatch(requestId) ||
      intersection.isEmpty ||
      intersection == 'UNCONFIGURED' ||
      uid.isEmpty) {
    throw ArgumentError('Invalid remote command identity.');
  }
  // Rebuild an allowlisted payload; never forward a BLE passcode or caller IDs.
  final Map<String, dynamic> validated = switch (command['cmd']) {
    'SET' => TrafficLightCommand.set(
      command['direction'] as String,
      command['light'] as String,
    ),
    'AUTO' => TrafficLightCommand.automatic(
      greenSec: command['green_sec'] as int,
      yellowSec: command['yellow_sec'] as int,
      allRedSec: command['all_red_sec'] as int,
    ),
    'ALL_RED' || 'MANUAL' || 'STATUS' => {'cmd': command['cmd']},
    _ => throw ArgumentError('Unsupported remote command.'),
  };
  return {
    'state': 'pending',
    'createdAt': FieldValue.serverTimestamp(),
    // Leave five seconds below the rules' maximum lifetime for a fast phone.
    'expiresAt': Timestamp.fromDate(now.add(const Duration(seconds: 15))),
    'payload': {
      ...validated,
      'v': 2,
      'request_id': requestId,
      'intersection': intersection,
      'uid': uid,
      'role': 'traffic_police',
    },
  };
}

/// A terminal document without a matching, valid device ACK is not a result.
TrafficLightStatus? validateRemoteAck(
  Map<String, dynamic> data, {
  required String requestId,
  required String intersection,
}) {
  if (!const ['accepted', 'rejected'].contains(data['state']) ||
      data['error'] is! String) {
    return null;
  }
  try {
    final status = decodeTrafficStatus(data['ackJson']);
    if (status.ackId != requestId || status.intersectionId != intersection) {
      return null;
    }
    if (data['state'] == 'accepted' &&
        ((data['error'] as String).isNotEmpty || status.errorCode != null)) {
      return null;
    }
    return status;
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }
}

StateError remoteCommandWriteFailure(Object error) {
  if (error is FirebaseException && error.code == 'permission-denied') {
    return StateError(
      'Firebase refused the command. Verify your authorization and enable automatic '
      'date/time on your phone; excessive clock skew can invalidate the command deadline. '
      'No automatic retry.',
    );
  }
  return StateError('Command write uncertain; outcome unknown: $error');
}

abstract interface class RemoteTrafficService {
  String? get currentUid;
  Stream<String?> get userChanges;
  RemoteTrafficTelemetry? get latestTelemetry;
  Stream<RemoteTrafficTelemetry?> get telemetryStream;
  Future<void> watch({required String intersection, required String uid});
  Future<void> stop();
  Future<TrafficLightStatus> send(
    Map<String, dynamic> command, {
    required bool Function() canDispatch,
  });
  Future<void> dispose();
}

class FirebaseTrafficService implements RemoteTrafficService {
  FirebaseTrafficService({
    required this.checkAuthorization,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    this.ackTimeout = const Duration(seconds: 25),
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance {
    _authSub = _auth.userChanges().listen((user) {
      if (user?.uid != _uid) unawaited(stop());
      _users.add(user?.uid);
    });
  }

  final Future<Map<String, dynamic>> Function() checkAuthorization;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final Duration ackTimeout;
  final _telemetry = StreamController<RemoteTrafficTelemetry?>.broadcast();
  final _users = StreamController<String?>.broadcast();
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _documentSub;
  RemoteTrafficTelemetry? _latest;
  String? _intersection;
  String? _uid;
  int _generation = 0;
  bool _sending = false;
  Completer<TrafficLightStatus>? _pending;

  @override
  String? get currentUid => _auth.currentUser?.uid;
  @override
  Stream<String?> get userChanges => _users.stream;
  @override
  RemoteTrafficTelemetry? get latestTelemetry => _latest;
  @override
  Stream<RemoteTrafficTelemetry?> get telemetryStream => _telemetry.stream;

  @override
  Future<void> stop() async {
    ++_generation;
    _uid = null;
    _intersection = null;
    _latest = null;
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(
        StateError('Session changed; command outcome unknown.'),
      );
    }
    if (!_telemetry.isClosed) _telemetry.add(null);
    final sub = _documentSub;
    _documentSub = null;
    await sub?.cancel();
  }

  @override
  Future<void> watch({
    required String intersection,
    required String uid,
  }) async {
    final generation = _generation + 1;
    await stop();
    if (generation != _generation || uid != currentUid) {
      throw StateError('User session changed.');
    }
    _uid = uid;
    _intersection = intersection;
    _documentSub = _firestore
        .collection('trafficControllers')
        .doc(intersection)
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) {
            if (generation != _generation) return;
            try {
              _latest = snapshot.exists
                  ? RemoteTrafficTelemetry.fromDocument(
                      snapshot.data()!,
                      fromServer:
                          !snapshot.metadata.isFromCache &&
                          !snapshot.metadata.hasPendingWrites,
                    )
                  : null;
            } catch (_) {
              _latest = null;
            }
            _telemetry.add(_latest);
          },
          onError: (Object error) {
            if (generation != _generation) return;
            _latest = null;
            _telemetry.add(null);
          },
        );
  }

  @override
  Future<TrafficLightStatus> send(
    Map<String, dynamic> command, {
    required bool Function() canDispatch,
  }) async {
    if (_sending) throw StateError('Wait for the pending acknowledgement.');
    _sending = true;
    final generation = _generation;
    final intersection = _intersection;
    final uid = _uid;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? ackSub;
    try {
      final authorization = await checkAuthorization();
      if (generation != _generation ||
          uid == null ||
          uid != currentUid ||
          authorization['isAuthorized'] != true ||
          authorization['uid'] != uid ||
          authorization['role'] != 'traffic_police' ||
          authorization['intersectionId'] != intersection) {
        throw StateError(
          'Current authorization or assigned intersection changed.',
        );
      }
      if (!canDispatch() ||
          intersection == null ||
          _latest?.isReadyFor(intersection, DateTime.now()) != true) {
        throw StateError(
          'Bluetooth has priority or internet telemetry is not ready. Check your '
          'connection and enable automatic date/time on your phone; excessive clock '
          'skew prevents safe freshness checks.',
        );
      }
      final ref = _firestore
          .collection('trafficControllers')
          .doc(intersection)
          .collection('commands')
          .doc();
      final envelope = remoteCommandEnvelope(
        requestId: ref.id,
        intersection: intersection,
        uid: uid,
        command: command,
        now: DateTime.now(),
      );
      final completion = Completer<TrafficLightStatus>();
      _pending = completion;
      // Start the bounded wait before dispatch so write uncertainty is bounded too.
      final result = completion.future.timeout(
        ackTimeout,
        onTimeout: () {
          throw StateError(
            'Internet acknowledgement timed out; command outcome unknown. Do not retry automatically.',
          );
        },
      );
      ackSub = ref
          .snapshots(includeMetadataChanges: true)
          .listen(
            (snapshot) {
              if (completion.isCompleted ||
                  generation != _generation ||
                  uid != currentUid ||
                  snapshot.metadata.isFromCache ||
                  snapshot.metadata.hasPendingWrites ||
                  !snapshot.exists) {
                return;
              }
              final data = snapshot.data()!;
              final ack = validateRemoteAck(
                data,
                requestId: ref.id,
                intersection: intersection,
              );
              if (ack == null) return;
              if (data['state'] == 'rejected') {
                completion.completeError(
                  StateError('Controller rejected command: ${data['error']}'),
                );
              } else {
                completion.complete(ack);
              }
            },
            onError: (Object error) {
              if (!completion.isCompleted) {
                completion.completeError(
                  StateError(
                    'ACK unavailable; command outcome unknown: $error',
                  ),
                );
              }
            },
          );
      // Recheck actual BLE attachment at dispatch, not just before authorization.
      // Firmware arbitrates a BLE arrival after this final synchronous check.
      if (!canDispatch()) {
        if (!completion.isCompleted) {
          completion.completeError(
            StateError('Bluetooth has priority; command not sent.'),
          );
        }
      } else {
        // One write only. A network error cannot prove that the device did not act.
        unawaited(
          ref.set(envelope).catchError((Object error) {
            if (!completion.isCompleted) {
              completion.completeError(remoteCommandWriteFailure(error));
            }
          }),
        );
      }
      return await result;
    } finally {
      _pending = null;
      await ackSub?.cancel();
      _sending = false;
    }
  }

  @override
  Future<void> dispose() async {
    await _authSub?.cancel();
    await stop();
    await _telemetry.close();
    await _users.close();
  }
}
