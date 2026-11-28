import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/emergency_service_location.dart';
import 'user_service.dart';

class EmergencyServiceDirectoryService {
  EmergencyServiceDirectoryService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _providedFirestore = firestore,
       _providedAuth = auth;

  final FirebaseFirestore? _providedFirestore;
  final FirebaseAuth? _providedAuth;

  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;

  FirebaseAuth get _auth => _providedAuth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('emergency_services');

  Stream<List<EmergencyServiceLocation>> watchAll() =>
      _collection.snapshots().map((snapshot) {
        final services = snapshot.docs
            .map(EmergencyServiceLocation.fromDocument)
            .toList();
        services.sort(
          (first, second) =>
              first.name.toLowerCase().compareTo(second.name.toLowerCase()),
        );
        return services;
      });

  Future<List<EmergencyServiceLocation>> fetchActive() async {
    final snapshot = await _collection.where('isActive', isEqualTo: true).get();
    final services = snapshot.docs
        .map(EmergencyServiceLocation.fromDocument)
        .toList();
    services.sort(
      (first, second) =>
          first.name.toLowerCase().compareTo(second.name.toLowerCase()),
    );
    return services;
  }

  static List<EmergencyServiceLocation> withinRadius({
    required Iterable<EmergencyServiceLocation> services,
    required LatLng center,
    double radiusMeters = 15000,
    EmergencyServiceCategory? category,
  }) {
    final nearby = services.where((service) {
      if (!service.isActive ||
          (category != null && service.category != category)) {
        return false;
      }
      return Geolocator.distanceBetween(
            center.latitude,
            center.longitude,
            service.latitude,
            service.longitude,
          ) <=
          radiusMeters;
    }).toList();
    nearby.sort(
      (first, second) =>
          Geolocator.distanceBetween(
            center.latitude,
            center.longitude,
            first.latitude,
            first.longitude,
          ).compareTo(
            Geolocator.distanceBetween(
              center.latitude,
              center.longitude,
              second.latitude,
              second.longitude,
            ),
          ),
    );
    return nearby;
  }

  Future<String> _requireAdmin() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Sign in as an admin first.');
    if (!await UserService.instance.isAdmin(uid)) {
      throw StateError('Only admins can manage 999 services.');
    }
    return uid;
  }

  Future<void> save({
    String? id,
    required EmergencyServiceCategory category,
    required String name,
    required String address,
    required double latitude,
    required double longitude,
    String phone = '',
    String description = '',
    bool isActive = true,
  }) async {
    if (name.trim().isEmpty || address.trim().isEmpty) {
      throw ArgumentError('Service name and address are required.');
    }
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      throw ArgumentError('Enter valid latitude and longitude coordinates.');
    }

    final uid = await _requireAdmin();
    final reference = id == null ? _collection.doc() : _collection.doc(id);
    final data = EmergencyServiceLocation(
      id: reference.id,
      category: category,
      name: name,
      address: address,
      latitude: latitude,
      longitude: longitude,
      phone: phone,
      description: description,
      isActive: isActive,
    ).toFirestore(updatedBy: uid, createdBy: id == null ? uid : null);
    await reference.set(data, SetOptions(merge: id != null));
  }

  Future<void> setActive(String id, bool isActive) async {
    final uid = await _requireAdmin();
    await _collection.doc(id).update({
      'isActive': isActive,
      'updatedBy': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String id) async {
    await _requireAdmin();
    await _collection.doc(id).delete();
  }
}
