import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class TrafficService {
  TrafficService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<QuerySnapshot<Map<String, dynamic>>> alertsForOfficer(String uid) =>
      _firestore
          .collection('emergency_alerts')
          .where('officerId', isEqualTo: uid)
          .where('status', isEqualTo: 'ACTIVE')
          .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> activeDispatches() =>
      _firestore
          .collection('dispatches')
          .where('status', isEqualTo: 'ACTIVE')
          .snapshots();

  Future<void> updateDispatchLocation({
    required String dispatchId,
    required Position position,
  }) async {
    await _firestore.collection('dispatches').doc(dispatchId).set({
      'status': 'ACTIVE',
      'driverLocation': GeoPoint(position.latitude, position.longitude),
      'driverLat': position.latitude,
      'driverLng': position.longitude,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _createNearbyAlerts(dispatchId, position);
  }

  Future<void> _createNearbyAlerts(String dispatchId, Position position) async {
    final officers = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'traffic_police')
        .where('isVerified', isEqualTo: true)
        .where('isActive', isEqualTo: true)
        .get();
    for (final officer in officers.docs) {
      final data = officer.data();
      final location = data['intersectionLocation'];
      final lat = location is GeoPoint
          ? location.latitude
          : (data['intersectionLatitude'] as num?)?.toDouble();
      final lng = location is GeoPoint
          ? location.longitude
          : (data['intersectionLongitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        lat,
        lng,
      );
      if (distance <= 1000) {
        final alertId = '${dispatchId}_${officer.id}';
        await _firestore.collection('emergency_alerts').doc(alertId).set({
          'dispatchId': dispatchId,
          'officerId': officer.id,
          'intersection': data['assignedIntersection'] ?? '',
          'distanceMeters': distance,
          'status': 'ACTIVE',
          'signalState': 'NORMAL',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }
  }

  StreamSubscription<Position> trackDispatch({
    required String dispatchId,
    required LocationSettings settings,
  }) =>
      Geolocator.getPositionStream(locationSettings: settings).listen(
        (position) => updateDispatchLocation(
          dispatchId: dispatchId,
          position: position,
        ),
      );
}
