import 'package:e_ambulance/models/emergency_service_location.dart';
import 'package:e_ambulance/services/emergency_service_directory_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  const center = LatLng(23.8103, 90.4125);
  const nearbyPolice = EmergencyServiceLocation(
    id: 'police-nearby',
    category: EmergencyServiceCategory.policeStation,
    name: 'Central Police Station',
    address: 'Dhaka',
    latitude: 23.82,
    longitude: 90.4125,
  );
  const nearbyFire = EmergencyServiceLocation(
    id: 'fire-nearby',
    category: EmergencyServiceCategory.fireService,
    name: 'Fire Station',
    address: 'Dhaka',
    latitude: 23.83,
    longitude: 90.4125,
  );
  const farPolice = EmergencyServiceLocation(
    id: 'police-far',
    category: EmergencyServiceCategory.policeStation,
    name: 'Distant Police Station',
    address: 'Outside the radius',
    latitude: 24.1,
    longitude: 90.4125,
  );
  const disabledFire = EmergencyServiceLocation(
    id: 'fire-disabled',
    category: EmergencyServiceCategory.fireService,
    name: 'Disabled Fire Station',
    address: 'Dhaka',
    latitude: 23.811,
    longitude: 90.4125,
    isActive: false,
  );

  test('returns only active services within 15 km, nearest first', () {
    final results = EmergencyServiceDirectoryService.withinRadius(
      services: const [farPolice, nearbyFire, disabledFire, nearbyPolice],
      center: center,
    );

    expect(results.map((service) => service.id), [
      'police-nearby',
      'fire-nearby',
    ]);
  });

  test('filters nearby results by selected service category', () {
    final results = EmergencyServiceDirectoryService.withinRadius(
      services: const [nearbyFire, nearbyPolice],
      center: center,
      category: EmergencyServiceCategory.fireService,
    );

    expect(results.map((service) => service.id), ['fire-nearby']);
  });
}
