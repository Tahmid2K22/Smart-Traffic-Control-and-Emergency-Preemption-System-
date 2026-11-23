import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/intersection_point.dart';
import 'overpass_signal_service.dart';
import 'request_service.dart';
import 'traffic_rtdb_service.dart';
import 'user_service.dart';

/// Who ended an emergency escape — recorded on the alert for the audit trail.
enum EscapeReleaseSource {
  /// The ambulance drove out of the escape ring (~1 km) — sent automatically.
  autoRange,

  /// The driver tapped release.
  driver,

  /// A traffic officer tapped release.
  police;

  String get label => switch (this) {
    EscapeReleaseSource.autoRange => 'AUTO_RANGE',
    EscapeReleaseSource.driver => 'DRIVER',
    EscapeReleaseSource.police => 'POLICE',
  };
}

/// An emergency escape that is currently latching a traffic light green.
///
/// The board has no GPS, so the "leave the 1 km ring" check lives here: the
/// app watches the ambulance's position and sends `release` as soon as it is
/// back outside [IntersectionPoint.escapeRequestRadiusMeters]. The same
/// release path is used for a manual release by the driver or an officer.
class ActiveEscape {
  const ActiveEscape({
    required this.intersectionId,
    required this.intersectionName,
    required this.latitude,
    required this.longitude,
    required this.dispatchId,
    required this.approachDirection,
    required this.startedAt,
  });

  final String intersectionId;
  final String intersectionName;
  final double latitude;
  final double longitude;
  final String dispatchId;
  final String approachDirection;
  final DateTime startedAt;

  /// Metres from the ambulance at ([lat], [lng]) to the escaped intersection.
  double distanceFrom(double lat, double lng) =>
      Geolocator.distanceBetween(latitude, longitude, lat, lng);
}

/// What happened after an escape request was submitted.
class EmergencyEscapeResult {
  const EmergencyEscapeResult({
    required this.officersNotified,
    required this.approachDirection,
    required this.lightCommandSent,
    this.boardLatched = false,
    this.boardApproachLight = 'unknown',
    this.boardOnline = false,
  });

  /// Officers assigned to the intersection that were recorded for
  /// notification. May be zero — the light command does not depend on them.
  final int officersNotified;

  /// Approach arm sent to the light ('north' | 'east' | 'south' | 'west').
  final String approachDirection;

  /// Whether the RTDB preemption command write succeeded.
  final bool lightCommandSent;

  /// Whether the board's own status confirms the ambulance latch is active.
  final bool boardLatched;

  /// The colour the board reports for the approach arm
  /// ('green' | 'yellow' | 'red' | 'unknown').
  final String boardApproachLight;

  /// Whether the board's status heartbeat is recent (board online).
  final bool boardOnline;
}

class TrafficService {
  TrafficService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final _overpass = OverpassSignalService();
  final _signalsByDispatch = <String, List<TrafficSignal>>{};

  /// The emergency escape currently holding a light green, if any. Static
  /// because only one can be held at a time and every page (driver dashboard,
  /// intersection search, officer page) must agree on it.
  static final ValueNotifier<ActiveEscape?> activeEscape =
      ValueNotifier<ActiveEscape?>(null);

  static Timer? _escapeWatchTimer;
  static bool _releaseInFlight = false;

  /// Starts watching a freshly latched escape so it releases itself as soon
  /// as the ambulance leaves the ~1 km ring.
  static void _watchEscape(ActiveEscape escape) {
    activeEscape.value = escape;
    _escapeWatchTimer?.cancel();
    _escapeWatchTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkEscapeRange(),
    );
  }

  /// Auto-release check: outside [IntersectionPoint.escapeRequestRadiusMeters]
  /// the light goes straight back to its normal AUTO cycle.
  static Future<void> _checkEscapeRange() async {
    final escape = activeEscape.value;
    if (escape == null) {
      _escapeWatchTimer?.cancel();
      _escapeWatchTimer = null;
      return;
    }
    if (_releaseInFlight) return;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      final distance = escape.distanceFrom(
        position.latitude,
        position.longitude,
      );
      if (distance <= IntersectionPoint.escapeRequestRadiusMeters) return;
      await TrafficService().releaseEscape(
        intersectionId: escape.intersectionId,
        source: EscapeReleaseSource.autoRange,
      );
    } catch (_) {
      // No fix this tick — try again shortly. The board's own max-hold
      // watchdog still frees the light if the phone goes away entirely.
    }
  }

  /// Ends an emergency escape: sends `release` to the board (which resumes
  /// its AUTO cycle) and closes every ACTIVE escape record so officer alert
  /// streams clear and the audit trail records who released it.
  Future<void> releaseEscape({
    required String intersectionId,
    EscapeReleaseSource source = EscapeReleaseSource.driver,
  }) async {
    if (_releaseInFlight) return;
    _releaseInFlight = true;
    try {
      try {
        await TrafficRtdbService(
          intersectionId: intersectionId,
        ).releaseAmbulance();
      } catch (_) {
        // Best-effort: the firmware's max-hold watchdog recovers anyway.
      }
      try {
        final snapshot = await _firestore
            .collection('emergency_alerts')
            .where('intersectionId', isEqualTo: intersectionId)
            .where('type', isEqualTo: 'EMERGENCY_ESCAPE')
            .where('status', isEqualTo: 'ACTIVE')
            .get();
        if (snapshot.docs.isNotEmpty) {
          final batch = _firestore.batch();
          for (final doc in snapshot.docs) {
            batch.update(doc.reference, {
              'status': 'RELEASED',
              'signalState': 'ESCAPE_RELEASED',
              'releasedBy': source.label,
              'releasedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
          await batch.commit();
        }
      } catch (_) {
        // The audit update is best-effort — the light is already released.
      }
      if (activeEscape.value?.intersectionId == intersectionId) {
        activeEscape.value = null;
      }
    } finally {
      _releaseInFlight = false;
      if (activeEscape.value == null) {
        _escapeWatchTimer?.cancel();
        _escapeWatchTimer = null;
      }
    }
  }

  /// Releases whatever escape is currently latched (no-op if there is none).
  static Future<void> releaseActiveEscape(EscapeReleaseSource source) async {
    final escape = activeEscape.value;
    if (escape == null) return;
    await TrafficService().releaseEscape(
      intersectionId: escape.intersectionId,
      source: source,
    );
  }

  /// Requests an emergency escape. The request goes straight to the traffic
  /// light (RTDB preemption — the ambulance's approach arm goes green); no
  /// assigned traffic officer is required. Officers assigned to the
  /// intersection, if any, are recorded on `emergency_alerts` for their
  /// in-app alert stream, and a Cloud Function sends them an FCM push.
  Future<EmergencyEscapeResult> requestEmergencyEscape({
    required String intersectionId,
    String? dispatchId,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Sign in as a driver first.');
    final profile = await UserService.instance.fetch(uid);
    if (profile?.role != 'driver' || profile?.isApproved != true) {
      throw StateError(
        'Only approved ambulance drivers can request an emergency escape.',
      );
    }
    // Escape requests are only available during an active trip. Requiring the
    // dispatch id keeps them tied to a real ride, so the light cannot be
    // preempted from a parked/idle ambulance.
    final rideId = dispatchId?.trim() ?? '';
    if (rideId.isEmpty ||
        !await RequestService.isActiveRideForCurrentDriver(rideId)) {
      throw StateError(
        'Emergency escape is only available during an active ambulance trip.',
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
    final officers = await UserService.instance.fetchOfficers();

    // Re-read the intersection and recipients in the write transaction so an
    // admin disabling an intersection is respected and repeat taps within a
    // minute of a successful command are ignored (spam guard).
    final plan = await _firestore
        .runTransaction<_EscapePlan>((transaction) async {
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
          'You are ${distance.round()} m away. Move within '
          '${IntersectionPoint.escapeRequestRadiusMeters.round()} m to '
          'request an emergency escape.',
        );
      }
      final approachDirection = _approachDirection(intersection, position);
      // Primary record: audit trail + dedup for the light command. No
      // specific officer is attached — the request targets the light.
      final primaryId = 'ESC_${uid}_${intersection.id}_$rideId';
      final primaryRef = _firestore
          .collection('emergency_alerts')
          .doc(primaryId);
      final existing = (await transaction.get(primaryRef)).data();
      final requestedAt = existing?['requestedAt'];
      final recent =
          requestedAt is Timestamp &&
          DateTime.now().difference(requestedAt.toDate()) <
              const Duration(minutes: 1);
      // A recent request whose light command went through blocks repeats.
      // If the light did not confirm, the driver may retry immediately.
      if (recent && existing?['lightCommandSent'] == true) {
        throw StateError(
          'An escape request was already sent. The light should be '
          'switching for your approach.',
        );
      }

      // Officers assigned to this intersection (if any). Optional: an empty
      // list still allows the request because the light is targeted directly.
      final recipients = <String>[];
      for (final officer in officers) {
        if (!officer.isVerifiedOfficer || !officer.isActive) continue;
        if (intersection.matchesOfficer(
          intersectionId: officer.assignedIntersectionId,
          assignedIntersection: officer.assignedIntersection,
          latitude: officer.intersectionLatitude,
          longitude: officer.intersectionLongitude,
        )) {
          recipients.add(officer.uid);
        }
      }

      final speed = position.speed > 1 ? position.speed : 8;
      final arrivalMinutes = (distance / speed / 60).ceil();
      transaction.set(primaryRef, {
        'alertId': primaryId,
        'type': 'EMERGENCY_ESCAPE',
        'source': 'DRIVER_REQUEST',
        'driverUid': uid,
        'driverName':
            profile?.name ?? profile?.fullName ?? 'Ambulance driver',
        'dispatchId': rideId,
        'officerId': '',
        'intersectionId': intersection.id,
        'intersection': intersection.name,
        'intersectionName': intersection.name,
        'intersectionLocation': GeoPoint(
          intersection.latitude,
          intersection.longitude,
        ),
        'driverLocation': GeoPoint(position.latitude, position.longitude),
        'distanceMeters': distance,
        'estimatedArrivalMinutes': arrivalMinutes,
        'approachDirection': approachDirection,
        'notifiedOfficerIds': recipients,
        'status': 'ACTIVE',
        'signalState': 'ESCAPE_REQUESTED',
        'lightCommandSent': false,
        'requestedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Per-officer alert docs keep the officers' in-app alert stream working.
      for (final officerId in recipients) {
        final ref = _firestore
            .collection('emergency_alerts')
            .doc(
              'ESC_${uid}_${intersection.id}_${rideId}_$officerId',
            );
        final officerAlert = (await transaction.get(ref)).data();
        final officerRequestedAt = officerAlert?['requestedAt'];
        // Do not reopen an officer-cleared/overridden alert on repeated taps.
        if (officerAlert?['status'] == 'ACTIVE' ||
            (officerRequestedAt is Timestamp &&
                DateTime.now()
                        .difference(officerRequestedAt.toDate()) <
                    const Duration(minutes: 1))) {
          continue;
        }
        transaction.set(ref, {
          'alertId': ref.id,
          'type': 'EMERGENCY_ESCAPE',
          'source': 'DRIVER_REQUEST',
          'driverUid': uid,
          'driverName':
              profile?.name ?? profile?.fullName ?? 'Ambulance driver',
          'dispatchId': rideId,
          'officerId': officerId,
          'policeUid': officerId,
          'primaryAlertId': primaryId,
          'approachDirection': approachDirection,
          'intersectionId': intersection.id,
          'intersection': intersection.name,
          'intersectionName': intersection.name,
          'intersectionLocation': GeoPoint(
            intersection.latitude,
            intersection.longitude,
          ),
          'driverLocation': GeoPoint(position.latitude, position.longitude),
          'distanceMeters': distance,
          'estimatedArrivalMinutes': arrivalMinutes,
          'status': 'ACTIVE',
          'signalState': 'NORMAL',
          'requestedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      return _EscapePlan(
        primaryId: primaryId,
        approachDirection: approachDirection,
        officersNotified: recipients.length,
        intersectionName: intersection.name,
        latitude: intersection.latitude,
        longitude: intersection.longitude,
      );
    });

    // Send the preemption command to the light. On failure the primary
    // record keeps lightCommandSent = false, so the driver can retry at once.
    final light = TrafficRtdbService(intersectionId: intersectionId);
    try {
      await light.ambulancePreempt(plan.approachDirection);
    } on Exception {
      return EmergencyEscapeResult(
        officersNotified: plan.officersNotified,
        approachDirection: plan.approachDirection,
        lightCommandSent: false,
      );
    }

    // The command is on its way. Watch the ambulance's position so the light
    // releases itself the moment it leaves the ~1 km escape ring — the board
    // has no GPS, so this is the only place the range check can happen.
    _watchEscape(
      ActiveEscape(
        intersectionId: intersectionId,
        intersectionName: plan.intersectionName,
        latitude: plan.latitude,
        longitude: plan.longitude,
        dispatchId: rideId,
        approachDirection: plan.approachDirection,
        startedAt: DateTime.now(),
      ),
    );

    // The command write gives no acknowledgement — the board may be offline
    // or mid-cycle. Read its status to confirm the latch actually happened.
    // The board publishes status immediately on latch; one short re-check
    // covers the moment it was mid-transition when the command arrived.
    var state = await light.readStatus();
    if (state == null || !state.ambulanceLatched) {
      await Future<void>.delayed(const Duration(seconds: 3));
      state = await light.readStatus();
    }
    final latched = state?.ambulanceLatched ?? false;
    final online = state?.isFresh ?? false;
    final approachLight = state?.lightFor(plan.approachDirection) ?? 'unknown';

    await _firestore
        .collection('emergency_alerts')
        .doc(plan.primaryId)
        .update({
      'lightCommandSent': true,
      'lightCommandAt': FieldValue.serverTimestamp(),
      'boardLatched': latched,
      'boardOnline': online,
      'boardApproachLight': approachLight,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return EmergencyEscapeResult(
      officersNotified: plan.officersNotified,
      approachDirection: plan.approachDirection,
      lightCommandSent: true,
      boardLatched: latched,
      boardApproachLight: approachLight,
      boardOnline: online,
    );
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
    final officers = await UserService.instance.fetchOfficers(onlyActive: true);
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
      for (final officer in officers) {
        final lat = officer.intersectionLatitude;
        final lng = officer.intersectionLongitude;
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
          final alertId = 'ALT_${dispatchId}_${officer.uid}_${signal.id}';
          final speed = position.speed > 1 ? position.speed : 8;
          await _firestore.collection('emergency_alerts').doc(alertId).set({
            'alertId': alertId,
            'policeUid': officer.uid,
            'driverUid': driverUid,
            'dispatchId': dispatchId,
            'officerId': officer.uid,
            'intersection': officer.assignedIntersection ?? '',
            'intersectionName': officer.assignedIntersection ?? '',
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

  /// Bearing from the ambulance to the intersection, snapped to the nearest
  /// approach arm — which signal the ambulance obeys when it arrives.
  /// Same convention as the driver dashboard's auto-preemption: the arm is
  /// where the ambulance comes FROM, i.e. opposite of bearing-to-intersection.
  ///
  /// When the ambulance is MOVING with a valid GPS heading, the heading is
  /// used instead: at close range (or stationary) the bearing to the
  /// junction is nearly meaningless and can snap to the wrong arm.
  String _approachDirection(IntersectionPoint point, Position position) {
    const dirs = ['north', 'east', 'south', 'west'];
    double fromArmBearing;
    if (position.speed > 1 && position.heading >= 0) {
      // Travel direction → the arm the ambulance comes FROM is opposite.
      fromArmBearing = (position.heading + 180) % 360;
    } else {
      final dLng = (point.longitude - position.longitude) * math.pi / 180;
      final lat1 = position.latitude * math.pi / 180;
      final lat2 = point.latitude * math.pi / 180;
      final y = math.sin(dLng) * math.cos(lat2);
      final x = math.cos(lat1) * math.sin(lat2) -
          math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
      final bearing = (math.atan2(y, x) * 180 / math.pi + 360) % 360;
      fromArmBearing = (bearing + 180) % 360;
    }
    return dirs[(((fromArmBearing + 45) ~/ 90)) % 4];
  }
}

/// Internal plan produced by the escape-request transaction, before the
/// RTDB light command is attempted.
class _EscapePlan {
  const _EscapePlan({
    required this.primaryId,
    required this.approachDirection,
    required this.officersNotified,
    required this.intersectionName,
    required this.latitude,
    required this.longitude,
  });

  final String primaryId;
  final String approachDirection;
  final int officersNotified;
  final String intersectionName;
  final double latitude;
  final double longitude;
}
