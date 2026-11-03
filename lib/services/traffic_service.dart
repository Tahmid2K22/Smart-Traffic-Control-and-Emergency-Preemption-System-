import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'overpass_signal_service.dart';

class TrafficService {
  TrafficService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final _overpass = OverpassSignalService();
  final _signalsByDispatch = <String, List<TrafficSignal>>{};

  Future<void> prepareRoute({
    required String dispatchId,
    required List<LatLng> routePoints,
  }) async {
    final signals = await _overpass.findSignalsAlongRoute(routePoints);
    _signalsByDispatch[dispatchId] = signals;
    await _firestore.collection('dispatches').doc(dispatchId).set({
      'routeSignalNodes': signals
          .map((signal) => {
                'id': signal.id,
                'latitude': signal.latitude,
                'longitude': signal.longitude,
              })
          .toList(),
      'routeSignalsUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

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
    required String driverUid,
    required Position position,
  }) async {
    await _firestore.collection('dispatches').doc(dispatchId).set({
      'status': 'ACTIVE',
      'driverLocation': GeoPoint(position.latitude, position.longitude),
      'driverLat': position.latitude,
      'driverLng': position.longitude,
      'driverHeading': position.heading,
      'driverSpeedMps': position.speed,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _createApproachingAlerts(dispatchId, driverUid, position);
  }

  Future<void> _createApproachingAlerts(
    String dispatchId,
    String driverUid,
    Position position,
  ) async {
    final signals = _signalsByDispatch[dispatchId] ?? const [];
    if (signals.isEmpty || position.heading < 0) return;
    final officers = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'traffic_police')
        .where('isVerified', isEqualTo: true)
        .where('isActive', isEqualTo: true)
        .get();
    for (final signal in signals) {
      if (!isApproachingIntersection(
        driverLat: position.latitude,
        driverLng: position.longitude,
        driverHeading: position.heading,
        signalLat: signal.latitude,
        signalLng: signal.longitude,
      )) {
        continue;
      }
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
      final signalToOfficer = Geolocator.distanceBetween(
        signal.latitude,
        signal.longitude,
        lat,
        lng,
      );
      if (signalToOfficer <= 250) {
        final alertId = 'ALT_${dispatchId}_${officer.id}_${signal.id}';
        final speed = position.speed > 1 ? position.speed : 8;
        await _firestore.collection('emergency_alerts').doc(alertId).set({
          'alertId': alertId,
          'policeUid': officer.id,
          'driverUid': driverUid,
          'dispatchId': dispatchId,
          'officerId': officer.id,
          'intersection': data['assignedIntersection'] ?? '',
          'intersectionName': data['assignedIntersection'] ?? '',
          'intersectionLocation': GeoPoint(signal.latitude, signal.longitude),
          'driverLocation': GeoPoint(position.latitude, position.longitude),
          'distanceMeters': distance,
          'estimatedArrivalMinutes': (distance / speed / 60).ceil(),
          'status': 'ACTIVE',
          'signalState': 'NORMAL',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }
    }
  }

  StreamSubscription<Position> trackDispatch({
    required String dispatchId,
    required String driverUid,
    required LocationSettings settings,
  }) =>
      Geolocator.getPositionStream(locationSettings: settings).listen(
        (position) => updateDispatchLocation(
          dispatchId: dispatchId,
          driverUid: driverUid,
          position: position,
        ),
      );
}
