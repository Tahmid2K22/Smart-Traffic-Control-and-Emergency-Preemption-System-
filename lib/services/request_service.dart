import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:math' as math;

import '../models/message_model.dart';
import '../models/request_model.dart';
import 'supabase_service.dart';

/// Ambulance request ops over Supabase (Firebase Auth for identity).
class RequestService {
  RequestService._();

  /// Current time as a UTC ISO string. The columns are timestamptz and Postgres
  /// reads an offset-less timestamp as UTC, so a local toIso8601String() would
  /// be off by the device's timezone offset.
  static String _utcNowIso() => DateTime.now().toUtc().toIso8601String();

  // ── Driver helpers ──────────────────────────────────────────────────────────

  /// Upsert driver row (isApproved mirrors Firestore admin decision).
  static Future<void> upsertDriverProfile({
    required String firebaseUid,
    required String name,
    required String phone,
    required String vehicleType,
    required String vehicleNumber,
    bool isApproved = false,
  }) async {
    if (!supabaseReady) return;
    await sb.from(SupabaseTables.drivers).upsert({
      'firebase_uid': firebaseUid,
      'name': name,
      'phone': phone,
      'vehicle_type': vehicleType,
      'vehicle_number': vehicleNumber,
      'is_approved': isApproved,
    }, onConflict: 'firebase_uid');
  }

  static Future<DriverProfile?> getMyDriverProfile() async {
    if (!supabaseReady) return null;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final response = await sb
        .from(SupabaseTables.drivers)
        .select()
        .eq('firebase_uid', uid)
        .maybeSingle();
    if (response == null) return null;
    return DriverProfile.fromMap(response);
  }

  static Future<void> setOnlineStatus({
    required String driverId,
    required bool isOnline,
  }) async {
    if (!supabaseReady) return;
    await sb
        .from(SupabaseTables.drivers)
        .update({'is_online': isOnline})
        .eq('id', driverId);
  }

  static Future<void> updateDriverLocation({
    required String driverId,
    required double lat,
    required double lng,
    String? currentRequestId,
  }) async {
    if (!supabaseReady) return;
    await sb
        .from(SupabaseTables.drivers)
        .update({
          'current_lat': lat,
          'current_lng': lng,
          'updated_at': _utcNowIso(),
        })
        .eq('id', driverId);
  }

  // ── User request operations ─────────────────────────────────────────────────

  /// Create a request, return its UUID.
  static Future<String> createRequest({
    required String userFirebaseUid,
    required String userName,
    required String userPhone,
    required String ambulanceType,
    required double pickupLat,
    required double pickupLng,
    required String pickupAddress,
    required double destinationLat,
    required double destinationLng,
    required String destinationAddress,
    required int estimatedFare,
    required double distanceKm,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != userFirebaseUid) {
      throw StateError('Log in to your account before booking an ambulance.');
    }
    if (!supabaseReady) throw StateError('Supabase is not initialised.');
    try {
      final response = await sb
          .from(SupabaseTables.requests)
          .insert({
            'user_firebase_uid': userFirebaseUid,
            'user_name': userName,
            'user_phone': userPhone,
            'status': 'pending',
            'ambulance_type': ambulanceType,
            'pickup_lat': pickupLat,
            'pickup_lng': pickupLng,
            'pickup_address': pickupAddress,
            'destination_lat': destinationLat,
            'destination_lng': destinationLng,
            'destination_address': destinationAddress,
            'estimated_fare': estimatedFare,
            'distance_km': distanceKm,
          })
          .select('id')
          .single();
      final id = response['id']?.toString();
      if (id == null || id.isEmpty) {
        throw StateError('The dispatch server returned no booking id.');
      }
      return id;
    } on PostgrestException catch (error) {
      throw StateError(
        'Dispatch server rejected the booking: ${error.message}',
      );
    }
  }

  /// All requests for current user.
  static Future<List<AmbulanceRequest>> getUserRequests() async {
    if (!supabaseReady) return [];
    await expireStalePendingRequests();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];
    final rows = await sb
        .from(SupabaseTables.requests)
        .select('*, drivers(name, phone, current_lat, current_lng)')
        .eq('user_firebase_uid', uid)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => AmbulanceRequest.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Cancel a request (driver redispatch or user cancel).
  static Future<void> cancelRequest(
    String requestId, {
    String? driverId,
  }) async {
    if (!supabaseReady) {
      throw StateError('Supabase is not initialised.');
    }

    // A driver cancelling an accepted trip is not a final cancellation.
    // Put the trip back into the pending pool and restart its 10-minute search.
    if (driverId != null) {
      final redispatched = await sb
          .from(SupabaseTables.requests)
          .update({
            'status': RequestStatus.pending.toDbString(),
            'driver_id': null,
            'accepted_at': null,
            'completed_at': null,
            'created_at': _utcNowIso(),
          })
          .eq('id', requestId)
          .eq('driver_id', driverId)
          .inFilter('status', [
            RequestStatus.accepted.toDbString(),
            RequestStatus.enRoute.toDbString(),
            RequestStatus.arrived.toDbString(),
          ])
          .select('id');
      if (redispatched.isEmpty) {
        throw StateError('This trip is no longer available for you to cancel.');
      }
      await sb
          .from(SupabaseTables.drivers)
          .update({'current_request_id': null})
          .eq('id', driverId);
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('Log in to your account before cancelling a trip.');
    }
    final cancellableStatuses = [
      RequestStatus.pending.toDbString(),
      RequestStatus.accepted.toDbString(),
      RequestStatus.enRoute.toDbString(),
      RequestStatus.arrived.toDbString(),
    ];
    final cancelled = await sb
        .from(SupabaseTables.requests)
        .update({'status': RequestStatus.cancelled.toDbString()})
        .eq('id', requestId)
        .eq('user_firebase_uid', uid)
        .inFilter('status', cancellableStatuses)
        .select('id');
    if (cancelled.isEmpty) {
      final current = await sb
          .from(SupabaseTables.requests)
          .select('status')
          .eq('id', requestId)
          .maybeSingle();
      final currentStatus = current?['status'] as String?;
      if (currentStatus != RequestStatus.cancelled.toDbString()) {
        throw StateError(
          currentStatus == null
              ? 'This trip could not be found.'
              : 'This trip is no longer available to cancel (status: $currentStatus).',
        );
      }
    }
    // Whichever driver held the trip is free again.
    await sb
        .from(SupabaseTables.drivers)
        .update({'current_request_id': null})
        .eq('current_request_id', requestId);
  }

  /// Expire a pending request on search timeout; false if a driver won the race.
  static Future<bool> expirePendingRequest(String requestId) async {
    if (!supabaseReady) {
      throw StateError('Supabase is not initialised.');
    }
    final expired = await sb
        .from(SupabaseTables.requests)
        .update({'status': RequestStatus.cancelled.toDbString()})
        .eq('id', requestId)
        .eq('status', RequestStatus.pending.toDbString())
        .select('id');
    return expired.isNotEmpty;
  }

  /// Expire stale pending requests (>10 min); works after restart/reconnect.
  static Future<int> expireStalePendingRequests() async {
    if (!supabaseReady) return 0;
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 10))
        .toIso8601String();
    final expired = await sb
        .from(SupabaseTables.requests)
        .update({'status': RequestStatus.cancelled.toDbString()})
        .eq('status', RequestStatus.pending.toDbString())
        .lt('created_at', cutoff)
        .select('id');
    return (expired as List).length;
  }

  // ── Driver accept / reject / complete ───────────────────────────────────────

  static Future<void> acceptRequest({
    required String requestId,
    required String driverId,
  }) async {
    if (!supabaseReady) {
      throw StateError('Supabase is not initialised.');
    }
    final accepted = await sb
        .from(SupabaseTables.requests)
        .update({
          'driver_id': driverId,
          'status': RequestStatus.accepted.toDbString(),
          'accepted_at': _utcNowIso(),
        })
        .eq('id', requestId)
        .eq('status', RequestStatus.pending.toDbString())
        .select('id')
        .maybeSingle();
    if (accepted == null) {
      throw StateError('This request has already been accepted or cancelled.');
    }

    await sb
        .from(SupabaseTables.drivers)
        .update({'current_request_id': requestId})
        .eq('id', driverId);
  }

  static Future<void> markArrived(String requestId) async {
    if (!supabaseReady) {
      throw StateError('Supabase is not initialised.');
    }
    final updated = await sb
        .from(SupabaseTables.requests)
        .update({'status': RequestStatus.arrived.toDbString()})
        .eq('id', requestId)
        .inFilter('status', [
          RequestStatus.accepted.toDbString(),
          RequestStatus.enRoute.toDbString(),
        ])
        .select('id');
    if (updated.isEmpty) {
      throw StateError(
        'The trip cannot be marked arrived in its current state.',
      );
    }
  }

  static Future<void> completeRequest({
    required String requestId,
    required String driverId,
  }) async {
    if (!supabaseReady) {
      throw StateError('Supabase is not initialised.');
    }
    final updated = await sb
        .from(SupabaseTables.requests)
        .update({
          'status': RequestStatus.completed.toDbString(),
          'completed_at': _utcNowIso(),
        })
        .eq('id', requestId)
        .inFilter('status', [
          RequestStatus.accepted.toDbString(),
          RequestStatus.enRoute.toDbString(),
          RequestStatus.arrived.toDbString(),
        ])
        .select('id');
    if (updated.isEmpty) {
      throw StateError('The trip cannot be completed in its current state.');
    }

    await sb
        .from(SupabaseTables.drivers)
        .update({'current_request_id': null})
        .eq('id', driverId);
  }

  // ── Real-time streams ───────────────────────────────────────────────────────

  /// Stream of all pending requests (incoming jobs).
  static Stream<List<AmbulanceRequest>> streamPendingRequests() {
    if (!supabaseReady) return const Stream.empty();
    expireStalePendingRequests();
    return sb
        .from(SupabaseTables.requests)
        .stream(primaryKey: ['id'])
        .eq('status', 'pending')
        .order('created_at', ascending: false)
        .map((rows) => rows.map(AmbulanceRequest.fromMap).toList());
  }

  /// Stream of a specific request (tracking).
  static Stream<AmbulanceRequest?> streamRequest(String requestId) {
    if (!supabaseReady) return const Stream.empty();
    return sb
        .from(SupabaseTables.requests)
        .stream(primaryKey: ['id'])
        .eq('id', requestId)
        .asyncMap((rows) async {
          if (rows.isEmpty) return null;
          final row = Map<String, dynamic>.from(rows.first);
          final driverId = row['driver_id'] as String?;
          if (driverId != null) {
            final driver = await sb
                .from(SupabaseTables.drivers)
                .select('name, phone, current_lat, current_lng')
                .eq('id', driverId)
                .maybeSingle();
            if (driver != null) row['drivers'] = driver;
          }
          return AmbulanceRequest.fromMap(row);
        });
  }

  /// Read request + driver GPS (coords change independently of request row).
  static Future<AmbulanceRequest?> getRequest(String requestId) async {
    if (!supabaseReady) return null;
    final row = await sb
        .from(SupabaseTables.requests)
        .select('*, drivers(name, phone, current_lat, current_lng)')
        .eq('id', requestId)
        .maybeSingle();
    return row == null
        ? null
        : AmbulanceRequest.fromMap(Map<String, dynamic>.from(row));
  }

  /// Count online ambulances in dispatch radius (grows as request waits).
  static Stream<int> streamNearbyDriverCount({
    required double pickupLat,
    required double pickupLng,
    required DateTime requestedAt,
  }) {
    if (!supabaseReady) return const Stream.empty();
    return sb
        .from(SupabaseTables.drivers)
        .stream(primaryKey: ['id'])
        .eq('is_online', true)
        .map((rows) {
          final radiusKm = dispatchRadiusKm(requestedAt);
          return rows.where((row) {
            final lat = (row['current_lat'] as num?)?.toDouble();
            final lng = (row['current_lng'] as num?)?.toDouble();
            return lat != null &&
                lng != null &&
                _distanceKm(pickupLat, pickupLng, lat, lng) <= radiusKm;
          }).length;
        });
  }

  static double dispatchRadiusKm(DateTime requestedAt) {
    final waited = DateTime.now().difference(requestedAt).inSeconds;
    if (waited < 15) return 5;
    if (waited < 35) return 10;
    if (waited < 60) return 20;
    return 50;
  }

  static double distanceKm({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) => _distanceKm(fromLat, fromLng, toLat, toLng);

  static double _distanceKm(
    double fromLat,
    double fromLng,
    double toLat,
    double toLng,
  ) {
    const earthRadiusKm = 6371.0;
    final latDelta = (toLat - fromLat) * math.pi / 180;
    final lngDelta = (toLng - fromLng) * math.pi / 180;
    final fromLatitude = fromLat * math.pi / 180;
    final toLatitude = toLat * math.pi / 180;
    final a =
        math.sin(latDelta / 2) * math.sin(latDelta / 2) +
        math.cos(fromLatitude) *
            math.cos(toLatitude) *
            math.sin(lngDelta / 2) *
            math.sin(lngDelta / 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Stream of the driver's active requests.
  static Stream<AmbulanceRequest?> streamDriverActiveRequest(String driverId) {
    if (!supabaseReady) return const Stream.empty();
    return sb
        .from(SupabaseTables.requests)
        .stream(primaryKey: ['id'])
        .eq('driver_id', driverId)
        .order('accepted_at', ascending: false)
        .map((rows) {
          final activeRows = rows.where(
            (row) => [
              RequestStatus.accepted.toDbString(),
              RequestStatus.enRoute.toDbString(),
              RequestStatus.arrived.toDbString(),
            ].contains(row['status']),
          );
          return activeRows.isEmpty
              ? null
              : AmbulanceRequest.fromMap(activeRows.first);
        });
  }

  /// Whether requestId is an active ride owned by signed-in driver (gates escape).
  static Future<bool> isActiveRideForCurrentDriver(String requestId) async {
    if (!supabaseReady) return false;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final driver = await sb
        .from(SupabaseTables.drivers)
        .select('id')
        .eq('firebase_uid', uid)
        .maybeSingle();
    if (driver == null) return false;
    final row = await sb
        .from(SupabaseTables.requests)
        .select('id, driver_id, status')
        .eq('id', requestId)
        .maybeSingle();
    if (row == null) return false;
    final status = row['status'] as String?;
    return row['driver_id'] == driver['id'] &&
        (status == 'accepted' || status == 'en_route' || status == 'arrived');
  }

  // ── Chat / messaging ────────────────────────────────────────────────────────

  static Future<void> sendMessage({
    required String requestId,
    required SenderRole senderRole,
    required String senderName,
    required String body,
  }) async {
    if (!supabaseReady) {
      throw StateError('Supabase is not initialised.');
    }
    await sb.from(SupabaseTables.messages).insert({
      'request_id': requestId,
      'sender_role': senderRole.toDbString(),
      'sender_name': senderName,
      'body': body,
    });
    // Update last_message_at for unread badge.
    await sb
        .from(SupabaseTables.requests)
        .update({'last_message_at': _utcNowIso()})
        .eq('id', requestId);
  }

  /// Real-time messages for a request, oldest first.
  static Stream<List<ChatMessage>> streamMessages(String requestId) {
    if (!supabaseReady) return const Stream.empty();
    return sb
        .from(SupabaseTables.messages)
        .stream(primaryKey: ['id'])
        .eq('request_id', requestId)
        .order('created_at', ascending: true)
        .map((rows) => rows.map(ChatMessage.fromMap).toList());
  }

  /// Fetch messages once (read-only history).
  static Future<List<ChatMessage>> getMessages(String requestId) async {
    if (!supabaseReady) return [];
    final rows = await sb
        .from(SupabaseTables.messages)
        .select()
        .eq('request_id', requestId)
        .order('created_at', ascending: true);
    return (rows as List)
        .map((r) => ChatMessage.fromMap(r as Map<String, dynamic>))
        .toList();
  }
}
