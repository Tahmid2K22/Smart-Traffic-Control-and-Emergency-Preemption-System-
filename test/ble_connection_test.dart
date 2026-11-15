import 'dart:async';

import 'package:e_ambulance/services/ble_traffic_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';

const _authorization = {
  'isAuthorized': true,
  'uid': 'private-officer-uid',
  'role': 'traffic_police',
  'intersectionId': 'assigned-junction',
};

class _Device extends Fake implements BluetoothDevice {
  bool connected = false;
  int negotiatedMtu = 517;
  int disconnects = 0;
  int discoveries = 0;
  Object? discoveryError;
  Object? disconnectError;
  final connectMtus = <int?>[];

  @override
  bool get isConnected => connected;

  @override
  int get mtuNow => negotiatedMtu;

  @override
  Stream<BluetoothConnectionState> get connectionState =>
      Stream.value(BluetoothConnectionState.connected);

  @override
  Future<void> connect({
    required License license,
    Duration timeout = const Duration(seconds: 35),
    int? mtu = 512,
    bool autoConnect = false,
  }) async {
    connectMtus.add(mtu);
    connected = true;
  }

  @override
  Future<void> disconnect({
    int timeout = 35,
    bool queue = true,
    int androidDelay = 2000,
  }) async {
    disconnects++;
    connected = false;
    if (disconnectError != null) throw disconnectError!;
  }

  @override
  Future<List<BluetoothService>> discoverServices({
    bool subscribeToServicesChanged = true,
    int timeout = 15,
  }) async {
    discoveries++;
    if (discoveryError != null) throw discoveryError!;
    return [];
  }
}

Matcher _failureDuring(String stage, String detail) => isA<StateError>()
    .having(
      (error) => error.message,
      'stage',
      contains('Bluetooth connection failed during $stage:'),
    )
    .having((error) => error.message, 'detail', contains(detail));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'concurrent connect is rejected before authorization or cleanup',
    () async {
      final authorization = Completer<Map<String, dynamic>>();
      var checks = 0;
      final service = BleTrafficService.forTesting(
        checkAuthorization: () {
          checks++;
          return authorization.future;
        },
      );
      addTearDown(service.dispose);
      final firstDevice = _Device();
      final secondDevice = _Device();
      final connectionEvents = <bool>[];
      final subscription = service.connectionStream.listen(
        connectionEvents.add,
      );
      addTearDown(subscription.cancel);

      final first = service.connect(firstDevice);
      expect(service.isConnecting, isTrue);
      await expectLater(
        service.connect(secondDevice),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('connection attempt is already in progress'),
          ),
        ),
      );
      expect(checks, 1);
      expect(service.isConnecting, isTrue);
      expect(firstDevice.connectMtus, isEmpty);
      expect(secondDevice.connectMtus, isEmpty);
      expect(firstDevice.disconnects, 0);
      expect(secondDevice.disconnects, 0);
      expect(connectionEvents, isEmpty);

      final rejected = expectLater(
        first,
        throwsA(_failureDuring('authorization', 'Permission revoked')),
      );
      authorization.complete({
        'isAuthorized': false,
        'reason': 'Permission revoked',
      });
      await rejected;
      expect(service.isConnecting, isFalse);

      await expectLater(
        service.connect(secondDevice),
        throwsA(_failureDuring('authorization', 'Permission revoked')),
      );
      expect(checks, 2);
      expect(service.isConnecting, isFalse);
    },
  );

  test(
    'first-use auto-connect stays disabled and retry rechecks authorization',
    () async {
      var checks = 0;
      var authorized = true;
      final service = BleTrafficService.forTesting(
        checkAuthorization: () async {
          checks++;
          return authorized
              ? _authorization
              : {'isAuthorized': false, 'reason': 'Permission revoked'};
        },
      );
      addTearDown(service.dispose);
      final errors = <String>[];

      await service.startAutoConnect(onError: errors.add);
      expect(service.autoConnectEnabled, isFalse);
      expect(errors.single, contains('previously verified device'));
      await service.startAutoConnect(onError: errors.add);
      expect(checks, 2);
      expect(errors, hasLength(2));
      expect(service.autoConnectEnabled, isFalse);

      authorized = false;
      await service.startAutoConnect(onError: errors.add);
      expect(checks, 3);
      expect(errors.last, 'Permission revoked');
      expect(service.autoConnectEnabled, isFalse);
    },
  );

  for (final mtu in [514, 515, 517]) {
    test(
      'connect disables default MTU exchange and keeps 515 gate at $mtu',
      () async {
        final service = BleTrafficService.forTesting(
          checkAuthorization: () async => _authorization,
        );
        addTearDown(service.dispose);
        final device = _Device()..negotiatedMtu = mtu;

        await expectLater(
          service.connect(device),
          throwsA(
            mtu < 515
                ? _failureDuring('MTU negotiation', 'received $mtu')
                : _failureDuring(
                    'service discovery',
                    'characteristics were not found',
                  ),
          ),
        );
        expect(device.connectMtus, [null]);
        expect(device.discoveries, mtu < 515 ? 0 : 1);
        expect(device.disconnects, 1);
        expect(service.isConnecting, isFalse);
        expect(service.isConnected, isFalse);
        expect(service.isReady, isFalse);
      },
    );
  }

  test('connection error retains failing stage and original error without credentials', () async {
    final logs = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() => debugPrint = previousDebugPrint);
    final service = BleTrafficService.forTesting(
      checkAuthorization: () async => _authorization,
    );
    addTearDown(service.dispose);
    final device = _Device()
      ..discoveryError = StateError('discovery sentinel')
      ..disconnectError = StateError('cleanup sentinel');

    await expectLater(
      service.connect(device),
      throwsA(_failureDuring('service discovery', 'discovery sentinel')),
    );
    expect(logs.join('\n'), contains('MTU result: 517'));
    expect(logs.join('\n'), contains('cleanup sentinel'));
    expect(logs.join('\n'), isNot(contains('private-officer-uid')));
    expect(logs.join('\n'), isNot(contains(kPolicePasscode)));
    expect(device.disconnects, 1);
    expect(service.isConnecting, isFalse);
    expect(service.isReady, isFalse);
  });
}
