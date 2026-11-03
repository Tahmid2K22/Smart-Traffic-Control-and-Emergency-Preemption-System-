import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../services/admin_service.dart';
import '../../services/ble_traffic_service.dart';
import '../../services/traffic_service.dart';
import '../traffic_light_control_page.dart';

class TrafficPoliceDashboardScreen extends StatefulWidget {
  const TrafficPoliceDashboardScreen({
    super.key,
    required this.uid,
    required this.profile,
  });

  final String uid;
  final Map<String, dynamic> profile;

  @override
  State<TrafficPoliceDashboardScreen> createState() =>
      _TrafficPoliceDashboardScreenState();
}

class _TrafficPoliceDashboardScreenState
    extends State<TrafficPoliceDashboardScreen> {
  final _trafficService = TrafficService();
  final _adminService   = AdminService();
  final _ble            = BleTrafficService.instance;

  late bool _isActive;

  _BleStatus _bleStatus  = _BleStatus.idle;
  String     _bleMessage = 'Searching for ESP32 signal…';
  String?    _bleDeviceName;

  @override
  void initState() {
    super.initState();
    _isActive = widget.profile['isActive'] == true;
    _startAutoConnect();
  }

  @override
  void dispose() {
    _ble.stopAutoConnect();
    super.dispose();
  }

  Future<void> _startAutoConnect() async {
    if (!mounted) return;
    setState(() {
      _bleStatus  = _BleStatus.scanning;
      _bleMessage = 'Searching for ESP32 signal in range…';
    });

    final permOk = await _ble.requestPermissions();
    if (!permOk) {
      if (mounted) {
        setState(() {
          _bleStatus  = _BleStatus.error;
          _bleMessage = 'Bluetooth permission required for ESP32 control.';
        });
      }
      return;
    }

    await _ble.startAutoConnect(
      onConnected: (dev) {
        if (mounted) {
          setState(() {
            _bleStatus     = _BleStatus.connected;
            _bleDeviceName = dev.name;
            _bleMessage    = 'Connected to ${dev.name}';
          });
        }
      },
      onDisconnected: () {
        if (mounted) {
          setState(() {
            _bleStatus  = _BleStatus.scanning;
            _bleMessage = 'ESP32 disconnected. Reconnecting…';
          });
        }
      },
      onError: (msg) {
        if (mounted) {
          setState(() {
            _bleStatus  = _BleStatus.error;
            _bleMessage = msg;
          });
        }
      },
    );
  }

  LatLng get _intersection {
    final value = widget.profile['intersectionLocation'];
    if (value is GeoPoint) return LatLng(value.latitude, value.longitude);
    final lat = (widget.profile['intersectionLatitude']  as num?)?.toDouble();
    final lng = (widget.profile['intersectionLongitude'] as num?)?.toDouble();
    return LatLng(lat ?? 23.8103, lng ?? 90.4125);
  }

  Set<Marker> _markers(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> alerts) {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('assigned-intersection'),
        position: _intersection,
        infoWindow: InfoWindow(
          title: widget.profile['assignedIntersection']?.toString() ??
              'Assigned intersection',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ),
    };
    for (final alert in alerts) {
      final data           = alert.data();
      final driverLocation = data['driverLocation'];
      if (driverLocation is GeoPoint) {
        markers.add(
          Marker(
            markerId: MarkerId('ambulance-${alert.id}'),
            position: LatLng(
                driverLocation.latitude, driverLocation.longitude),
            infoWindow: InfoWindow(
              title:   'Approaching ambulance',
              snippet: '${data['distanceMeters'] ?? 0} m away',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueRed),
          ),
        );
      }
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.profile['assignedIntersection']?.toString() ??
              'Traffic Control',
        ),
        actions: [
          Row(
            children: [
              const Text('On duty', style: TextStyle(fontSize: 13)),
              Switch(
                value: _isActive,
                onChanged: (value) async {
                  await _adminService.setOfficerActive(widget.uid, value);
                  if (mounted) setState(() => _isActive = value);
                },
              ),
            ],
          ),
          IconButton(
            tooltip: 'Log Out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: Column(
        children: [
          _BleStatusBanner(
            status:     _bleStatus,
            message:    _bleMessage,
            deviceName: _bleDeviceName,
            onRetry:    _startAutoConnect,
            onOpenControl: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TrafficLightControlPage()),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _trafficService.alertsForOfficer(widget.uid),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                      child: Text('Unable to load alerts: ${snapshot.error}'));
                }
                final alerts = snapshot.data?.docs ?? const [];
                return Column(
                  children: [
                    Expanded(
                      child: GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: _intersection,
                          zoom:   14.5,
                        ),
                        markers:                 _markers(alerts),
                        myLocationButtonEnabled: true,
                        zoomControlsEnabled:     false,
                      ),
                    ),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 280),
                      padding: const EdgeInsets.all(12),
                      child: alerts.isEmpty
                          ? const ListTile(
                              leading: Icon(Icons.check_circle, color: Colors.green),
                              title: Text('No approaching ambulances'),
                              subtitle: Text('Alerts will appear within 2 km while on duty.'),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: alerts.length,
                              itemBuilder: (context, index) => _AlertCard(
                                doc:          alerts[index],
                                adminService: _adminService,
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor:  Colors.redAccent,
        foregroundColor:  Colors.white,
        icon:  const Icon(Icons.traffic_rounded),
        label: const Text('Traffic Light Control'),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TrafficLightControlPage()),
        ),
      ),
    );
  }
}

enum _BleStatus { idle, scanning, connected, error }

class _BleStatusBanner extends StatelessWidget {
  final _BleStatus status;
  final String     message;
  final String?    deviceName;
  final VoidCallback onRetry;
  final VoidCallback onOpenControl;

  const _BleStatusBanner({
    required this.status,
    required this.message,
    required this.deviceName,
    required this.onRetry,
    required this.onOpenControl,
  });

  @override
  Widget build(BuildContext context) {
    if (status == _BleStatus.connected) {
      return InkWell(
        onTap: onOpenControl,
        child: Container(
          width: double.infinity,
          color: const Color(0xFFE8F5E9),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.bluetooth_connected_rounded, color: Colors.green, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ESP32 Connected: ${deviceName ?? "Signal"} (Tap to Control)',
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: const Color(0xFF2E7D32),
                      fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF2E7D32), size: 18),
            ],
          ),
        ),
      );
    }

    if (status == _BleStatus.scanning) {
      return Container(
        width: double.infinity,
        color: const Color(0xFFFFF8E1),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.orange.shade800),
              ),
            ),
          ],
        ),
      );
    }

    if (status == _BleStatus.error) {
      return Container(
        width: double.infinity,
        color: const Color(0xFFFFEBEE),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.bluetooth_disabled_rounded, color: Colors.red, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.poppins(fontSize: 11, color: Colors.red.shade800),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: Text('Retry',
                  style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.doc,
    required this.adminService,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final AdminService adminService;

  @override
  Widget build(BuildContext context) {
    final data     = doc.data();
    final distance = (data['distanceMeters'] as num?)?.toDouble() ?? 0;
    final eta      = (data['estimatedArrivalMinutes'] as num?)?.toInt();
    return Card(
      color: Colors.red.shade50,
      child: ListTile(
        leading: const Icon(Icons.emergency, color: Colors.red),
        title: Text(
          data['intersectionName']?.toString() ?? 'Traffic signal alert',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${(distance / 1000).toStringAsFixed(2)} km away'
          '${eta == null ? '' : ' • ETA $eta min'}'
          ' • ${data['status'] ?? 'ACTIVE'}',
        ),
        trailing: Wrap(
          spacing: 2,
          children: [
            IconButton(
              tooltip: 'Override signal to green',
              color: Colors.green,
              onPressed: () => adminService.overrideSignal(
                doc.id,
                data['dispatchId']?.toString() ?? '',
              ),
              icon: const Icon(Icons.traffic),
            ),
            IconButton(
              tooltip: 'Clear alert',
              onPressed: () => adminService.clearEmergencyAlert(doc.id),
              icon: const Icon(Icons.clear),
            ),
          ],
        ),
      ),
    );
  }
}
