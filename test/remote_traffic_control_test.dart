import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:e_ambulance/services/firebase_traffic_service.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> statusJson({String ack = 'request_1'}) => {
  'v': 2,
  'intersection': 'junction-1',
  'lights': {'north': 'red', 'east': 'green', 'south': 'red', 'west': 'red'},
  'mode': 'manual',
  'phase': 'green',
  'target': '',
  'uptime': 12,
  'auth': false,
  'seq': 7,
  'ack': ack,
  'error': '',
};

void main() {
  final now = DateTime.utc(2026, 11, 15);
  RemoteTrafficTelemetry telemetry({
    Duration age = Duration.zero,
    Duration? sampleAge,
    bool server = true,
    bool blePriority = false,
    Map<String, dynamic>? status,
  }) => RemoteTrafficTelemetry.fromDocument({
    'deviceUid': 'device-1',
    'statusJson': jsonEncode(status ?? statusJson()),
    'reportedAt': Timestamp.fromDate(now.subtract(age)),
    'sampledAt': Timestamp.fromDate(now.subtract(sampleAge ?? age)),
    'transport': 'idle',
    'blePriority': blePriority,
  }, fromServer: server);

  test('BLE connected or connecting has priority even when stale', () {
    for (final connected in [false, true]) {
      for (final connecting in [false, true]) {
        for (final ready in [false, true]) {
          expect(
            selectTrafficRoute(
              bleConnected: connected,
              bleConnecting: connecting,
              bleReady: ready,
              remoteReady: true,
            ),
            connected && ready && !connecting
                ? TrafficControlRoute.bluetooth
                : connected || connecting
                ? TrafficControlRoute.unavailable
                : TrafficControlRoute.internet,
          );
        }
      }
    }
    expect(
      selectTrafficRoute(
        bleConnected: false,
        bleConnecting: false,
        bleReady: false,
        remoteReady: false,
      ),
      TrafficControlRoute.unavailable,
    );
  });

  test(
    'server freshness boundaries and assignment are enforced without authOk',
    () {
      expect(telemetry().status.authOk, isFalse);
      expect(telemetry().isReadyFor('junction-1', now), isTrue);
      for (final age in [
        const Duration(seconds: 6),
        const Duration(seconds: -2),
      ]) {
        expect(telemetry(age: age).isReadyFor('junction-1', now), isTrue);
      }
      for (final age in [
        const Duration(milliseconds: 6001),
        const Duration(milliseconds: -2001),
      ]) {
        expect(telemetry(age: age).isReadyFor('junction-1', now), isFalse);
      }
      expect(telemetry(server: false).isReadyFor('junction-1', now), isFalse);
      expect(
        telemetry(blePriority: true).isReadyFor('junction-1', now),
        isFalse,
      );
      expect(telemetry().isReadyFor('other', now), isFalse);
      expect(
        () => telemetry(status: {...statusJson(), 'v': 1}),
        throwsFormatException,
      );
      expect(
        () => telemetry(
          status: {
            ...statusJson(),
            'lights': {'north': 'green'},
          },
        ),
        throwsFormatException,
      );
    },
  );

  test('sample freshness is independent of fresh publication time', () {
    for (final sampleAge in [
      const Duration(seconds: 6),
      const Duration(seconds: -2),
    ]) {
      expect(
        telemetry(sampleAge: sampleAge).isReadyFor('junction-1', now),
        isTrue,
      );
    }
    for (final sampleAge in [
      const Duration(milliseconds: 6001),
      const Duration(milliseconds: -2001),
    ]) {
      expect(
        telemetry(sampleAge: sampleAge).isReadyFor('junction-1', now),
        isFalse,
      );
    }
    // A newly published old loop sample is not fresh telemetry.
    expect(
      telemetry(sampleAge: const Duration(seconds: 30))
          .isReadyFor('junction-1', now),
      isFalse,
    );
    // Both timestamps are independently bounded.
    expect(
      telemetry(
        age: const Duration(seconds: 7),
        sampleAge: Duration.zero,
      ).isReadyFor('junction-1', now),
      isFalse,
    );
    expect(
      telemetry(
        age: const Duration(seconds: -3),
        sampleAge: Duration.zero,
      ).isReadyFor('junction-1', now),
      isFalse,
    );
  });

  test('missing or malformed sampledAt is incompatible old cloud data', () {
    final data = <String, dynamic>{
      'deviceUid': 'device',
      'reportedAt': Timestamp.fromDate(now),
      'blePriority': false,
      'transport': 'firebase',
      'statusJson': jsonEncode(statusJson()),
    };
    for (final value in [null, now, now.toIso8601String(), 0]) {
      expect(
        () => RemoteTrafficTelemetry.fromDocument({
          ...data,
          'sampledAt': value,
        }, fromServer: true),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('sampledAt'),
          ),
        ),
      );
    }
    expect(
      () => RemoteTrafficTelemetry.fromDocument(data, fromServer: true),
      throwsFormatException,
    );
  });

  test('provisioned document metadata and canonical status are required', () {
    for (final field in [
      'deviceUid',
      'reportedAt',
      'sampledAt',
      'blePriority',
      'transport',
      'statusJson',
    ]) {
      final data = <String, dynamic>{
        'deviceUid': 'device',
        'reportedAt': Timestamp.fromDate(now),
        'sampledAt': Timestamp.fromDate(now),
        'blePriority': false,
        'transport': 'firebase',
        'statusJson': jsonEncode(statusJson()),
      }..remove(field);
      expect(
        () => RemoteTrafficTelemetry.fromDocument(data, fromServer: true),
        throwsFormatException,
      );
    }
  });

  Map<String, dynamic> envelope(
    Map<String, dynamic> command, {
    String id = 'request_1',
  }) => remoteCommandEnvelope(
    requestId: id,
    intersection: 'junction-1',
    uid: 'officer',
    command: command,
    now: now,
  );

  test('command envelope uses server time, fifteen-second expiry and no BLE secret', () {
    final data = envelope({
      'cmd': 'SET',
      'direction': 'west',
      'light': 'green',
      'pass': 'secret',
      'uid': 'forged',
      'v': 1,
    });
    expect(data.keys.toSet(), {'state', 'createdAt', 'expiresAt', 'payload'});
    expect(data['state'], 'pending');
    expect(data['createdAt'], isA<FieldValue>());
    expect(
      (data['expiresAt'] as Timestamp).toDate().toUtc(),
      now.add(const Duration(seconds: 15)),
    );
    expect(data['payload'], {
      'v': 2,
      'cmd': 'SET',
      'direction': 'west',
      'light': 'green',
      'request_id': 'request_1',
      'intersection': 'junction-1',
      'uid': 'officer',
      'role': 'traffic_police',
    });
    expect(
      envelope({
        'cmd': 'AUTO',
        'green_sec': 30,
        'yellow_sec': 3,
        'all_red_sec': 2,
      })['payload'],
      containsPair('green_sec', 30),
    );
    for (final cmd in ['MANUAL', 'ALL_RED', 'STATUS']) {
      expect(envelope({'cmd': cmd})['payload'], containsPair('cmd', cmd));
    }
  });

  test(
    'fifteen-second deadline allows up to five seconds of fast-phone skew',
    () {
      for (final fastSeconds in [0, 2, 5]) {
        final data = remoteCommandEnvelope(
          requestId: 'request_1',
          intersection: 'junction-1',
          uid: 'officer',
          command: {'cmd': 'ALL_RED'},
          now: now.add(Duration(seconds: fastSeconds)),
        );
        final lifetime = (data['expiresAt'] as Timestamp).toDate().difference(
          now,
        );
        expect(lifetime, lessThanOrEqualTo(const Duration(seconds: 20)));
        expect(lifetime, greaterThan(Duration.zero));
      }
    },
  );

  test(
    'write refusal explains possible excessive clock skew without retry',
    () {
      final failure = remoteCommandWriteFailure(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      ).toString();
      expect(failure, contains('authorization'));
      expect(failure, contains('automatic date/time'));
      expect(failure, contains('clock skew'));
      expect(failure, contains('No automatic retry'));
      expect(
        remoteCommandWriteFailure(StateError('network error')).toString(),
        contains('outcome unknown'),
      );
    },
  );

  test(
    'invalid command IDs, directions, timings and legacy commands fail closed',
    () {
      for (final id in ['', 'a' * 33, 'non_ascii_é', 'path/id']) {
        expect(() => envelope({'cmd': 'ALL_RED'}, id: id), throwsArgumentError);
      }
      for (final command in [
        {'cmd': 'SET', 'direction': 'all', 'light': 'green'},
        {'cmd': 'AUTO', 'green_sec': 4, 'yellow_sec': 3, 'all_red_sec': 2},
        {'cmd': 'AUTO', 'green_sec': 30, 'yellow_sec': 2, 'all_red_sec': 2},
        {'cmd': 'AUTO', 'green_sec': 30, 'yellow_sec': 3, 'all_red_sec': 1},
        {'cmd': 'GREEN'},
      ]) {
        expect(() => envelope(command), throwsArgumentError);
      }
    },
  );

  test('terminal state alone is not ACK; request, protocol and intersection must match', () {
    final data = <String, dynamic>{
      'state': 'accepted',
      'error': '',
      'ackJson': jsonEncode(statusJson()),
    };
    Object? validate(Map<String, dynamic> value) => validateRemoteAck(
      value,
      requestId: 'request_1',
      intersection: 'junction-1',
    );
    expect(validate(data), isNotNull);
    for (final invalid in [
      {...data, 'state': 'pending'},
      {...data}..remove('ackJson'),
      {...data, 'ackJson': 'not JSON'},
      {...data, 'error': 'busy'},
      {...data, 'ackJson': jsonEncode(statusJson(ack: 'other'))},
      {
        ...data,
        'ackJson': jsonEncode({...statusJson(), 'intersection': 'other'}),
      },
      {
        ...data,
        'ackJson': jsonEncode({...statusJson(), 'v': 1}),
      },
      {
        ...data,
        'ackJson': jsonEncode({...statusJson(), 'error': 'busy'}),
      },
    ]) {
      expect(validate(invalid), isNull);
    }
    expect(
      validate({
        ...data,
        'state': 'rejected',
        'error': 'busy',
        'ackJson': jsonEncode({...statusJson(), 'error': 'busy'}),
      }),
      isNotNull,
    );
  });

  test('accepted ACK reports a transition, not its completion', () {
    final ack = validateRemoteAck(
      {
        'state': 'accepted',
        'error': '',
        'ackJson': jsonEncode({
          ...statusJson(),
          'phase': 'yellow',
          'target': 'west',
          'lights': {
            'north': 'red',
            'east': 'yellow',
            'south': 'red',
            'west': 'red',
          },
        }),
      },
      requestId: 'request_1',
      intersection: 'junction-1',
    );
    expect(ack!.phase, 'yellow');
    expect(ack.lightFor('west'), 'red');
  });
}
