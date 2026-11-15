import 'dart:async';

import 'package:e_ambulance/pages/traffic_light_control_page.dart';
import 'package:e_ambulance/services/ble_traffic_service.dart';
import 'package:e_ambulance/services/firebase_traffic_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';

class _Status extends Fake implements TrafficLightStatus {
  _Status({
    this.lights = const {
      'north': 'red',
      'east': 'green',
      'south': 'red',
      'west': 'red',
    },
    this.mode = 'manual',
    this.phase = 'green',
    this.targetDirection,
    this.version = 2,
    this.intersectionId = 'assigned-junction',
    this.authOk = true,
    this.supportsFourWay = true,
    this.errorCode,
    this.uptime = 42,
    this.sequence = 7,
  });

  @override
  final Map<String, String> lights;
  @override
  final String mode;
  @override
  final String phase;
  @override
  final String? targetDirection;
  @override
  final int version;
  @override
  final String intersectionId;
  @override
  final bool authOk;
  @override
  final bool supportsFourWay;
  @override
  final String? errorCode;
  @override
  final int uptime;
  @override
  final int sequence;
  @override
  String? get ackId => null;
  @override
  String lightFor(String direction) => lights[direction] ?? 'unknown';
}

class _Service extends Fake implements BleTrafficService {
  final statuses = StreamController<TrafficLightStatus>.broadcast(sync: true);
  final connections = StreamController<bool>.broadcast(sync: true);
  final scans = StreamController<List<TrafficLightDevice>>.broadcast(
    sync: true,
  );
  bool authorized = true;
  bool connected = true;
  bool ready = true;
  bool autoEnabled = false;
  bool autoConnecting = false;
  bool explicitConnecting = false;
  @override
  bool get autoConnectEnabled => autoEnabled;
  @override
  bool get isConnecting => autoConnecting || explicitConnecting;
  bool permission = true;
  int permissionRequests = 0;
  int disconnects = 0;
  int statusRequests = 0;
  int scanRequests = 0;
  int scanStops = 0;
  int connectRequests = 0;
  Completer<void>? pendingConnection;
  final commands = <String>[];
  Completer<void>? pending;
  TrafficLightStatus? cached = _Status();

  @override
  TrafficLightStatus? get latestStatus => cached;
  @override
  Stream<TrafficLightStatus> get statusStream => statuses.stream;
  @override
  Stream<bool> get connectionStream => connections.stream;
  @override
  bool get isConnected => connected;
  @override
  bool get isAuthenticated => connected;
  @override
  bool get isReady => connected && ready;
  @override
  Future<Map<String, dynamic>> checkUserAuthorization() async => {
    'isAuthorized': authorized,
    'uid': 'officer-1',
    'role': 'traffic_police',
    'name': 'Test officer',
    'policeId': '123',
    'intersection': 'Assigned junction',
    'intersectionId': 'assigned-junction',
  };
  @override
  Future<void> requestStatus() async {
    statusRequests++;
  }

  @override
  Future<bool> requestPermissions() async {
    permissionRequests++;
    return permission;
  }

  @override
  Stream<List<TrafficLightDevice>> scan({
    Duration timeout = const Duration(seconds: 10),
  }) {
    scanRequests++;
    return scans.stream;
  }

  @override
  Future<void> stopScan() async {
    scanStops++;
  }

  @override
  Future<void> connect(BluetoothDevice device) async {
    connectRequests++;
    explicitConnecting = true;
    connected = true;
    ready = false;
    cached = null;
    pendingConnection = Completer<void>();
    try {
      await pendingConnection!.future;
    } finally {
      explicitConnecting = false;
    }
  }

  Future<void> _command(String name) {
    commands.add(name);
    pending = Completer<void>();
    return pending!.future;
  }

  @override
  Future<void> setDirectionLight({
    required String direction,
    required String light,
  }) => _command('$direction:$light');
  @override
  Future<void> setAllRed() => _command('all-red');
  @override
  Future<void> setManualMode() => _command('manual');
  @override
  Future<void> setAutoMode({
    required int greenSec,
    required int yellowSec,
    required int allRedSec,
  }) => _command('auto:$greenSec:$yellowSec:$allRedSec');
  @override
  Future<void> disconnect() async {
    disconnects++;
    connected = false;
    cached = null;
    connections.add(false);
  }

  void emit(TrafficLightStatus status) {
    cached = status;
    statuses.add(status);
  }

  Future<void> close() async {
    await statuses.close();
    await connections.close();
    await scans.close();
  }
}

Finder _key(String key) => find.byKey(ValueKey(key));

bool _enabled(WidgetTester tester, String key) =>
    tester.widget<ButtonStyleButton>(_key(key)).onPressed != null;

Future<void> _largeSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _panel(
  WidgetTester tester, {
  TrafficLightStatus? status,
  bool enabled = true,
  bool sending = false,
  void Function(String, String)? onSetDirection,
  VoidCallback? onAllRed,
}) async {
  await _largeSurface(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: FourWaySignalPanel(
            status: status,
            enabled: enabled,
            sending: sending,
            onSetDirection: onSetDirection ?? (_, _) {},
            onAllRed: onAllRed ?? () {},
          ),
        ),
      ),
    ),
  );
}

class _Remote extends Fake implements RemoteTrafficService {
  final telemetry = StreamController<RemoteTrafficTelemetry?>.broadcast(
    sync: true,
  );
  final users = StreamController<String?>.broadcast(sync: true);
  final commands = <Map<String, dynamic>>[];
  Completer<TrafficLightStatus>? pending;
  Completer<void>? authorizationGate;
  @override
  String? currentUid = 'officer-1';
  @override
  RemoteTrafficTelemetry? latestTelemetry;
  @override
  Stream<String?> get userChanges => users.stream;
  @override
  Stream<RemoteTrafficTelemetry?> get telemetryStream => telemetry.stream;
  @override
  Future<void> watch({
    required String intersection,
    required String uid,
  }) async {
    emit();
  }

  void emit({
    bool blePriority = false,
    bool fromServer = true,
    DateTime? at,
    DateTime? sampledAt,
    TrafficLightStatus? status,
  }) {
    latestTelemetry = RemoteTrafficTelemetry(
      status: status ?? _Status(authOk: false),
      reportedAt: at ?? DateTime.now(),
      sampledAt: sampledAt ?? at ?? DateTime.now(),
      deviceUid: 'device-1',
      transport: 'firebase',
      blePriority: blePriority,
      fromServer: fromServer,
    );
    telemetry.add(latestTelemetry);
  }

  @override
  Future<void> stop() async {}
  @override
  Future<TrafficLightStatus> send(
    Map<String, dynamic> command, {
    required bool Function() canDispatch,
  }) async {
    await authorizationGate?.future;
    if (!canDispatch()) throw StateError('BLE priority');
    commands.add(command);
    pending = Completer<TrafficLightStatus>();
    return pending!.future;
  }

  @override
  Future<void> dispose() async {
    await telemetry.close();
    await users.close();
  }
}

Future<_Service> _page(
  WidgetTester tester, [
  _Service? service,
  _Remote? remote,
]) async {
  await _largeSurface(tester);
  final ble = service ?? _Service();
  addTearDown(ble.close);
  await tester.pumpWidget(
    MaterialApp(
      home: TrafficLightControlPage(service: ble, remoteService: remote),
    ),
  );
  await tester.pumpAndSettle();
  return ble;
}

void main() {
  for (final automatic in [false, true]) {
    testWidgets(
      '${automatic ? 'auto' : 'explicit'} handshake suppresses refresh until complete',
      (tester) async {
        final ble = _Service()..ready = false;
        if (automatic) {
          ble.autoConnecting = true;
        } else {
          ble.explicitConnecting = true;
        }
        await _page(tester, ble);
        expect(ble.statusRequests, 0);
        await tester.pump(const Duration(seconds: 6));
        expect(ble.statusRequests, 0);
        final refresh = find.byWidgetPredicate(
          (widget) =>
              widget is IconButton && widget.tooltip == 'Refresh device status',
        );
        expect(tester.widget<IconButton>(refresh).onPressed, isNull);
        ble.autoConnecting = false;
        ble.explicitConnecting = false;
        await tester.pump(const Duration(seconds: 1));
        expect(tester.widget<IconButton>(refresh).onPressed, isNotNull);
        await tester.tap(refresh);
        await tester.pump();
        expect(ble.statusRequests, 1);
        await tester.pump(const Duration(seconds: 5));
        expect(ble.statusRequests, greaterThan(1));
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      '${automatic ? 'auto' : 'explicit'} attachment gates manual scan and selection',
      (tester) async {
        final ble = await _page(tester, _Service()..connected = false);
        await tester.tap(find.text('Scan for controllers'));
        await tester.pump();
        ble.scans.add([
          TrafficLightDevice(
            device: BluetoothDevice.fromId('test-controller'),
            name: 'Test controller',
            rssi: -40,
          ),
        ]);
        await tester.pump();
        final scan = find.widgetWithText(FilledButton, 'Stop scan');
        final controller = find.widgetWithText(ListTile, 'Test controller');
        if (automatic) {
          ble.autoConnecting = true;
        } else {
          ble.explicitConnecting = true;
        }
        await tester.pump(const Duration(seconds: 1));
        expect(tester.widget<FilledButton>(scan).onPressed, isNull);
        expect(tester.widget<ListTile>(controller).onTap, isNull);
        expect(ble.scanRequests, 1);
        expect(ble.connectRequests, 0);
        ble.autoConnecting = false;
        ble.explicitConnecting = false;
        await tester.pump(const Duration(seconds: 1));
        expect(tester.widget<FilledButton>(scan).onPressed, isNotNull);
        expect(tester.widget<ListTile>(controller).onTap, isNotNull);
        await tester.tap(controller);
        // Let the broadcast subscription's cancellation complete outside fake time.
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
        expect(ble.scanStops, 1);
        expect(ble.connectRequests, 1);
        await tester.pump(const Duration(seconds: 6));
        expect(ble.statusRequests, 0);
        final refresh = find.byWidgetPredicate(
          (widget) =>
              widget is IconButton && widget.tooltip == 'Refresh device status',
        );
        expect(tester.widget<IconButton>(refresh).onPressed, isNull);
        ble.ready = true;
        ble.emit(_Status());
        ble.pendingConnection!.complete();
        await tester.pump();
        expect(tester.widget<IconButton>(refresh).onPressed, isNotNull);
        await tester.tap(refresh);
        await tester.pump();
        expect(ble.statusRequests, 1);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'internet route accepts auth false telemetry without optimistic lights',
    (tester) async {
      final remote = _Remote();
      addTearDown(remote.dispose);
      final ble = await _page(tester, _Service()..connected = false, remote);
      expect(find.textContaining('Route: Internet'), findsOneWidget);
      expect(_enabled(tester, 'set-north-green'), isTrue);
      await tester.tap(_key('set-north-green'));
      await tester.pump();
      expect(remote.commands.single['cmd'], 'SET');
      expect(ble.commands, isEmpty);
      expect(_enabled(tester, 'all-red'), isFalse);
      expect(tester.widget<Text>(_key('reported-north')).data, 'Reported: RED');
      remote.pending!.complete(
        _Status(phase: 'yellow', targetDirection: 'north'),
      );
      await tester.pump();
      expect(_enabled(tester, 'set-north-green'), isFalse);
      expect(_enabled(tester, 'all-red'), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'connected stale and background connecting BLE never use internet',
    (tester) async {
      final remote = _Remote();
      addTearDown(remote.dispose);
      final ble = await _page(tester, _Service()..ready = false, remote);
      expect(find.textContaining('Route: Bluetooth priority'), findsOneWidget);
      expect(_enabled(tester, 'all-red'), isFalse);
      ble.connected = false;
      ble.autoEnabled = true;
      ble.autoConnecting = true;
      await tester.pump(const Duration(seconds: 1));
      expect(_enabled(tester, 'all-red'), isFalse);
      expect(find.textContaining('Route: Bluetooth priority'), findsOneWidget);
      expect(remote.commands, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'enabled idle auto scan permits internet until actual attachment',
    (tester) async {
      final remote = _Remote();
      addTearDown(remote.dispose);
      final ble = await _page(
        tester,
        _Service()
          ..connected = false
          ..autoEnabled = true,
        remote,
      );
      expect(ble.autoConnectEnabled, isTrue);
      expect(ble.isConnecting, isFalse);
      expect(find.textContaining('Route: Internet'), findsOneWidget);
      expect(_enabled(tester, 'all-red'), isTrue);
      await tester.tap(_key('all-red'));
      await tester.pump();
      expect(remote.commands, hasLength(1));
      remote.pending!.complete(_Status());
      await tester.pump();

      ble.autoConnecting = true;
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Route: Bluetooth priority'), findsOneWidget);
      expect(_enabled(tester, 'all-red'), isFalse);
      ble.autoConnecting = false;
      await tester.pump(const Duration(seconds: 1));
      expect(ble.autoConnectEnabled, isTrue);
      expect(find.textContaining('Route: Internet'), findsOneWidget);
      expect(_enabled(tester, 'all-red'), isTrue);
      expect(ble.commands, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final automatic in [false, true]) {
    testWidgets(
      '${automatic ? 'auto' : 'explicit'} attachment during remote authorization blocks dispatch',
      (tester) async {
        final remote = _Remote()..authorizationGate = Completer<void>();
        addTearDown(remote.dispose);
        final ble = await _page(
          tester,
          _Service()
            ..connected = false
            ..autoEnabled = automatic,
          remote,
        );
        await tester.tap(_key('all-red'));
        await tester.pump();
        expect(remote.commands, isEmpty);
        if (automatic) {
          ble.autoConnecting = true;
        } else {
          ble.explicitConnecting = true;
        }
        // No rebuild: the pre-write callback must read current BLE state.
        remote.authorizationGate!.complete();
        await tester.pump();
        expect(remote.commands, isEmpty);
        expect(ble.commands, isEmpty);
        expect(_enabled(tester, 'all-red'), isFalse);
        expect(
          find.textContaining('Route: Bluetooth priority'),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'reboot telemetry replaces a higher-sequence preboot ACK immediately',
    (tester) async {
      final remote = _Remote();
      addTearDown(remote.dispose);
      await _page(tester, _Service()..connected = false, remote);
      await tester.tap(_key('all-red'));
      await tester.pump();
      remote.pending!.complete(
        _Status(
          uptime: 100,
          sequence: 100,
          phase: 'yellow',
          targetDirection: 'north',
          lights: {
            'north': 'red',
            'east': 'yellow',
            'south': 'red',
            'west': 'red',
          },
        ),
      );
      await tester.pump();
      expect(
        tester.widget<Text>(_key('reported-east')).data,
        'Reported: YELLOW',
      );
      expect(_enabled(tester, 'set-north-green'), isFalse);
      remote.emit(
        status: _Status(
          uptime: 1,
          sequence: 1,
          phase: 'all_red',
          lights: {
            for (final direction in kTrafficDirections) direction: 'red',
          },
        ),
      );
      await tester.pump();
      expect(tester.widget<Text>(_key('reported-east')).data, 'Reported: RED');
      expect(find.textContaining('Transfer pending'), findsNothing);
      expect(_enabled(tester, 'set-north-green'), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'older telemetry than ACK stays buffered until an actual telemetry reboot',
    (tester) async {
      final remote = _Remote();
      addTearDown(remote.dispose);
      await _page(tester, _Service()..connected = false, remote);
      remote.emit(status: _Status(uptime: 9, sequence: 3));
      await tester.pump();
      await tester.tap(_key('all-red'));
      await tester.pump();
      remote.pending!.complete(
        _Status(
          uptime: 11,
          sequence: 5,
          phase: 'yellow',
          targetDirection: 'north',
          lights: {
            'north': 'red',
            'east': 'yellow',
            'south': 'red',
            'west': 'red',
          },
        ),
      );
      await tester.pump();
      remote.emit(status: _Status(uptime: 10, sequence: 4));
      await tester.pump();
      expect(
        tester.widget<Text>(_key('reported-east')).data,
        'Reported: YELLOW',
      );
      expect(_enabled(tester, 'set-north-green'), isFalse);
      remote.emit(
        status: _Status(
          uptime: 0,
          sequence: 1,
          phase: 'all_red',
          lights: {
            for (final direction in kTrafficDirections) direction: 'red',
          },
        ),
      );
      await tester.pump();
      expect(tester.widget<Text>(_key('reported-east')).data, 'Reported: RED');
      expect(_enabled(tester, 'set-north-green'), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a delayed preboot ACK cannot overwrite telemetry after reboot', (
    tester,
  ) async {
    final remote = _Remote();
    addTearDown(remote.dispose);
    await _page(tester, _Service()..connected = false, remote);
    await tester.tap(_key('all-red'));
    await tester.pump();
    remote.emit(
      status: _Status(
        uptime: 1,
        sequence: 1,
        phase: 'all_red',
        lights: {for (final direction in kTrafficDirections) direction: 'red'},
      ),
    );
    remote.pending!.complete(_Status(uptime: 100, sequence: 100));
    await tester.pump();
    expect(tester.widget<Text>(_key('reported-east')).data, 'Reported: RED');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'ACK bridges same-boot telemetry lag but expires after six seconds',
    (tester) async {
      final remote = _Remote();
      addTearDown(remote.dispose);
      await _page(tester, _Service()..connected = false, remote);
      await tester.tap(_key('all-red'));
      await tester.pump();
      remote.pending!.complete(
        _Status(
          sequence: 100,
          lights: {
            'north': 'green',
            'east': 'red',
            'south': 'red',
            'west': 'red',
          },
        ),
      );
      await tester.pump();
      remote.emit(status: _Status(uptime: 43, sequence: 99));
      await tester.pump();
      expect(
        tester.widget<Text>(_key('reported-north')).data,
        'Reported: GREEN',
      );
      await tester.pump(const Duration(seconds: 6));
      expect(tester.widget<Text>(_key('reported-north')).data, 'Reported: RED');
      expect(
        tester.widget<Text>(_key('reported-east')).data,
        'Reported: GREEN',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('internet expires and rejects cached or BLE-priority telemetry', (
    tester,
  ) async {
    final remote = _Remote();
    addTearDown(remote.dispose);
    await _page(tester, _Service()..connected = false, remote);
    for (final emit in <void Function()>[
      () => remote.emit(blePriority: true),
      () => remote.emit(fromServer: false),
      () => remote.emit(
        sampledAt: DateTime.now().subtract(const Duration(seconds: 7)),
      ),
      () => remote.emit(
        sampledAt: DateTime.now().add(const Duration(seconds: 3)),
      ),
      () =>
          remote.emit(at: DateTime.now().subtract(const Duration(seconds: 7))),
    ]) {
      emit();
      await tester.pump();
      expect(_enabled(tester, 'all-red'), isFalse);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('uncertain internet command never retries or falls back to BLE', (
    tester,
  ) async {
    final remote = _Remote();
    addTearDown(remote.dispose);
    final ble = await _page(tester, _Service()..connected = false, remote);
    await tester.tap(_key('all-red'));
    await tester.pump();
    ble.connected = true;
    ble.connections.add(true);
    remote.pending!.completeError(StateError('Outcome unknown'));
    await tester.pump();
    expect(remote.commands, hasLength(1));
    expect(ble.commands, isEmpty);
    expect(
      find.textContaining('No automatic retry or transport fallback'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('logout removes remote controls and reported state', (
    tester,
  ) async {
    final remote = _Remote();
    addTearDown(remote.dispose);
    await _page(tester, _Service()..connected = false, remote);
    remote.currentUid = null;
    remote.users.add(null);
    await tester.pumpAndSettle();
    expect(_key('all-red'), findsNothing);
    expect(
      find.text('Verified Traffic Police access required'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('four labeled heads use device map; missing is unknown', (
    tester,
  ) async {
    await _panel(
      tester,
      status: _Status(
        lights: {'north': 'red', 'east': 'green', 'west': 'yellow'},
      ),
    );
    for (final direction in kTrafficDirections) {
      expect(_key('head-$direction'), findsOneWidget);
      for (final light in ['red', 'yellow', 'green']) {
        expect(_key('set-$direction-$light'), findsOneWidget);
      }
    }
    expect(tester.widget<Text>(_key('reported-north')).data, 'Reported: RED');
    expect(tester.widget<Text>(_key('reported-east')).data, 'Reported: GREEN');
    expect(tester.widget<Text>(_key('reported-west')).data, 'Reported: YELLOW');
    expect(
      tester.widget<Text>(_key('reported-south')).data,
      'Reported: UNKNOWN',
    );
  });

  testWidgets('direction callback never optimistically changes heads', (
    tester,
  ) async {
    final requests = <String>[];
    await _panel(
      tester,
      status: _Status(),
      onSetDirection: (direction, light) {
        requests.add('$direction:$light');
      },
    );
    await tester.tap(_key('set-north-green'));
    await tester.pump();
    expect(requests, ['north:green']);
    expect(tester.widget<Text>(_key('reported-north')).data, 'Reported: RED');
    expect(tester.widget<Text>(_key('reported-east')).data, 'Reported: GREEN');
  });

  for (final phase in ['yellow', 'all_red']) {
    testWidgets('$phase transfer locks directions but keeps All Red', (
      tester,
    ) async {
      var allRed = false;
      await _panel(
        tester,
        status: _Status(phase: phase, targetDirection: 'west'),
        onAllRed: () => allRed = true,
      );
      expect(find.textContaining('Transfer pending → WEST'), findsOneWidget);
      for (final direction in kTrafficDirections) {
        for (final light in ['red', 'yellow', 'green']) {
          expect(_enabled(tester, 'set-$direction-$light'), isFalse);
        }
      }
      expect(_enabled(tester, 'all-red'), isTrue);
      await tester.tap(_key('all-red'));
      expect(allRed, isTrue);
    });
  }

  testWidgets('yellow-to-idle transition needs no target and stays locked', (
    tester,
  ) async {
    await _panel(
      tester,
      status: _Status(
        phase: 'yellow',
        lights: {
          'north': 'red',
          'east': 'yellow',
          'south': 'red',
          'west': 'red',
        },
      ),
    );
    expect(find.textContaining('Transfer pending → ALL RED'), findsOneWidget);
    expect(_enabled(tester, 'set-north-green'), isFalse);
    expect(_enabled(tester, 'all-red'), isTrue);
  });

  testWidgets('yellow is only available for the active green direction', (
    tester,
  ) async {
    await _panel(tester, status: _Status());
    expect(_enabled(tester, 'set-east-yellow'), isTrue);
    expect(_enabled(tester, 'set-north-yellow'), isFalse);
  });

  testWidgets('pending acknowledgement disables even All Red', (tester) async {
    await _panel(tester, status: _Status(), sending: true);
    expect(_enabled(tester, 'all-red'), isFalse);
    expect(_enabled(tester, 'set-north-green'), isFalse);
    expect(
      find.textContaining('Waiting for controller acknowledgement'),
      findsOneWidget,
    );
  });

  testWidgets('lowercase firmware errors are explained', (tester) async {
    await _panel(tester, status: _Status(errorCode: 'busy'));
    expect(
      find.textContaining('busy — controller is completing a transfer'),
      findsOneWidget,
    );
  });

  testWidgets(
    'cached status is used and shared connection survives page exit',
    (tester) async {
      final ble = await _page(tester);
      expect(
        tester.widget<Text>(_key('reported-east')).data,
        'Reported: GREEN',
      );
      expect(_enabled(tester, 'set-north-green'), isTrue);
      expect(ble.statusRequests, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
      expect(ble.disconnects, 0);
    },
  );

  testWidgets(
    'freshness tick disables stale controls and periodically refreshes',
    (tester) async {
      final ble = await _page(tester);
      ble.ready = false;
      await tester.pump(const Duration(seconds: 1));
      expect(_enabled(tester, 'all-red'), isFalse);
      expect(_enabled(tester, 'set-north-green'), isFalse);
      expect(find.textContaining('Status stale'), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(ble.statusRequests, greaterThanOrEqualTo(2));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('disconnect clears cached light readouts', (tester) async {
    final ble = await _page(tester);
    await ble.disconnect();
    await tester.pump();
    for (final direction in kTrafficDirections) {
      expect(
        tester.widget<Text>(_key('reported-$direction')).data,
        'Reported: UNKNOWN',
      );
    }
    expect(_enabled(tester, 'all-red'), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unauthenticated controller leaves controls disabled', (
    tester,
  ) async {
    await _page(
      tester,
      _Service()
        ..cached = _Status(authOk: false)
        ..ready = false,
    );
    expect(_enabled(tester, 'set-north-green'), isFalse);
    expect(_enabled(tester, 'all-red'), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('legacy firmware is explained and disabled', (tester) async {
    await _page(
      tester,
      _Service()
        ..cached = _Status(version: 1, supportsFourWay: false)
        ..ready = false,
    );
    expect(find.textContaining('Legacy firmware'), findsOneWidget);
    expect(_enabled(tester, 'set-north-green'), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('intersection mismatch is explained and disabled', (
    tester,
  ) async {
    await _page(
      tester,
      _Service()
        ..cached = _Status(intersectionId: 'another-junction')
        ..ready = false,
    );
    expect(find.textContaining('Intersection mismatch'), findsOneWidget);
    expect(_enabled(tester, 'all-red'), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('waiting for first status never invents red heads', (
    tester,
  ) async {
    await _page(
      tester,
      _Service()
        ..cached = null
        ..ready = false,
    );
    expect(find.textContaining('waiting for device status'), findsOneWidget);
    expect(
      tester.widget<Text>(_key('reported-north')).data,
      'Reported: UNKNOWN',
    );
    expect(_enabled(tester, 'all-red'), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unauthorized users cannot scan or control', (tester) async {
    final ble = await _page(tester, _Service()..authorized = false);
    expect(
      find.text('Verified Traffic Police access required'),
      findsOneWidget,
    );
    expect(find.text('Scan for controllers'), findsNothing);
    expect(_key('all-red'), findsNothing);
    expect(ble.statusRequests, 0);
    expect(ble.permissionRequests, 0);
    expect(ble.commands, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('scan requests permission and surfaces permission denial', (
    tester,
  ) async {
    final ble = await _page(
      tester,
      _Service()
        ..connected = false
        ..permission = false,
    );
    await tester.tap(find.text('Scan for controllers'));
    await tester.pump();
    expect(ble.permissionRequests, 1);
    expect(
      find.textContaining('Bluetooth permission is required'),
      findsOneWidget,
    );
    expect(find.text('Scan for controllers'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'failed command shows only failure and leaves reported lights unchanged',
    (tester) async {
      final ble = await _page(tester);
      await tester.tap(_key('set-north-green'));
      await tester.pump();
      expect(ble.commands, ['north:green']);
      expect(_enabled(tester, 'all-red'), isFalse);
      expect(tester.widget<Text>(_key('reported-north')).data, 'Reported: RED');
      ble.pending!.completeError(StateError('ACK timed out'));
      await tester.pump();
      expect(find.textContaining('Command failed:'), findsOneWidget);
      expect(find.textContaining('Command accepted'), findsNothing);
      expect(_enabled(tester, 'all-red'), isTrue);
      expect(tester.widget<Text>(_key('reported-north')).data, 'Reported: RED');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('accepted transfer still waits for device-reported completion', (
    tester,
  ) async {
    final ble = await _page(tester);
    await tester.tap(_key('set-north-green'));
    await tester.pump();
    ble.emit(
      _Status(
        phase: 'yellow',
        targetDirection: 'north',
        lights: {
          'north': 'red',
          'east': 'yellow',
          'south': 'red',
          'west': 'red',
        },
      ),
    );
    ble.pending!.complete();
    await tester.pump();
    expect(
      find.textContaining(
        'acceptance does not mean the transition is complete',
      ),
      findsOneWidget,
    );
    expect(_enabled(tester, 'set-north-green'), isFalse);
    expect(_enabled(tester, 'all-red'), isTrue);
    expect(tester.widget<Text>(_key('reported-north')).data, 'Reported: RED');
    ble.emit(
      _Status(
        lights: {
          'north': 'green',
          'east': 'red',
          'south': 'red',
          'west': 'red',
        },
      ),
    );
    await tester.pump();
    expect(tester.widget<Text>(_key('reported-north')).data, 'Reported: GREEN');
    expect(_enabled(tester, 'set-north-green'), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'auto timings have safe ranges and explicit nonoptimistic apply',
    (tester) async {
      final ble = await _page(tester);
      final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
      expect(sliders.map((slider) => slider.min), [5, 3, 2]);
      expect(sliders.map((slider) => slider.max), [300, 60, 60]);
      expect(ble.commands, isEmpty);
      final apply = find.text('Apply auto mode and timings');
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pump();
      expect(ble.commands, ['auto:30:5:2']);
      expect(find.text('Device-reported mode: manual'), findsOneWidget);
      ble.pending!.complete();
      await tester.pump();
      expect(find.text('Device-reported mode: manual'), findsOneWidget);
      ble.emit(_Status(mode: 'auto'));
      await tester.pump();
      expect(find.text('Device-reported mode: auto'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
