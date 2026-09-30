import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../constants/colors.dart';
import '../../models/message_model.dart';
import '../../models/request_model.dart';
import '../../services/request_service.dart';
import '../chat_page.dart';
import '../tracking_page.dart';

/// Uber-like dashboard for approved drivers.
/// Shows an online/offline toggle and a real-time incoming-request card.
class DriverDashboardPage extends StatefulWidget {
  const DriverDashboardPage({super.key, required this.driver});

  final DriverProfile driver;

  @override
  State<DriverDashboardPage> createState() => _DriverDashboardPageState();
}

class _DriverDashboardPageState extends State<DriverDashboardPage> {
  late DriverProfile _driver;
  List<AmbulanceRequest> _pendingRequests = [];
  AmbulanceRequest? _activeRequest;

  // streams
  StreamSubscription<List<AmbulanceRequest>>? _pendingSub;
  StreamSubscription<AmbulanceRequest?>? _activeSub;

  // location
  StreamSubscription<Position>? _locationSub;

  // countdown for auto-reject
  Timer? _countdownTimer;
  int _countdown = 30;

  // unread chat badge
  int _unreadCount = 0;
  StreamSubscription<List<ChatMessage>>? _chatSub;
  int _lastSeenMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _driver = widget.driver;
    if (_driver.isOnline) {
      _startListening();
      _startLocationUpdates();
    }
  }

  @override
  void dispose() {
    _pendingSub?.cancel();
    _activeSub?.cancel();
    _locationSub?.cancel();
    _countdownTimer?.cancel();
    _chatSub?.cancel();
    super.dispose();
  }

  // ── Online toggle ──────────────────────────────────────────────────────────

  Future<void> _toggleOnline(bool value) async {
    await RequestService.setOnlineStatus(driverId: _driver.id, isOnline: value);
    setState(() => _driver = DriverProfile(
          id:               _driver.id,
          firebaseUid:      _driver.firebaseUid,
          name:             _driver.name,
          phone:            _driver.phone,
          vehicleType:      _driver.vehicleType,
          vehicleNumber:    _driver.vehicleNumber,
          isOnline:         value,
          isApproved:       _driver.isApproved,
          currentLat:       _driver.currentLat,
          currentLng:       _driver.currentLng,
          currentRequestId: _driver.currentRequestId,
        ));
    if (value) {
      _startListening();
      _startLocationUpdates();
    } else {
      _pendingSub?.cancel();
      _activeSub?.cancel();
      _locationSub?.cancel();
      setState(() { _pendingRequests = []; _activeRequest = null; });
    }
  }

  // ── Streams ────────────────────────────────────────────────────────────────

  void _startListening() {
    // Pending requests feed
    _pendingSub = RequestService.streamPendingRequests().listen((list) {
      if (!mounted) return;
      setState(() => _pendingRequests = list);
      // Start countdown for the first new request
      if (list.isNotEmpty && _countdownTimer == null) _startCountdown();
    });

    // Active request (accepted)
    _activeSub = RequestService.streamDriverActiveRequest(_driver.id).listen((req) {
      if (!mounted) return;
      final prevReq = _activeRequest;
      setState(() => _activeRequest = req);
      // Start or stop chat unread listener when active request changes
      if (req?.id != prevReq?.id) {
        _chatSub?.cancel();
        _lastSeenMessageCount = 0;
        _unreadCount = 0;
        if (req != null) {
          _chatSub = RequestService.streamMessages(req.id).listen((msgs) {
            if (!mounted) return;
            setState(() => _unreadCount = msgs.length - _lastSeenMessageCount < 0
                ? 0
                : msgs.length - _lastSeenMessageCount);
          });
        }
      }
    });
  }

  void _startCountdown() {
    _countdown = 30;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        _countdownTimer = null;
        // Auto-reject: just pop the first pending entry locally (no DB change)
        if (_pendingRequests.isNotEmpty) {
          setState(() => _pendingRequests = _pendingRequests.sublist(1));
          if (_pendingRequests.isNotEmpty) _startCountdown();
        }
      }
    });
  }

  // ── Location ───────────────────────────────────────────────────────────────

  Future<void> _startLocationUpdates() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;

    _locationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 20),
    ).listen((pos) {
      RequestService.updateDriverLocation(
        driverId: _driver.id,
        lat: pos.latitude,
        lng: pos.longitude,
        currentRequestId: _driver.currentRequestId,
      );
    });
  }

  // ── Accept / Reject ────────────────────────────────────────────────────────

  Future<void> _acceptRequest(AmbulanceRequest request) async {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    try {
      await RequestService.acceptRequest(requestId: request.id, driverId: _driver.id);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TrackingPage(requestId: request.id, isDriver: true, driverId: _driver.id),
        ),
      );
    } catch (e) {
      if (mounted) _showSnack('Failed to accept request. Try again.');
    }
  }

  void _rejectRequest(AmbulanceRequest request) {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    setState(() {
      _pendingRequests = _pendingRequests.where((r) => r.id != request.id).toList();
    });
    if (_pendingRequests.isNotEmpty) _startCountdown();
  }

  void _showSnack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _activeRequest != null
                  ? _buildActiveRequestBanner()
                  : _driver.isOnline
                      ? _buildPendingFeed()
                      : _buildOfflineView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: const BoxDecoration(
        color: AppColors.white,
        boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryDark]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_driver.name, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textDark)),
                Text(_driver.vehicleNumber, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textGrey)),
              ],
            ),
          ),
          // Online toggle
          Column(
            children: [
              Switch(
                value: _driver.isOnline,
                onChanged: _toggleOnline,
                activeThumbColor: AppColors.primary,
              ),
              Text(
                _driver.isOnline ? 'Online' : 'Offline',
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _driver.isOnline ? AppColors.success : AppColors.textLight,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.cardBorder.withValues(alpha: .4),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.wifi_off_rounded, size: 56, color: AppColors.textLight),
          ),
          const SizedBox(height: 20),
          Text('You are offline', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          const SizedBox(height: 8),
          Text('Toggle online to start receiving requests', style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textGrey), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildPendingFeed() {
    if (_pendingRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_rounded, size: 56, color: AppColors.primary),
            const SizedBox(height: 16),
            Text('Looking for requests…', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textDark)),
            const SizedBox(height: 8),
            Text('New requests will appear here instantly', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textGrey)),
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
          ],
        ),
      );
    }

    final request = _pendingRequests.first;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: _IncomingRequestCard(
        request: request,
        countdown: _countdown,
        onAccept: () => _acceptRequest(request),
        onReject: () => _rejectRequest(request),
      ),
    );
  }

  Widget _buildActiveRequestBanner() {
    final req = _activeRequest!;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primary, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.check_circle_rounded, color: AppColors.success),
                  const SizedBox(width: 8),
                  Text('Active Trip', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: AppColors.textDark, fontSize: 16)),
                ]),
                const SizedBox(height: 16),
                _InfoRow(icon: Icons.person_rounded, label: 'Patient', value: req.userName),
                _InfoRow(icon: Icons.phone_rounded, label: 'Phone', value: req.userPhone),
                _InfoRow(icon: Icons.my_location_rounded, label: 'Pickup', value: req.pickupAddress),
                _InfoRow(icon: Icons.flag_rounded, label: 'Destination', value: req.destinationAddress),
                _InfoRow(icon: Icons.attach_money_rounded, label: 'Fare', value: '৳${req.estimatedFare}'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => RequestService.markArrived(req.id),
                icon: const Icon(Icons.place_rounded),
                label: Text('Arrived', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => RequestService.completeRequest(requestId: req.id, driverId: _driver.id),
                icon: const Icon(Icons.check_rounded),
                label: Text('Complete', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.success,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => TrackingPage(requestId: req.id, isDriver: true, driverId: _driver.id),
                  ),
                ),
                icon: const Icon(Icons.map_rounded),
                label: Text('Map', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        setState(() => _lastSeenMessageCount = _lastSeenMessageCount + _unreadCount);
                        setState(() => _unreadCount = 0);
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ChatPage(
                              requestId: req.id,
                              senderRole: SenderRole.driver,
                              senderName: _driver.name,
                              request: req,
                            ),
                          ),
                        ).then((_) {
                          // Reset unread after returning
                          if (mounted) setState(() { _unreadCount = 0; });
                        });
                      },
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      label: Text('Chat', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  if (_unreadCount > 0)
                    Positioned(
                      top: -6,
                      right: -6,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          color: AppColors.warning,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            _unreadCount > 9 ? '9+' : '$_unreadCount',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

// ── Incoming request card ─────────────────────────────────────────────────────

class _IncomingRequestCard extends StatelessWidget {
  const _IncomingRequestCard({
    required this.request,
    required this.countdown,
    required this.onAccept,
    required this.onReject,
  });

  final AmbulanceRequest request;
  final int countdown;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final progress = countdown / 30.0;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: .15), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Countdown bar
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.cardBorder,
              color: progress > .4 ? AppColors.primary : AppColors.warning,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.emergency_rounded, color: AppColors.primary, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('New Request!', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                          Text(request.ambulanceType, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    // Countdown circle
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: countdown > 12 ? AppColors.primary : AppColors.warning, width: 3),
                      ),
                      child: Center(
                        child: Text(
                          '$countdown',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: countdown > 12 ? AppColors.primary : AppColors.warning,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _InfoRow(icon: Icons.person_rounded, label: 'Patient', value: request.userName),
                _InfoRow(icon: Icons.my_location_rounded, label: 'Pickup', value: request.pickupAddress),
                _InfoRow(icon: Icons.flag_rounded, label: 'Destination', value: request.destinationAddress),
                _InfoRow(icon: Icons.straighten_rounded, label: 'Distance', value: '${request.distanceKm.toStringAsFixed(1)} km'),
                _InfoRow(icon: Icons.payments_rounded, label: 'Fare', value: '৳${request.estimatedFare}'),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onReject,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textGrey,
                          side: const BorderSide(color: AppColors.cardBorder),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text('Reject', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: onAccept,
                        icon: const Icon(Icons.check_rounded),
                        label: Text('Accept', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15)),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('$label: ', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textGrey, fontWeight: FontWeight.w500)),
            Expanded(child: Text(value, style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textDark, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis)),
          ],
        ),
      );
}
