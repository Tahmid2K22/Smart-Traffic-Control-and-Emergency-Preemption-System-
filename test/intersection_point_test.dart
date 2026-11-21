import 'dart:math' as math;

import 'package:e_ambulance/models/intersection_point.dart';
import 'package:e_ambulance/services/overpass_signal_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const point = IntersectionPoint.khulna;
  double latitudeAtDistance(double meters) =>
      point.latitude + meters / 6371000 * 180 / math.pi;

  test('Khulna seed contains the decoded Plus Code center', () {
    expect(point.id, 'khulna_durbar_bangla');
    expect(point.plusCode, 'VGX3+G39');
    expect(point.latitude, closeTo(22.8987875, 1e-10));
    expect(point.longitude, closeTo(89.502734375, 1e-10));
    expect(point.distanceFrom(point.latitude, point.longitude), 0);
  });

  test('allows escape requests within 1 km, including at the intersection', () {
    expect(point.canRequestFrom(point.latitude, point.longitude), isTrue);
    expect(
      point.canRequestFrom(latitudeAtDistance(999.99), point.longitude),
      isTrue,
    );
    expect(
      point.distanceFrom(latitudeAtDistance(1000), point.longitude),
      closeTo(1000, 1e-6),
    );
    expect(
      point.canRequestFrom(latitudeAtDistance(1000.01), point.longitude),
      isFalse,
    );
    expect(
      point.canRequestFrom(latitudeAtDistance(1200), point.longitude),
      isFalse,
    );
  });

  test('disabled intersections never accept requests', () {
    final disabled = IntersectionPoint.fromMap(point.id, {
      ...point.toMap(),
      'isActive': false,
    });
    expect(disabled.canRequestFrom(point.latitude, point.longitude), isFalse);
  });

  test('round trips Firestore fields, including integer coordinates', () {
    final copy = IntersectionPoint.fromMap(point.id, point.toMap());
    expect(copy.toMap(), point.toMap());
    expect(
      IntersectionPoint.fromMap('test', {
        ...point.toMap(),
        'latitude': 22,
        'longitude': 89,
      }).latitude,
      22.0,
    );
  });

  test('rejects invalid and non-finite coordinates', () {
    for (final latitude in [91.0, -91.0, double.nan, double.infinity]) {
      expect(
        () => IntersectionPoint.validateCoordinates(latitude, 89),
        throwsArgumentError,
      );
    }
    for (final longitude in [181.0, -181.0, double.nan, double.infinity]) {
      expect(
        () => IntersectionPoint.validateCoordinates(22, longitude),
        throwsArgumentError,
      );
    }
  });

  test(
    'explicit officer assignment takes precedence over location or name',
    () {
      expect(point.matchesOfficer(intersectionId: point.id), isTrue);
      expect(
        point.matchesOfficer(
          intersectionId: 'another',
          assignedIntersection: point.name,
          latitude: point.latitude,
          longitude: point.longitude,
        ),
        isFalse,
      );
    },
  );

  test('matches officers within 250 m of the saved intersection', () {
    expect(
      point.matchesOfficer(
        latitude: latitudeAtDistance(249),
        longitude: point.longitude,
      ),
      isTrue,
    );
    expect(
      point.matchesOfficer(
        assignedIntersection: point.name,
        latitude: latitudeAtDistance(251),
        longitude: point.longitude,
      ),
      isFalse,
    );
  });

  test('supports legacy officer name and Plus Code assignments', () {
    for (final assignment in [' vgx3+g39 ', 'VGX3+G39, KHULNA', point.name]) {
      expect(point.matchesOfficer(assignedIntersection: assignment), isTrue);
    }
    expect(point.matchesOfficer(assignedIntersection: 'Khulna'), isFalse);
    expect(point.matchesOfficer(), isFalse);
  });

  test('automatic approach alerts also use the 500 m limit and heading', () {
    bool approaching(double meters, double heading) =>
        isApproachingIntersection(
          driverLat: latitudeAtDistance(meters),
          driverLng: point.longitude,
          driverHeading: heading,
          signalLat: point.latitude,
          signalLng: point.longitude,
        );
    expect(approaching(499, 180), isTrue);
    expect(approaching(501, 180), isFalse);
    expect(approaching(499, 0), isFalse);
  });
}
