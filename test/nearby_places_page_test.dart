import 'dart:async';

import 'package:e_ambulance/pages/nearby_places_page.dart';
import 'package:e_ambulance/services/places_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

const _center = LatLng(51.5, -0.12);
const _hospital = NearbyPlaceResult(
  id: 'mapped-hospital',
  name: 'St Thomas Hospital',
  address: 'Westminster Bridge Road, London',
  location: LatLng(51.498, -0.118),
  isOpen: null,
  types: ['hospital'],
);

Position _position([LatLng center = _center]) => Position(
  longitude: center.longitude,
  latitude: center.latitude,
  timestamp: DateTime.now(),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

class _Request {
  _Request(this.center, this.type, this.radiusMeters);
  final LatLng center;
  final String type;
  final double radiusMeters;
}

class _PlacesApi extends PlacesApiService {
  final requests = <_Request>[];
  Future<List<NearbyPlaceResult>> Function() respond = () async => [];
  bool disposed = false;

  @override
  Future<List<NearbyPlaceResult>> nearby({
    required LatLng center,
    required String type,
    required double radiusMeters,
  }) {
    requests.add(_Request(center, type, radiusMeters));
    return respond();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const locationChannel = MethodChannel('flutter.baseflow.com/geolocator');
  const launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');
  late _PlacesApi api;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    api = _PlacesApi();
  });

  tearDown(() {
    api.dispose();
    messenger.setMockMethodCallHandler(locationChannel, null);
    messenger.setMockMethodCallHandler(launcherChannel, null);
  });

  Future<void> open(
    WidgetTester tester, {
    Future<Position> Function()? locate,
    NearbyPlaceType type = NearbyPlaceType.hospitals,
    bool productionLocation = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NearbyPlacesPage(
          type: type,
          placesApi: api,
          locate: productionLocation ? null : locate ?? () async => _position(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('waits for one fresh GPS fix; never searches a fallback center', (
    tester,
  ) async {
    final gps = Completer<Position>();
    var locationCalls = 0;
    await open(
      tester,
      locate: () {
        locationCalls++;
        return gps.future;
      },
    );
    expect(locationCalls, 1);
    expect(api.requests, isEmpty);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );

    await tester.tap(find.byTooltip('Show map'));
    await tester.pump();
    expect(find.byType(GoogleMap), findsNothing);
    await tester.tap(find.byTooltip('Show list'));
    await tester.pump();

    gps.complete(_position());
    await tester.pumpAndSettle();
    expect(api.requests, hasLength(1));
    expect(api.requests.single.center, _center);
    expect(api.requests.single.radiusMeters, 15000.0);
    expect(locationCalls, 1);
  });

  for (final failure in <String, Object>{
    'denied': const PermissionDeniedException('Denied by user'),
    'disabled': const LocationServiceDisabledException(),
    'timeout': TimeoutException('GPS timed out'),
    'error': Exception('GPS unavailable'),
  }.entries) {
    testWidgets('GPS ${failure.key} shows retry and never calls API', (
      tester,
    ) async {
      await open(tester, locate: () async => throw failure.value);
      await tester.pumpAndSettle();
      expect(api.requests, isEmpty);
      expect(find.text('Retry scan'), findsOneWidget);
      expect(find.text('Scan unsuccessful'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('No hospitals found'), findsNothing);
      expect(find.byType(GoogleMap), findsNothing);
      if (failure.key == 'denied' || failure.key == 'disabled') {
        expect(find.text('Settings'), findsOneWidget);
        final settingsCalls = <MethodCall>[];
        messenger.setMockMethodCallHandler(locationChannel, (call) async {
          settingsCalls.add(call);
          return true;
        });
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        expect(
          settingsCalls.single.method,
          failure.key == 'disabled'
              ? 'openLocationSettings'
              : 'openAppSettings',
        );
      }
    });
  }

  testWidgets(
    'production locator requests high accuracy GPS once with 20s limit',
    (tester) async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(locationChannel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'isLocationServiceEnabled':
            return true;
          case 'checkPermission':
            return LocationPermission.denied.index;
          case 'requestPermission':
            return LocationPermission.whileInUse.index;
          case 'getCurrentPosition':
            return _position().toJson();
        }
        return null;
      });
      await open(tester, productionLocation: true);
      await tester.pumpAndSettle();
      expect(calls.map((call) => call.method), [
        'isLocationServiceEnabled',
        'checkPermission',
        'requestPermission',
        'getCurrentPosition',
      ]);
      final settings = calls.last.arguments as Map;
      expect(settings['accuracy'], LocationAccuracy.high.index);
      expect(api.requests, hasLength(1));
      expect(api.requests.single.center, _center);
      // The plugin enforces timeLimit in Dart, not in its platform arguments.
    },
  );

  testWidgets('production GPS times out after 20 seconds without searching', (
    tester,
  ) async {
    final pendingFix = Completer<Map<String, dynamic>>();
    messenger.setMockMethodCallHandler(locationChannel, (call) async {
      switch (call.method) {
        case 'isLocationServiceEnabled':
          return true;
        case 'checkPermission':
          return LocationPermission.whileInUse.index;
        case 'getCurrentPosition':
          return pendingFix.future;
      }
      return null;
    });
    await open(tester, productionLocation: true);
    await tester.pump(const Duration(seconds: 19));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(api.requests, isEmpty);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.textContaining('within 20 seconds'), findsOneWidget);
    expect(find.text('Retry scan'), findsOneWidget);
    expect(api.requests, isEmpty);
    pendingFix.complete(_position().toJson());
    await tester.pump();
    expect(api.requests, isEmpty);
  });

  testWidgets(
    'map shows fixed circle, loading, empty, error, and no stale markers',
    (tester) async {
      final response = Completer<List<NearbyPlaceResult>>();
      api.respond = () => response.future;
      await open(tester);
      await tester.tap(find.byTooltip('Show map'));
      await tester.pump();
      var map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      expect(map.initialCameraPosition.target, _center);
      expect(map.circles.single.radius, 15000.0);
      expect(map.circles.single.center, _center);
      expect(map.markers, isEmpty);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      response.complete([_hospital]);
      await tester.pumpAndSettle();
      map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      expect(map.markers.single.position, _hospital.location);
      expect(find.text('Scan again'), findsOneWidget);

      api.respond = () async => [];
      await tester.tap(find.text('Scan again'));
      await tester.pumpAndSettle();
      map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      expect(map.markers, isEmpty);
      expect(find.text('No hospitals found within 15 km'), findsOneWidget);
      api.respond = () async => throw Exception('Map scan offline');
      await tester.tap(find.text('Scan again'));
      await tester.pumpAndSettle();
      expect(tester.widget<GoogleMap>(find.byType(GoogleMap)).markers, isEmpty);
      expect(find.textContaining('Map scan offline'), findsOneWidget);
      expect(find.text('Retry scan'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'production permanently denied location offers Settings without GPS/API',
    (tester) async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(locationChannel, (call) async {
        calls.add(call.method);
        if (call.method == 'isLocationServiceEnabled') return true;
        if (call.method == 'checkPermission') {
          return LocationPermission.deniedForever.index;
        }
        return null;
      });
      await open(tester, productionLocation: true);
      await tester.pumpAndSettle();
      expect(calls, ['isLocationServiceEnabled', 'checkPermission']);
      expect(api.requests, isEmpty);
      expect(find.textContaining('permanently denied'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Retry scan'), findsOneWidget);
    },
  );

  for (final type in NearbyPlaceType.values) {
    testWidgets('$type true empty has no dummy results or radius controls', (
      tester,
    ) async {
      await open(tester, type: type);
      await tester.pumpAndSettle();
      final facilities = type == NearbyPlaceType.hospitals
          ? 'hospitals'
          : 'pharmacies';
      expect(find.text('No $facilities found within 15 km'), findsOneWidget);
      expect(find.text('0 facilities found nearby'), findsOneWidget);
      expect(find.textContaining('Searching'), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(FilterChip), findsNothing);
      expect(find.textContaining('Expand'), findsNothing);
      expect(find.byTooltip('Directions'), findsNothing);
      expect(find.byIcon(Icons.call_rounded), findsNothing);
      expect(find.text('Scan again'), findsOneWidget);
      expect(api.requests.single.radiusMeters, 15000.0);
      expect(
        api.requests.single.type,
        type == NearbyPlaceType.hospitals ? 'hospital' : 'pharmacy',
      );
    });
  }

  testWidgets(
    'API failure is not empty and retry repeats GPS and the fixed scan',
    (tester) async {
      var fixes = 0;
      api.respond = () async => throw Exception('Overpass network unavailable');
      await open(
        tester,
        locate: () async {
          fixes++;
          return _position();
        },
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Overpass network unavailable'),
        findsOneWidget,
      );
      expect(find.text('Retry scan'), findsOneWidget);
      expect(find.textContaining('No hospitals found'), findsNothing);
      api.respond = () async => [];
      await tester.tap(find.text('Retry scan'));
      await tester.pumpAndSettle();
      expect(fixes, 2);
      expect(api.requests, hasLength(2));
      expect(api.requests.every((r) => r.radiusMeters == 15000.0), isTrue);
      expect(find.text('No hospitals found within 15 km'), findsOneWidget);
    },
  );

  testWidgets(
    'real supplied hospital keeps unknown hours and has no emergency call fallback',
    (tester) async {
      api.respond = () async => [_hospital];
      final launches = <MethodCall>[];
      messenger.setMockMethodCallHandler(launcherChannel, (call) async {
        launches.add(call);
        return true;
      });
      await open(tester);
      await tester.pumpAndSettle();
      expect(find.text(_hospital.name), findsOneWidget);
      expect(find.text(_hospital.address), findsOneWidget);
      expect(find.text('Hours unavailable'), findsOneWidget);
      expect(find.text('Open 24/7'), findsNothing);
      expect(find.text('Open now'), findsNothing);
      expect(find.byIcon(Icons.call_rounded), findsNothing);
      expect(find.textContaining('999'), findsNothing);
      expect(launches, isEmpty);

      await tester.tap(find.byTooltip('Directions'));
      await tester.pumpAndSettle();
      final uri = Uri.parse((launches.last.arguments as Map)['url'] as String);
      expect(uri.queryParameters['destination'], '51.498,-0.118');
      expect(uri.queryParameters['origin'], '51.5,-0.12');
      expect(
        launches.any((call) => call.arguments.toString().contains('tel:999')),
        isFalse,
      );
    },
  );

  testWidgets(
    'scan again clears stale cards, waits for new GPS, and retains no results on failure',
    (tester) async {
      api.respond = () async => [_hospital];
      final secondFix = Completer<Position>();
      var fixes = 0;
      await open(
        tester,
        locate: () {
          fixes++;
          return fixes == 1 ? Future.value(_position()) : secondFix.future;
        },
      );
      await tester.pumpAndSettle();
      expect(find.text(_hospital.name), findsOneWidget);
      await tester.tap(find.text('Scan again'));
      await tester.pump();
      expect(find.text(_hospital.name), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(api.requests, hasLength(1));
      final response = Completer<List<NearbyPlaceResult>>();
      api.respond = () => response.future;
      const moved = LatLng(51.52, -0.15);
      secondFix.complete(_position(moved));
      await tester.pump();
      expect(api.requests, hasLength(2));
      expect(api.requests.last.center, moved);
      expect(api.requests.last.radiusMeters, 15000.0);
      expect(find.text(_hospital.name), findsNothing);
      response.completeError(Exception('Network disconnected'));
      await tester.pumpAndSettle();
      expect(find.text('Retry scan'), findsOneWidget);
      expect(find.text(_hospital.name), findsNothing);
      expect(find.text('Scan unsuccessful'), findsOneWidget);
    },
  );

  testWidgets(
    'filters out results outside 15 km and leaves injected service owned by caller',
    (tester) async {
      api.respond = () async => [
        _hospital,
        const NearbyPlaceResult(
          id: 'far',
          name: 'Faraway Hospital',
          address: 'Outside the search area',
          location: LatLng(52.5, -0.12),
          isOpen: true,
          types: ['hospital'],
        ),
      ];
      await open(tester);
      await tester.pumpAndSettle();
      expect(find.text(_hospital.name), findsOneWidget);
      expect(find.text('Faraway Hospital'), findsNothing);
      expect(find.text('1 facilities found nearby'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(api.disposed, isFalse);
    },
  );
}
