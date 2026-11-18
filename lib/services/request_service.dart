import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:math' as math;

import '../models/message_model.dart';
import '../models/request_model.dart';
import 'supabase_service.dart';

/// Service layer for all ambulance request operations.
/// Uses Supabase Postgres + real-time for the driver dispatch system
/// while Firebase Auth provides identity.
class RequestService {
  RequestService._();

  // ── Driver helpers ──────────────────────────────────────────────────────────

  /// Upserts a driver row in Supabase when a driver logs in or registers.
  /// [isApproved] mirrors the Firestore `isApproved` field so the Supabase
  /// `is_approved` column is always in sync with admin decisions.
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

  /// Fetches the driver row for the currently signed-in Firebase user.
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

  /// Toggles the driver online/offline status.
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

  /// Updates the driver's live GPS coordinates.
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
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', driverId);
  }

  // ── User request operations ─────────────────────────────────────────────────

  /// Creates a new ambulance request and returns its UUID.
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

  /// Fetches all requests for the current user (for Activity page).
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

  /// Cancels a request before it is completed.
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
            'created_at': DateTime.now().toIso8601String(),
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
    final driverQuery = sb.from(SupabaseTables.drivers).update({
      'current_request_id': null,
    });
    if (driverId == null) {
      await driverQuery.eq('current_request_id', requestId);
    } else {
      await driverQuery.eq('id', driverId);
    }
  }

  /// Cancels a pending request when the driver search window expires.
  /// Returns false when a driver accepted it before the timeout won the race.
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

  /// Cancels every pending request whose search window is 10 minutes old.
  /// This sweep also works after the app restarts or comes back online.
  static Future<int> expireStalePendingRequests() async {
    if (!supabaseReady) return 0;
    final cutoff = DateTime.now()
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

  /// Driver accepts a pending request.
  static Future<void> acceptRequest({
    required String requestId,
    required String driverId,
  }) async {
    if (!supabaseReady) return;
    final accepted = await sb
        .from(SupabaseTables.requests)
        .update({
          'driver_id': driverId,
          'status': RequestStatus.accepted.toDbString(),
          'accepted_at': DateTime.now().toIso8601String(),
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

  /// Driver marks themselves as arrived at pickup.
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

  /// Driver marks the trip as completed.
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
          'completed_at': DateTime.now().toIso8601String(),
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

  /// Stream of ALL pending requests — driver listens to this to get incoming jobs.
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

  /// Stream of a specific request — user listens after booking to track status.
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

  /// Reads the request with its current driver GPS position. This short
  /// refresh is needed because driver coordinates change independently of the
  /// request row.
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

  /// Counts online ambulances close enough to receive the request. The
  /// dispatch radius grows as the request waits, like a ride-hailing system.
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

  /// Stream of the driver's own active requests.
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

  // ── Chat / messaging ────────────────────────────────────────────────────────

  /// Sends a chat message for a given request.
  static Future<void> sendMessage({
    required String requestId,
    required SenderRole senderRole,
    required String senderName,
    required String body,
  }) async {
    if (!supabaseReady) return;
    await sb.from(SupabaseTables.messages).insert({
      'request_id': requestId,
      'sender_role': senderRole.toDbString(),
      'sender_name': senderName,
      'body': body,
    });
    // Update last_message_at on the request for unread badge support
    await sb
        .from(SupabaseTables.requests)
        .update({'last_message_at': DateTime.now().toIso8601String()})
        .eq('id', requestId);
  }

  /// Real-time stream of all messages for a given request, oldest first.
  static Stream<List<ChatMessage>> streamMessages(String requestId) {
    if (!supabaseReady) return const Stream.empty();
    return sb
        .from(SupabaseTables.messages)
        .stream(primaryKey: ['id'])
        .eq('request_id', requestId)
        .order('created_at', ascending: true)
        .map((rows) => rows.map(ChatMessage.fromMap).toList());
  }

  /// Fetch all messages for a request once (for read-only history view).
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
