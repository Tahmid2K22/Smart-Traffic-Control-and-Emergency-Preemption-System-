import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:e_ambulance/services/places_api_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _channel = MethodChannel('e_ambulance/places');
const _center = LatLng(23.75, 90.4);

Map<String, dynamic> _native({
  String id = 'native-1',
  dynamic name = 'Mapped Hospital',
  dynamic latitude = 23.751,
  dynamic longitude = 90.4,
  List<String> types = const ['hospital'],
}) => {
  'id': id,
  'name': name,
  'latitude': latitude,
  'longitude': longitude,
  'types': types,
};

Map<String, dynamic> _osm({
  int id = 1,
  String type = 'node',
  dynamic latitude = 23.751,
  dynamic longitude = 90.4,
  Map<String, dynamic> tags = const {
    'name': 'Mapped Hospital',
    'amenity': 'hospital',
  },
}) => {
  'type': type,
  'id': id,
  if (type == 'node') ...{
    'lat': latitude,
    'lon': longitude,
  } else
    'center': {'lat': latitude, 'lon': longitude},
  'tags': tags,
};

http.Response _response(List<dynamic> elements) => http.Response(
  jsonEncode({'elements': elements}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<List<NearbyPlaceResult>> _nearby(
  PlacesApiService service, {
  String type = 'hospital',
  double radius = 1,
}) => service.nearby(center: _center, type: type, radiusMeters: radius);

class _TrackingClient extends MockClient {
  _TrackingClient() : super((_) async => _response([]));

  bool closed = false;

  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(_channel, (_) async => {'places': []});
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_channel, null);
  });

  test(
    'native remains first, uses 15 km, filters, deduplicates and sorts',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        return {
          'places': [
            _native(id: 'farther', name: 'Farther Hospital', latitude: 23.85),
            _native(id: 'outside', latitude: 24.0),
            _native(name: '   '),
            _native(name: 42),
            _native(name: 'Hospital'),
            _native(name: '1234'),
            _native(name: '💉'),
            _native(name: '！！！'),
            _native(latitude: 100),
            _native(longitude: 181),
            _native(latitude: double.nan),
            _native(longitude: double.infinity),
            _native(latitude: '23.751'),
            _native()..remove('latitude'),
            _native(id: ''),
            _native(types: ['clinic']),
            _native(types: ['pharmacy']),
            _native(types: ['hospital', 'clinic']),
            _native(types: ['hospital', 'pharmacy']),
            _native(types: []),
            'not a place',
            _native(id: 'nearest', latitude: 23.7501),
            _native(id: 'nearest', name: 'Duplicate ID', latitude: 23.7502),
            _native(
              id: 'same-name',
              name: ' mapped   HOSPITAL ',
              latitude: 23.7503,
            ),
            _native(id: 'other-branch', latitude: 23.76),
          ],
        };
      });
      final client = MockClient(
        (_) async => fail('Valid native results must not fetch OSM'),
      );
      addTearDown(client.close);
      final service = PlacesApiService(client: client);

      final results = await _nearby(service, radius: 50000);

      expect(PlacesApiService.nearbyRadiusMeters, 15000.0);
      expect(calls.single.method, 'nearby');
      expect(calls.single.arguments, {
        'type': 'hospital',
        'latitude': _center.latitude,
        'longitude': _center.longitude,
        'radiusMeters': 15000.0,
      });
      expect(results.map((place) => place.id), [
        'nearest',
        'other-branch',
        'farther',
      ]);
      expect(results.every((place) => place.isOpen == null), isTrue);
    },
  );

  test(
    'native strict spherical distance boundary includes only <= 15 km',
    () async {
      final degreesPerMeter = 180 / (math.pi * 6371000);
      messenger.setMockMethodCallHandler(
        _channel,
        (_) async => {
          'places': [
            _native(
              id: 'inside',
              name: 'Inside Hospital',
              latitude: _center.latitude + 14999.99 * degreesPerMeter,
            ),
            _native(
              id: 'outside',
              name: 'Outside Hospital',
              latitude: _center.latitude + 15000.01 * degreesPerMeter,
            ),
          ],
        },
      );
      final client = MockClient((_) async => fail('Native result expected'));
      addTearDown(client.close);
      expect(
        (await _nearby(PlacesApiService(client: client))).map((p) => p.id),
        ['inside'],
      );
    },
  );

  for (final nativeState in [
    'empty',
    'unavailable',
    'error',
    'invalid',
    'filtered',
  ]) {
    test(
      'native $nativeState falls back to an exact-radius Overpass POST',
      () async {
        var nativeCalled = false;
        messenger.setMockMethodCallHandler(_channel, (_) async {
          nativeCalled = true;
          switch (nativeState) {
            case 'unavailable':
              throw MissingPluginException();
            case 'error':
              throw PlatformException(code: 'GOOGLE_UNAVAILABLE');
            case 'invalid':
              return {'places': 'invalid'};
            case 'filtered':
              return {
                'places': [_native(latitude: 24.0), _native(name: null)],
              };
            default:
              return {'places': []};
          }
        });
        var requests = 0;
        final client = MockClient((request) async {
          requests++;
          expect(nativeCalled, isTrue);
          expect(request.method, 'POST');
          expect(
            request.url.toString(),
            'https://overpass-api.de/api/interpreter',
          );
          expect(
            request.bodyFields['data'],
            '[out:json][timeout:12];('
            'nwr["amenity"="hospital"](around:15000,23.75,90.4);'
            'nwr["healthcare"="hospital"](around:15000,23.75,90.4);'
            ');out center tags;',
          );
          return _response([_osm()]);
        });
        addTearDown(client.close);

        final results = await _nearby(
          PlacesApiService(client: client),
          radius: 100000,
        );
        expect(results.single.id, 'osm:node:1');
        expect(requests, 1);
      },
    );
  }

  test('Overpass parses nodes, way/relation centers, names, addresses and actual phones', () async {
    final client = MockClient(
      (_) async => _response([
        _osm(
          id: 3,
          type: 'relation',
          latitude: 23.78,
          tags: {
            'name:bn': 'বাংলা হাসপাতাল',
            'healthcare': 'hospital',
            'addr:full': 'Mapped full address',
            'opening_hours': 'Mo-Su 08:00-18:00',
          },
        ),
        _osm(
          id: 2,
          type: 'way',
          latitude: 23.76,
          tags: {
            'name': ' ',
            'name:en': 'English Hospital',
            'amenity': 'hospital',
            'opening_hours': '24/7',
            'contact:phone': '+8802222222',
          },
        ),
        _osm(
          tags: {
            'name': 'Local Hospital',
            'name:en': 'Not the preferred name',
            'amenity': 'hospital',
            'addr:housenumber': '12',
            'addr:street': 'Mapped Road',
            'addr:suburb': 'Mapped Suburb',
            'addr:city': 'Dhaka',
            'addr:postcode': '1200',
            'phone': '+8801111111',
          },
        ),
      ]),
    );
    addTearDown(client.close);

    final results = await _nearby(PlacesApiService(client: client));

    expect(results.map((p) => p.id), [
      'osm:node:1',
      'osm:way:2',
      'osm:relation:3',
    ]);
    expect(results.map((p) => p.name), [
      'Local Hospital',
      'English Hospital',
      'বাংলা হাসপাতাল',
    ]);
    expect(results.map((p) => p.location), [
      const LatLng(23.751, 90.4),
      const LatLng(23.76, 90.4),
      const LatLng(23.78, 90.4),
    ]);
    expect(
      results.first.address,
      '12, Mapped Road, Mapped Suburb, Dhaka, 1200',
    );
    expect(results.last.address, 'Mapped full address');
    expect(results.map((p) => p.phone), ['+8801111111', '+8802222222', null]);
    expect(results.map((p) => p.isOpen), [null, true, null]);
    expect(results.last.types, ['hospital']);
  });

  test(
    'Overpass rejects distant, malformed, unnamed and non-hospital records',
    () async {
      final client = MockClient(
        (_) async => _response([
          _osm(),
          _osm(id: 2, latitude: 24),
          _osm(id: 3, latitude: 91),
          _osm(id: 4, longitude: 181),
          _osm(id: 5, latitude: '23.751'),
          _osm(id: 6)..remove('lon'),
          _osm(id: 7, type: 'way')..remove('center'),
          _osm(id: 8, type: 'relation')
            ..['center'] = {'lat': null, 'lon': 90.4},
          _osm(id: 9, tags: {'amenity': 'hospital'}),
          _osm(id: 10, tags: {'name': 123, 'amenity': 'hospital'}),
          _osm(id: 11, tags: {'name': '  Hospital  ', 'amenity': 'hospital'}),
          _osm(id: 12, tags: {'name': 'Local Clinic', 'amenity': 'clinic'}),
          _osm(id: 13, tags: {'name': 'Local Pharmacy', 'amenity': 'pharmacy'}),
          _osm(
            id: 14,
            tags: {
              'name': 'Mixed Clinic',
              'amenity': 'clinic',
              'healthcare': 'hospital',
            },
          ),
          _osm(id: 15, tags: {'name': 'No Classification'}),
          _osm(id: 0),
          _osm(id: 16, type: 'invalid'),
          _osm(id: 17)..['tags'] = 'invalid',
          null,
        ]),
      );
      addTearDown(client.close);

      final results = await _nearby(PlacesApiService(client: client));
      expect(results.map((p) => p.id), ['osm:node:1']);
      expect(results.single.isOpen, isNull);
      expect(results.single.phone, isNull);
    },
  );

  test('Overpass applies the spherical radius boundary and deduplicates mapped facilities', () async {
    final degreesPerMeter = 180 / (math.pi * 6371000);
    final client = MockClient(
      (_) async => _response([
        _osm(
          id: 5,
          latitude: _center.latitude + 15000.01 * degreesPerMeter,
          tags: {'name': 'Outside Hospital', 'amenity': 'hospital'},
        ),
        _osm(
          id: 4,
          latitude: _center.latitude + 14999.99 * degreesPerMeter,
          tags: {'name': 'Inside Hospital', 'amenity': 'hospital'},
        ),
        _osm(id: 1, latitude: 23.76),
        _osm(
          id: 2,
          type: 'way',
          latitude: 23.7511,
          tags: {'name': ' mapped   HOSPITAL ', 'amenity': 'hospital'},
        ),
        _osm(id: 1),
        _osm(
          id: 1,
          tags: {'name': 'Conflicting duplicate ID', 'amenity': 'hospital'},
        ),
      ]),
    );
    addTearDown(client.close);

    expect((await _nearby(PlacesApiService(client: client))).map((p) => p.id), [
      'osm:node:1',
      'osm:node:4',
    ]);
  });

  test(
    'pharmacy uses the same 15 km radius and only pharmacy amenity query',
    () async {
      messenger.setMockMethodCallHandler(_channel, (call) async {
        expect(call.arguments['type'], 'pharmacy');
        expect(call.arguments['radiusMeters'], 15000.0);
        return {'places': []};
      });
      final client = MockClient((request) async {
        expect(
          request.bodyFields['data'],
          '[out:json][timeout:12];(nwr["amenity"="pharmacy"]'
          '(around:15000,23.75,90.4););out center tags;',
        );
        return _response([
          _osm(),
          _osm(id: 2, tags: {'name': 'Mapped Pharmacy', 'amenity': 'pharmacy'}),
          _osm(
            id: 3,
            latitude: 24,
            tags: {'name': 'Distant Pharmacy', 'amenity': 'pharmacy'},
          ),
        ]);
      });
      addTearDown(client.close);
      final results = await _nearby(
        PlacesApiService(client: client),
        type: 'pharmacy',
        radius: 500,
      );
      expect(results.single.name, 'Mapped Pharmacy');
      expect(results.single.isOpen, isNull);
    },
  );

  test(
    'valid empty OSM response stays empty with no seed or expanded search',
    () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        expect(request.url.host, 'overpass-api.de');
        return _response([]);
      });
      addTearDown(client.close);
      expect(await _nearby(PlacesApiService(client: client)), isEmpty);
      expect(requests, 1);
    },
  );

  for (final status in [408, 429, 500, 502, 503, 504]) {
    for (final type in ['hospital', 'pharmacy']) {
      test('HTTP $status primary uses worldwide mirror with identical $type query', () async {
        final requests = <http.Request>[];
        final client = MockClient((request) async {
          requests.add(request);
          if (requests.length == 1) return http.Response('unavailable', status);
          return _response([
            _osm(tags: {'name': 'Mapped Facility', 'amenity': type}),
          ]);
        });
        addTearDown(client.close);
        final results = await _nearby(
          PlacesApiService(client: client),
          type: type,
          radius: 99999,
        );
        expect(results.single.name, 'Mapped Facility');
        expect(requests.map((request) => request.url.toString()), [
          'https://overpass-api.de/api/interpreter',
          'https://overpass.private.coffee/api/interpreter',
        ]);
        expect(requests.every((request) => request.method == 'POST'), isTrue);
        expect(requests.last.body, requests.first.body);
        expect(
          requests.last.bodyFields['data'],
          '[out:json][timeout:12];(nwr["amenity"="$type"](around:15000,23.75,90.4);'
          '${type == 'hospital' ? 'nwr["healthcare"="hospital"](around:15000,23.75,90.4);' : ''}'
          ');out center tags;',
        );
      });
    }
  }

  test(
    'empty successful mirror stays empty with no further attempts',
    () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return requests == 1
            ? http.Response('unavailable', 503)
            : _response([]);
      });
      addTearDown(client.close);
      expect(await _nearby(PlacesApiService(client: client)), isEmpty);
      expect(requests, 2);
    },
  );

  test('transient transport failure falls back to mirror', () async {
    final hosts = <String>[];
    final client = MockClient((request) async {
      hosts.add(request.url.host);
      if (hosts.length == 1) throw http.ClientException('connection reset');
      return _response([_osm()]);
    });
    addTearDown(client.close);
    expect(
      (await _nearby(PlacesApiService(client: client))).single.id,
      'osm:node:1',
    );
    expect(hosts, ['overpass-api.de', 'overpass.private.coffee']);
  });

  for (final body in [
    '{"remark":"runtime error: Query timed out"}',
    '{"elements":{},"remark":"bad"}',
    '{"elements":[],"remark":"runtime error: Query timed out"}',
  ]) {
    test('Overpass remark triggers mirror instead of empty: $body', () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return requests == 1 ? http.Response(body, 200) : _response([_osm()]);
      });
      addTearDown(client.close);
      expect(
        (await _nearby(PlacesApiService(client: client))).single.id,
        'osm:node:1',
      );
      expect(requests, 2);
    });
  }

  test('remarks on both endpoints report both failures', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response('{"remark":"Query timed out"}', 200);
    });
    addTearDown(client.close);
    await expectLater(
      _nearby(PlacesApiService(client: client)),
      throwsA(
        isA<http.ClientException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('both endpoints'),
            contains('Query timed out'),
            contains('overpass-api.de'),
            contains('overpass.private.coffee'),
          ),
        ),
      ),
    );
    expect(requests, 2);
  });

  test(
    'malformed mirror reports both failures without further retry',
    () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return requests == 1
            ? http.Response('unavailable', 503)
            : http.Response('invalid JSON', 200);
      });
      addTearDown(client.close);
      await expectLater(
        _nearby(PlacesApiService(client: client)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('both endpoints'),
              contains('HTTP 503'),
              contains('invalid JSON'),
            ),
          ),
        ),
      );
      expect(requests, 2);
    },
  );

  testWidgets('primary timeout after 15 seconds can recover via mirror', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final requests = <http.Request>[];
    final client = MockClient((request) {
      requests.add(request);
      return requests.length == 1
          ? pending.future
          : Future.value(_response([_osm()]));
    });
    addTearDown(client.close);
    final result = _nearby(PlacesApiService(client: client));
    await tester.pump();
    await tester.pump(const Duration(seconds: 15));
    expect((await result).single.id, 'osm:node:1');
    expect(requests.map((request) => request.url.host), [
      'overpass-api.de',
      'overpass.private.coffee',
    ]);
    expect(requests.last.body, requests.first.body);
    pending.complete(_response([]));
    await tester.pump();
  });

  for (final status in [400, 401, 403, 408, 429, 500, 502, 503, 504]) {
    test(
      'HTTP $status throws a descriptive error, never fabricated results',
      () async {
        final hosts = <String>[];
        final client = MockClient((request) async {
          hosts.add(request.url.host);
          return http.Response('upstream failure', status);
        });
        addTearDown(client.close);
        await expectLater(
          _nearby(PlacesApiService(client: client)),
          throwsA(
            isA<http.ClientException>().having(
              (e) => e.message,
              'message',
              allOf(contains('Overpass'), contains('HTTP $status')),
            ),
          ),
        );
        expect(
          hosts,
          status == 408 || status == 429 || status >= 500
              ? ['overpass-api.de', 'overpass.private.coffee']
              : ['overpass-api.de'],
        );
      },
    );
  }

  for (final body in ['not JSON', '[]', '{}', '{"elements":null}']) {
    test('invalid/error Overpass response throws: $body', () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        expect(request.url.host, 'overpass-api.de');
        return http.Response(body, 200);
      });
      addTearDown(client.close);
      await expectLater(
        _nearby(PlacesApiService(client: client)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Overpass'),
          ),
        ),
      );
      expect(requests, 1);
    });
  }

  test(
    'network failure is descriptive and never converted into empty results',
    () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        throw http.ClientException('offline');
      });
      addTearDown(client.close);
      await expectLater(
        _nearby(PlacesApiService(client: client)),
        throwsA(
          isA<http.ClientException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Overpass'),
              contains('offline'),
              contains('both endpoints'),
              contains('overpass-api.de'),
              contains('overpass.private.coffee'),
            ),
          ),
        ),
      );
      expect(requests, 2);
    },
  );

  testWidgets('hung native and both endpoints fail within 40 seconds', (
    tester,
  ) async {
    final nativePending = Completer<dynamic>();
    messenger.setMockMethodCallHandler(_channel, (_) => nativePending.future);
    final pending = <Completer<http.Response>>[];
    final hosts = <String>[];
    final client = MockClient((request) {
      hosts.add(request.url.host);
      final response = Completer<http.Response>();
      pending.add(response);
      return response.future;
    });
    addTearDown(client.close);
    final expectation = expectLater(
      _nearby(PlacesApiService(client: client)),
      throwsA(
        isA<http.ClientException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('both endpoints'),
            contains('15 seconds'),
            contains('20 seconds'),
            contains('overpass-api.de'),
            contains('overpass.private.coffee'),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(hosts, isEmpty);
    await tester.pump(const Duration(seconds: 5));
    expect(hosts, ['overpass-api.de']);
    await tester.pump(const Duration(seconds: 15));
    expect(hosts, ['overpass-api.de', 'overpass.private.coffee']);
    await tester.pump(const Duration(seconds: 20));
    await expectation;
    nativePending.complete({'places': []});
    for (final response in pending) {
      response.complete(_response([]));
    }
    await tester.pump();
  });

  testWidgets('hung native request falls back after five seconds', (
    tester,
  ) async {
    final pending = Completer<dynamic>();
    messenger.setMockMethodCallHandler(_channel, (_) => pending.future);
    final client = MockClient((_) async => _response([_osm()]));
    addTearDown(client.close);
    final result = _nearby(PlacesApiService(client: client));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect((await result).single.id, 'osm:node:1');
    pending.complete({'places': []});
    await tester.pump();
  });

  test('dispose does not close caller-owned injected clients', () {
    final client = _TrackingClient();
    final service = PlacesApiService(client: client);
    service.dispose();
    expect(client.closed, isFalse);
    client.close();
  });

  test('dispose closes an internally created client', () {
    final client = _TrackingClient();
    final service = http.runWithClient(() => PlacesApiService(), () => client);
    service.dispose();
    expect(client.closed, isTrue);
  });

  test(
    'native autocomplete and getPlace retain their existing behavior',
    () async {
      messenger.setMockMethodCallHandler(_channel, (call) async {
        if (call.method == 'autocomplete') {
          expect(call.arguments['query'], 'Dhaka');
          return [
            {'placeId': 'suggestion-id', 'description': 'Dhaka'},
          ];
        }
        expect(call.method, 'details');
        expect(call.arguments['placeId'], 'suggestion-id');
        return _native(name: 'Detail Hospital')..['phone'] = '+880123456';
      });
      final client = MockClient(
        (_) async => fail('No nearby request expected'),
      );
      addTearDown(client.close);
      final service = PlacesApiService(client: client);
      expect(await service.autocomplete(input: 'a', bias: _center), isEmpty);
      expect(
        (await service.autocomplete(
          input: ' Dhaka ',
          bias: _center,
        )).single.placeId,
        'suggestion-id',
      );
      final detail = await service.getPlace('suggestion-id');
      expect(detail?.name, 'Detail Hospital');
      expect(detail?.phone, '+880123456');
      expect(detail?.isOpen, isNull);
    },
  );
}
