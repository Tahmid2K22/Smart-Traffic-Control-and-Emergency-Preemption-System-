import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

enum EmergencyServiceCategory {
  policeStation('police_station', 'Police station'),
  fireService('fire_service', 'Fire service'),
  other('other', 'Other 999 service');

  const EmergencyServiceCategory(this.value, this.label);

  final String value;
  final String label;

  static EmergencyServiceCategory fromValue(Object? value) =>
      EmergencyServiceCategory.values.firstWhere(
        (category) => category.value == value,
        orElse: () => EmergencyServiceCategory.other,
      );
}

class EmergencyServiceLocation {
  const EmergencyServiceLocation({
    required this.id,
    required this.category,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.phone = '',
    this.description = '',
    this.isActive = true,
  });

  final String id;
  final EmergencyServiceCategory category;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String phone;
  final String description;
  final bool isActive;

  LatLng get location => LatLng(latitude, longitude);

  factory EmergencyServiceLocation.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) {
      throw FormatException('999 service ${document.id} has no data.');
    }
    final latitude = (data['latitude'] as num?)?.toDouble();
    final longitude = (data['longitude'] as num?)?.toDouble();
    if (latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      throw FormatException(
        '999 service ${document.id} has invalid coordinates.',
      );
    }

    return EmergencyServiceLocation(
      id: document.id,
      category: EmergencyServiceCategory.fromValue(data['category']),
      name: data['name'] as String? ?? '',
      address: data['address'] as String? ?? '',
      latitude: latitude,
      longitude: longitude,
      phone: data['phone'] as String? ?? '',
      description: data['description'] as String? ?? '',
      isActive: data['isActive'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore({
    required String updatedBy,
    String? createdBy,
  }) => {
    'category': category.value,
    'name': name.trim(),
    'address': address.trim(),
    'latitude': latitude,
    'longitude': longitude,
    'location': GeoPoint(latitude, longitude),
    'phone': phone.trim(),
    'description': description.trim(),
    'isActive': isActive,
    'updatedBy': updatedBy,
    'updatedAt': FieldValue.serverTimestamp(),
    if (createdBy != null) ...{
      'createdBy': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
    },
  };
}
