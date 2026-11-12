import 'package:e_ambulance/models/intersection_point.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new Khulna Plus Codes use verified Open Location Code centers', () {
    expect(IntersectionPoint.moylapota.plusCode, 'RGPQ+37');
    expect(IntersectionPoint.moylapota.latitude, 22.8351875);
    expect(IntersectionPoint.moylapota.longitude, 89.5381875);
    expect(IntersectionPoint.royal.plusCode, 'RH66+4W2');
    expect(IntersectionPoint.royal.latitude, 22.8102625);
    expect(IntersectionPoint.royal.longitude, 89.562265625);
    expect(IntersectionPoint.shibbari.plusCode, 'RHC3+V3');
    expect(IntersectionPoint.shibbari.latitude, 22.8221875);
    expect(IntersectionPoint.shibbari.longitude, 89.5526875);
  });

  test('all four seeds have unique intersection and light IDs', () {
    final points = IntersectionPoint.khulnaIntersections;
    expect(points.map((point) => point.id).toSet(), hasLength(4));
    final ids = points.expand(
      (point) => point.lights.values.map((light) => light.id),
    );
    expect(ids.toSet(), hasLength(16));
  });

  for (final point in IntersectionPoint.khulnaIntersections) {
    test('${point.name} has one unconfigured light per approach', () {
      expect(point.wayCount, 4);
      expect(point.trafficLightCount, 4);
      expect(point.lights.keys, ['north', 'east', 'south', 'west']);
      for (final direction in IntersectionPoint.directions) {
        final light = point.lights[direction]!;
        expect(light.id, '${point.id}_$direction');
        expect(light.direction, direction);
        expect(light.controllerId, isNull);
        expect(light.state, 'UNKNOWN');
      }
      final data = point.toMap();
      expect(data['wayCount'], 4);
      expect(data['trafficLightCount'], 4);
      expect((data['trafficLights'] as Map).length, 4);
      expect(IntersectionPoint.fromMap(point.id, data).toMap(), data);
    });
  }

  test(
    'legacy intersections get four unknown defaults without live colors',
    () {
      final data = IntersectionPoint.royal.toMap()
        ..remove('wayCount')
        ..remove('trafficLightCount')
        ..remove('trafficLights');
      final point = IntersectionPoint.fromMap('legacy', data);
      expect(point.lights, hasLength(4));
      expect(
        point.lights.values.every((light) => light.state == 'UNKNOWN'),
        isTrue,
      );
      expect(
        point.lights.values.every((light) => light.controllerId == null),
        isTrue,
      );
    },
  );

  test(
    'reading partially configured lights preserves controller and state',
    () {
      final point = IntersectionPoint.fromMap('configured', {
        ...IntersectionPoint.shibbari.toMap(),
        'trafficLights': {
          'north': {
            'id': 'existing-north',
            'direction': 'north',
            'controllerId': 'existing-controller',
            'state': 'RED',
          },
        },
      });
      expect(point.lights, hasLength(4));
      expect(point.lights['north']!.id, 'existing-north');
      expect(point.lights['north']!.controllerId, 'existing-controller');
      expect(point.lights['north']!.state, 'RED');
      expect(point.lights['east']!.state, 'UNKNOWN');
      final reread = IntersectionPoint.fromMap(point.id, point.toMap());
      expect(reread.lights['north']!.controllerId, 'existing-controller');
      expect(reread.lights['north']!.state, 'RED');
    },
  );
}
