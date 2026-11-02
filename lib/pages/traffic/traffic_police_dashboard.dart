import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../services/admin_service.dart';
import '../../services/traffic_service.dart';

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
  final _adminService = AdminService();
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    _isActive = widget.profile['isActive'] == true;
  }

  LatLng get _intersection {
    final value = widget.profile['intersectionLocation'];
    if (value is GeoPoint) return LatLng(value.latitude, value.longitude);
    final lat = (widget.profile['intersectionLatitude'] as num?)?.toDouble();
    final lng = (widget.profile['intersectionLongitude'] as num?)?.toDouble();
    return LatLng(lat ?? 23.8103, lng ?? 90.4125);
  }

  Set<Marker> _markers(List<QueryDocumentSnapshot<Map<String, dynamic>>> alerts) {
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
      final data = alert.data();
      final driverLocation = data['driverLocation'];
      if (driverLocation is GeoPoint) {
        markers.add(
          Marker(
            markerId: MarkerId('ambulance-${alert.id}'),
            position: LatLng(driverLocation.latitude, driverLocation.longitude),
            infoWindow: InfoWindow(
              title: 'Approaching ambulance',
              snippet: '${data['distanceMeters'] ?? 0} m away',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
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
          const Text('On duty'),
          Switch(
            value: _isActive,
            onChanged: (value) async {
              await _adminService.setOfficerActive(widget.uid, value);
              if (mounted) setState(() => _isActive = value);
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _trafficService.alertsForOfficer(widget.uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Unable to load alerts: ${snapshot.error}'));
          }
          final alerts = snapshot.data?.docs ?? const [];
          return Column(
            children: [
              Expanded(
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _intersection,
                    zoom: 14.5,
                  ),
                  markers: _markers(alerts),
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: false,
                ),
              ),
              Container(
                constraints: const BoxConstraints(maxHeight: 280),
                padding: const EdgeInsets.all(12),
                child: alerts.isEmpty
                    ? const ListTile(
                        leading: Icon(Icons.check_circle, color: Colors.green),
                        title: Text('No approaching ambulances'),
                        subtitle: Text(
                          'You will be alerted within 2 km while on duty.',
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: alerts.length,
                        itemBuilder: (context, index) =>
                            _AlertCard(
                              doc: alerts[index],
                              adminService: _adminService,
                            ),
                      ),
              ),
            ],
          );
        },
      ),
    );
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
    final data = doc.data();
    final distance = (data['distanceMeters'] as num?)?.toDouble() ?? 0;
    final eta = (data['estimatedArrivalMinutes'] as num?)?.toInt();
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
