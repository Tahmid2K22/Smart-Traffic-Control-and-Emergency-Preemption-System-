import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/intersection_point.dart';
import 'overpass_signal_service.dart';

class TrafficService {
  TrafficService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final _overpass = OverpassSignalService();
  final _signalsByDispatch = <String, List<TrafficSignal>>{};

  /// Requests clearance from officers; it never changes a signal directly.
  Future<int> requestEmergencyEscape({
    required String intersectionId,
    String? dispatchId,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Sign in as a driver first.');
    final driver = await _firestore.collection('users').doc(uid).get();
    final profile = driver.data();
    if (profile?['role'] != 'driver' || profile?['isApproved'] != true) {
      throw StateError(
        'Only approved ambulance drivers can request an emergency escape.',
      );
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError(
        'Turn on location services before requesting an escape.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      throw StateError('Allow location access before requesting an escape.');
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    if (DateTime.now().difference(position.timestamp).abs() >
            const Duration(seconds: 30) ||
        !position.accuracy.isFinite ||
        position.accuracy > 100) {
      throw StateError(
        'GPS is not accurate enough. Move to an open area and retry.',
      );
    }
    final intersectionRef = _firestore
        .collection('intersections')
        .doc(intersectionId);
    final officers = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'traffic_police')
        .get();

    // Re-read the intersection and recipients in the write transaction so an
    // admin disabling an intersection or an officer going offline is respected.
    return _firestore.runTransaction<int>((transaction) async {
      final snapshot = await transaction.get(intersectionRef);
      if (!snapshot.exists) {
        throw StateError('This intersection no longer exists.');
      }
      final intersection = IntersectionPoint.fromMap(
        snapshot.id,
        snapshot.data()!,
      );
      if (!intersection.isActive) {
        throw StateError('This intersection is disabled.');
      }
      final distance = intersection.distanceFrom(
        position.latitude,
        position.longitude,
      );
      if (!intersection.canRequestFrom(position.latitude, position.longitude)) {
        throw StateError(
          'You are ${distance.round()} m away. Move within 500 m to request an emergency escape.',
        );
      }
      final recipients = <String>[];
      for (final officer in officers.docs) {
        final current = (await transaction.get(officer.reference)).data();
        if (current == null ||
            current['role'] != 'traffic_police' ||
            current['isVerified'] != true ||
            current['isActive'] != true) {
          continue;
        }
        final location = current['intersectionLocation'];
        if (intersection.matchesOfficer(
          intersectionId: current['assignedIntersectionId'] as String?,
          assignedIntersection: current['assignedIntersection'] as String?,
          latitude: location is GeoPoint
              ? location.latitude
              : (current['intersectionLatitude'] as num?)?.toDouble(),
          longitude: location is GeoPoint
              ? location.longitude
              : (current['intersectionLongitude'] as num?)?.toDouble(),
        )) {
          recipients.add(officer.id);
        }
      }
      if (recipients.isEmpty) {
        throw StateError(
          'No active verified traffic officer is assigned to this intersection. No request was sent.',
        );
      }
      final alerts = <String, DocumentReference<Map<String, dynamic>>>{};
      for (final officerId in recipients) {
        final ref = _firestore
            .collection('emergency_alerts')
            .doc(
              'ESC_${uid}_${intersection.id}_${dispatchId ?? 'manual'}_$officerId',
            );
        final existing = (await transaction.get(ref)).data();
        final requestedAt = existing?['requestedAt'];
        // Do not reopen an officer-cleared/overridden alert on repeated taps.
        if (existing?['status'] == 'ACTIVE' ||
            (requestedAt is Timestamp &&
                DateTime.now().difference(requestedAt.toDate()) <
                    const Duration(minutes: 1))) {
          continue;
        }
        alerts[officerId] = ref;
      }
      if (alerts.isEmpty) {
        throw StateError(
          'An escape request was already sent. Please wait for the traffic officer.',
        );
      }
      final speed = position.speed > 1 ? position.speed : 8;
      for (final entry in alerts.entries) {
        final officerId = entry.key;
        final ref = entry.value;
        transaction.set(ref, {
          'alertId': ref.id,
          'type': 'EMERGENCY_ESCAPE',
          'source': 'DRIVER_REQUEST',
          'driverUid': uid,
          'driverName':
              profile?['name'] ?? profile?['fullName'] ?? 'Ambulance driver',
          'dispatchId': ?dispatchId,
          'officerId': officerId,
          'policeUid': officerId,
          'intersectionId': intersection.id,
          'intersection': intersection.name,
          'intersectionName': intersection.name,
          'intersectionLocation': GeoPoint(
            intersection.latitude,
            intersection.longitude,
          ),
          'driverLocation': GeoPoint(position.latitude, position.longitude),
          'distanceMeters': distance,
          'estimatedArrivalMinutes': (distance / speed / 60).ceil(),
          'status': 'ACTIVE',
          'signalState': 'NORMAL',
          'requestedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      return alerts.length;
    });
  }

  Future<void> prepareRoute({
    required String dispatchId,
    required List<LatLng> routePoints,
  }) async {
    final signals = await _overpass.findSignalsAlongRoute(routePoints);
    _signalsByDispatch[dispatchId] = signals;
    await _firestore.collection('dispatches').doc(dispatchId).set({
      'routeSignalNodes': signals
          .map(
            (signal) => {
              'id': signal.id,
              'latitude': signal.latitude,
              'longitude': signal.longitude,
            },
          )
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

  Stream<QuerySnapshot<Map<String, dynamic>>> activeDispatches() => _firestore
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
  }) => Geolocator.getPositionStream(locationSettings: settings).listen(
    (position) => updateDispatchLocation(
      dispatchId: dispatchId,
      driverUid: driverUid,
      position: position,
    ),
  );
}
