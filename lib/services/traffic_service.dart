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
import 'supabase_service.dart';
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

/// An escape currently latching a light green; app handles the 1 km release.
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

    /// Officers notified (may be zero; light command is independent).
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

/// Active emergency escape alert targeted at a signed-in traffic officer.
class OfficerEscapeAlert {
  const OfficerEscapeAlert({
    required this.alertId,
    required this.intersectionId,
    required this.intersectionName,
    required this.driverName,
    required this.approachDirection,
    this.distanceMeters,
    this.estimatedArrivalMinutes,
    this.requestedAt,
  });

  final String alertId;
  final String intersectionId;
  final String intersectionName;
  final String driverName;
  final String approachDirection;
  final int? distanceMeters;
  final int? estimatedArrivalMinutes;
  final DateTime? requestedAt;

  static OfficerEscapeAlert fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final requested = data['requestedAt'];
    final intersection =
        (data['intersectionName'] as String?)?.trim().isNotEmpty == true
        ? (data['intersectionName'] as String).trim()
        : ((data['intersection'] as String?)?.trim() ?? 'Intersection');
    final driver = (data['driverName'] as String?)?.trim();
    final direction = (data['approachDirection'] as String?)?.trim();
    return OfficerEscapeAlert(
      alertId: doc.id,
      intersectionId: (data['intersectionId'] as String?) ?? '',
      intersectionName: intersection,
      driverName: (driver != null && driver.isNotEmpty)
          ? driver
          : 'Ambulance driver',
      approachDirection: (direction != null && direction.isNotEmpty)
          ? direction
          : 'unknown',
      distanceMeters: (data['distanceMeters'] as num?)?.round(),
      estimatedArrivalMinutes:
          (data['estimatedArrivalMinutes'] as num?)?.round(),
      requestedAt: requested is Timestamp ? requested.toDate() : null,
    );
  }
}

class TrafficService {
  TrafficService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final _overpass = OverpassSignalService();
  final _signalsByDispatch = <String, List<TrafficSignal>>{};

    /// Current escape (one at a time, shared across pages).
  static final ValueNotifier<ActiveEscape?> activeEscape =
      ValueNotifier<ActiveEscape?>(null);

  static Timer? _escapeWatchTimer;
  static bool _releaseInFlight = false;

  /// Watches a latched escape to auto-release outside ~1 km.
  static void _watchEscape(ActiveEscape escape) {
    activeEscape.value = escape;
    _escapeWatchTimer?.cancel();
    _escapeWatchTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkEscapeRange(),
    );
  }

  /// Auto-release when outside escape radius.
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
      // No fix this tick — retry shortly; board watchdog frees light if phone dies.
    }
  }

  /// Ends an escape: releases the board and closes ACTIVE records (audit trail).
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

  /// Requests an escape: preempts the light green for the approach arm; notifies assigned officers via FCM.
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
    // Block a second escape while one is already active on a different board.
    final existing = activeEscape.value;
    if (existing != null && existing.intersectionId != intersectionId) {
      throw StateError(
        'Release the active escape at ${existing.intersectionName} before '
        'requesting another.',
      );
    }
    // Escape only during active trip (dispatch id ties it to a real ride).
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

    // Re-read in transaction: respect disabled intersections; spam-guard repeat taps.
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
      // Primary record: audit + dedup for the light command.
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
      // Recent successful command blocks repeats; retry allowed if it failed.
      if (recent && existing?['lightCommandSent'] == true) {
        throw StateError(
          'An escape request was already sent. The light should be '
          'switching for your approach.',
        );
      }

      // Assigned officers (optional); empty list still allows the request.
      final recipients = <String>[];
      for (final officer in officers) {
        if (!officer.isVerifiedOfficer) continue;
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
      final driverDisplayName =
          profile?.name ?? profile?.fullName ?? 'Ambulance driver';
      transaction.set(primaryRef, {
        'alertId': primaryId,
        'type': 'EMERGENCY_ESCAPE',
        'source': 'DRIVER_REQUEST',
        'driverUid': uid,
        'driverName': driverDisplayName,
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

      // Per-officer alert docs for officers' in-app alert stream.
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
          'driverName': driverDisplayName,
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
        driverName: driverDisplayName,
        distanceMeters: distance,
        estimatedArrivalMinutes: arrivalMinutes,
      );
    });

    // Send preemption; failure keeps lightCommandSent false for retry.
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

    // Watch ambulance position to auto-release outside ~1 km (board has no GPS).
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

    // Read status to confirm latch (board gives no ack); re-check once for mid-transition.
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

    if (plan.officersNotified > 0) {
      unawaited(
        _notifyEscapeViaSupabase(
          alertId: plan.primaryId,
          intersectionId: intersectionId,
          intersectionName: plan.intersectionName,
          driverName: plan.driverName,
          approachDirection: plan.approachDirection,
          distanceMeters: plan.distanceMeters,
          estimatedArrivalMinutes: plan.estimatedArrivalMinutes,
        ),
      );
    }

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

  /// Active escape alerts for [uid], filtered client-side to avoid needing
  /// composite Firestore indexes on Spark plans.
  Stream<List<OfficerEscapeAlert>> activeAlertsForOfficer(String uid) {
    if (uid.isEmpty) return Stream<List<OfficerEscapeAlert>>.value(const []);
    return _firestore
        .collection('emergency_alerts')
        .where('officerId', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
          final alerts = snapshot.docs
              .where((doc) {
                final data = doc.data();
                return data['status'] == 'ACTIVE' &&
                    data['type'] == 'EMERGENCY_ESCAPE';
              })
              .map(OfficerEscapeAlert.fromDoc)
              .toList()
            ..sort((a, b) {
              final at = a.requestedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bt = b.requestedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bt.compareTo(at);
            });
          return alerts;
        });
  }

  Future<void> _notifyEscapeViaSupabase({
    required String alertId,
    required String intersectionId,
    required String intersectionName,
    required String driverName,
    required String approachDirection,
    required double distanceMeters,
    required int estimatedArrivalMinutes,
  }) async {
    if (!supabaseReady) return;
    try {
      await sb.functions.invoke(
        'notify-emergency-escape',
        body: {
          'alertId': alertId,
          'intersectionId': intersectionId,
          'intersectionName': intersectionName,
          'driverName': driverName,
          'approachDirection': approachDirection,
          'distanceMeters': distanceMeters.round(),
          'estimatedArrivalMinutes': estimatedArrivalMinutes,
        },
      );
    } catch (_) {
      // Optional free-tier Supabase Edge Function: ignore if not deployed yet.
    }
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
    final officers = await UserService.instance.fetchOfficers();
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

  /// Snaps ambulance bearing to nearest approach arm (opposite of bearing-to-junction); uses GPS heading when moving.
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

/// Plan from the escape transaction, before RTDB command.
class _EscapePlan {
  const _EscapePlan({
    required this.primaryId,
    required this.approachDirection,
    required this.officersNotified,
    required this.intersectionName,
    required this.latitude,
    required this.longitude,
    required this.driverName,
    required this.distanceMeters,
    required this.estimatedArrivalMinutes,
  });

  final String primaryId;
  final String approachDirection;
  final int officersNotified;
  final String intersectionName;
  final double latitude;
  final double longitude;
  final String driverName;
  final double distanceMeters;
  final int estimatedArrivalMinutes;
}
