import 'dart:async';

import 'package:e_ambulance/pages/traffic_light_control_page.dart';
import 'package:e_ambulance/services/ble_traffic_service.dart';
import 'package:flutter/material.dart';
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
  int get uptime => 42;
  @override
  int get sequence => 7;
  @override
  String? get ackId => null;
  @override
  String lightFor(String direction) => lights[direction] ?? 'unknown';
}

class _Service extends Fake implements BleTrafficService {
  final statuses = StreamController<TrafficLightStatus>.broadcast(sync: true);
  final connections = StreamController<bool>.broadcast(sync: true);
  bool authorized = true;
  bool connected = true;
  bool ready = true;
  bool permission = true;
  int permissionRequests = 0;
  int disconnects = 0;
  int statusRequests = 0;
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

Future<_Service> _page(WidgetTester tester, [_Service? service]) async {
  await _largeSurface(tester);
  final ble = service ?? _Service();
  addTearDown(ble.close);
  await tester.pumpWidget(
    MaterialApp(home: TrafficLightControlPage(service: ble)),
  );
  await tester.pumpAndSettle();
  return ble;
}

void main() {
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
