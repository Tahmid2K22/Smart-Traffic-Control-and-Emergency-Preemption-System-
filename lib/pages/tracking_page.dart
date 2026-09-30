import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../constants/colors.dart';
import '../models/message_model.dart';
import '../models/request_model.dart';
import '../services/request_service.dart';
import 'chat_page.dart';

/// Shared live-tracking screen shown to both user and driver after a request
/// is accepted. Polls the request real-time via Supabase stream and updates
/// the driver pin on the map automatically.
class TrackingPage extends StatefulWidget {
  const TrackingPage({
    super.key,
    required this.requestId,
    required this.isDriver,
    this.driverId,
  });

  final String requestId;
  final bool isDriver;
  final String? driverId;

  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage> {
  AmbulanceRequest? _request;
  StreamSubscription<AmbulanceRequest?>? _sub;
  GoogleMapController? _mapController;

  static const _defaultCenter = LatLng(23.8103, 90.4125);

  @override
  void initState() {
    super.initState();
    _sub = RequestService.streamRequest(widget.requestId).listen((req) {
      if (!mounted) return;
      setState(() => _request = req);
      _animateToRelevantPin();

      // Auto-pop when trip is done
      if (req?.status == RequestStatus.completed || req?.status == RequestStatus.cancelled) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _animateToRelevantPin() {
    final req = _request;
    if (req == null || _mapController == null) return;
    LatLng? target;
    if (widget.isDriver) {
      // Driver tracks the pickup point
      target = LatLng(req.pickupLat, req.pickupLng);
    } else if (req.driverLat != null && req.driverLng != null) {
      // User tracks the driver
      target = LatLng(req.driverLat!, req.driverLng!);
    }
    if (target != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLng(target));
    }
  }

  Set<Marker> _markers() {
    final req = _request;
    if (req == null) return {};
    final markers = <Marker>{};

    // Pickup marker
    markers.add(Marker(
      markerId: const MarkerId('pickup'),
      position: LatLng(req.pickupLat, req.pickupLng),
      infoWindow: InfoWindow(title: 'Pickup: ${req.pickupAddress}'),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
    ));

    // Destination marker
    markers.add(Marker(
      markerId: const MarkerId('destination'),
      position: LatLng(req.destinationLat, req.destinationLng),
      infoWindow: InfoWindow(title: 'Destination: ${req.destinationAddress}'),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
    ));

    // Driver location marker (shown to user)
    if (!widget.isDriver && req.driverLat != null && req.driverLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('driver'),
        position: LatLng(req.driverLat!, req.driverLng!),
        infoWindow: InfoWindow(title: 'Driver: ${req.driverName ?? "Driver"}'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      ));
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final req = _request;
    final isCompleted = req?.status == RequestStatus.completed;
    final isCancelled = req?.status == RequestStatus.cancelled;
    final isActive = req?.status == RequestStatus.accepted ||
        req?.status == RequestStatus.enRoute ||
        req?.status == RequestStatus.arrived;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.isDriver ? 'Active Trip' : 'Tracking your driver'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      floatingActionButton: (!widget.isDriver && req != null && isActive)
          ? FloatingActionButton.extended(
              heroTag: 'chat_fab',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ChatPage(
                    requestId: req.id,
                    senderRole: SenderRole.user,
                    senderName: req.userName,
                    request: req,
                  ),
                ),
              ),
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white),
              label: Text(
                'Chat',
                style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            )
          : null,
      body: Stack(
        children: [
          // Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: req != null ? LatLng(req.pickupLat, req.pickupLng) : _defaultCenter,
              zoom: 14.5,
            ),
            onMapCreated: (c) { _mapController = c; _animateToRelevantPin(); },
            markers: _markers(),
            zoomControlsEnabled: false,
            myLocationButtonEnabled: false,
          ),

          // Bottom info sheet
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Color(0x18000000), blurRadius: 20)],
              ),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              child: req == null
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : isCompleted
                      ? _CompletedBanner(req: req)
                      : isCancelled
                          ? _CancelledBanner()
                          : _StatusInfo(req: req, isDriver: widget.isDriver),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Status info sheet ─────────────────────────────────────────────────────────

class _StatusInfo extends StatelessWidget {
  const _StatusInfo({required this.req, required this.isDriver});
  final AmbulanceRequest req;
  final bool isDriver;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(
              width: 10, height: 10,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
            ),
            const SizedBox(width: 8),
            Text(req.status.label, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
          ]),
        ),
        const SizedBox(height: 16),

        if (!isDriver && req.driverName != null) ...[
          Text('Your driver', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textGrey)),
          Text(req.driverName!, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          const SizedBox(height: 4),
          Text(req.driverPhone ?? '', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textGrey)),
          const SizedBox(height: 16),
        ],

        _TripRow(icon: Icons.my_location_rounded, label: 'Pickup', value: req.pickupAddress),
        const SizedBox(height: 8),
        _TripRow(icon: Icons.flag_rounded, label: 'Destination', value: req.destinationAddress),
        const SizedBox(height: 8),
        _TripRow(icon: Icons.payments_rounded, label: 'Fare', value: '৳${req.estimatedFare}'),
      ],
    );
  }
}

class _CompletedBanner extends StatelessWidget {
  const _CompletedBanner({required this.req});
  final AmbulanceRequest req;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 52),
          const SizedBox(height: 12),
          Text('Trip Completed!', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          const SizedBox(height: 4),
          Text('Total fare: ৳${req.estimatedFare}', style: GoogleFonts.poppins(fontSize: 15, color: AppColors.textGrey)),
          const SizedBox(height: 16),
          Text('Returning in a moment…', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textLight)),
        ],
      );
}

class _CancelledBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cancel_rounded, color: AppColors.warning, size: 52),
          const SizedBox(height: 12),
          Text('Trip Cancelled', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          const SizedBox(height: 4),
          Text('The request was cancelled.', style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textGrey)),
        ],
      );
}

class _TripRow extends StatelessWidget {
  const _TripRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Text('$label  ', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textGrey)),
          Expanded(child: Text(value, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark), maxLines: 2, overflow: TextOverflow.ellipsis)),
        ],
      );
}
