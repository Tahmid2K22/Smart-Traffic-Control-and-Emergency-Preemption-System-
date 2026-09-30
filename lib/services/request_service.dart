import 'package:firebase_auth/firebase_auth.dart';

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
  static Future<void> upsertDriverProfile({
    required String firebaseUid,
    required String name,
    required String phone,
    required String vehicleType,
    required String vehicleNumber,
  }) async {
    if (!supabaseReady) return;
    await sb.from(SupabaseTables.drivers).upsert({
      'firebase_uid':    firebaseUid,
      'name':            name,
      'phone':           phone,
      'vehicle_type':    vehicleType,
      'vehicle_number':  vehicleNumber,
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
    await sb.from(SupabaseTables.drivers).update({
      'current_lat':  lat,
      'current_lng':  lng,
      'updated_at':   DateTime.now().toIso8601String(),
    }).eq('id', driverId);
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
    if (!supabaseReady) throw StateError('Supabase is not initialised.');
    final response = await sb.from(SupabaseTables.requests).insert({
      'user_firebase_uid':    userFirebaseUid,
      'user_name':            userName,
      'user_phone':           userPhone,
      'status':               'pending',
      'ambulance_type':       ambulanceType,
      'pickup_lat':           pickupLat,
      'pickup_lng':           pickupLng,
      'pickup_address':       pickupAddress,
      'destination_lat':      destinationLat,
      'destination_lng':      destinationLng,
      'destination_address':  destinationAddress,
      'estimated_fare':       estimatedFare,
      'distance_km':          distanceKm,
    }).select('id').single();
    return response['id'] as String;
  }

  /// Fetches all requests for the current user (for Activity page).
  static Future<List<AmbulanceRequest>> getUserRequests() async {
    if (!supabaseReady) return [];
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];
    final rows = await sb
        .from(SupabaseTables.requests)
        .select('*, drivers(name, phone, current_lat, current_lng)')
        .eq('user_firebase_uid', uid)
        .order('created_at', ascending: false);
    return (rows as List).map((r) => AmbulanceRequest.fromMap(r as Map<String, dynamic>)).toList();
  }

  /// Cancels a pending request (user side).
  static Future<void> cancelRequest(String requestId) async {
    if (!supabaseReady) return;
    await sb.from(SupabaseTables.requests).update({
      'status': RequestStatus.cancelled.toDbString(),
    }).eq('id', requestId);
  }

  // ── Driver accept / reject / complete ───────────────────────────────────────

  /// Driver accepts a pending request.
  static Future<void> acceptRequest({
    required String requestId,
    required String driverId,
  }) async {
    if (!supabaseReady) return;
    await sb.from(SupabaseTables.requests).update({
      'driver_id':    driverId,
      'status':       RequestStatus.accepted.toDbString(),
      'accepted_at':  DateTime.now().toIso8601String(),
    }).eq('id', requestId);

    await sb.from(SupabaseTables.drivers).update({
      'current_request_id': requestId,
    }).eq('id', driverId);
  }

  /// Driver marks themselves as arrived at pickup.
  static Future<void> markArrived(String requestId) async {
    if (!supabaseReady) return;
    await sb.from(SupabaseTables.requests).update({
      'status': RequestStatus.arrived.toDbString(),
    }).eq('id', requestId);
  }

  /// Driver marks the trip as completed.
  static Future<void> completeRequest({
    required String requestId,
    required String driverId,
  }) async {
    if (!supabaseReady) return;
    await sb.from(SupabaseTables.requests).update({
      'status':       RequestStatus.completed.toDbString(),
      'completed_at': DateTime.now().toIso8601String(),
    }).eq('id', requestId);

    await sb.from(SupabaseTables.drivers).update({
      'current_request_id': null,
    }).eq('id', driverId);
  }

  // ── Real-time streams ───────────────────────────────────────────────────────

  /// Stream of ALL pending requests — driver listens to this to get incoming jobs.
  static Stream<List<AmbulanceRequest>> streamPendingRequests() {
    if (!supabaseReady) return const Stream.empty();
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
        .map((rows) => rows.isEmpty ? null : AmbulanceRequest.fromMap(rows.first));
  }

  /// Stream of the driver's own active requests.
  static Stream<AmbulanceRequest?> streamDriverActiveRequest(String driverId) {
    if (!supabaseReady) return const Stream.empty();
    return sb
        .from(SupabaseTables.requests)
        .stream(primaryKey: ['id'])
        .eq('driver_id', driverId)
        .inFilter('status', ['accepted', 'en_route', 'arrived'])
        .order('accepted_at', ascending: false)
        .map((rows) => rows.isEmpty ? null : AmbulanceRequest.fromMap(rows.first));
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
      'request_id':  requestId,
      'sender_role': senderRole.toDbString(),
      'sender_name': senderName,
      'body':        body,
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
    return (rows as List).map((r) => ChatMessage.fromMap(r as Map<String, dynamic>)).toList();
  }
}
