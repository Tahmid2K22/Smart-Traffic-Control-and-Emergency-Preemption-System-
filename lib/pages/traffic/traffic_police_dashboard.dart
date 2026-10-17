import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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
  final _mapController = MapController();
  final _trafficService = TrafficService();
  final _adminService = AdminService();
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    _isActive = widget.profile['isActive'] == true;
  }

  LatLng? get _intersection {
    final value = widget.profile['intersectionLocation'];
    if (value is GeoPoint) return LatLng(value.latitude, value.longitude);
    final lat = (widget.profile['intersectionLatitude'] as num?)?.toDouble();
    final lng = (widget.profile['intersectionLongitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  @override
  Widget build(BuildContext context) {
    final point = _intersection ?? const LatLng(23.8103, 90.4125);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.profile['assignedIntersection']?.toString() ?? 'Traffic Control'),
        actions: [
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
        builder: (context, alertSnapshot) {
          final alerts = alertSnapshot.data?.docs ?? const [];
          return Column(
            children: [
              Expanded(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: point,
                    initialZoom: 14,
                    minZoom: 3,
                    maxZoom: 18,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.ambulance_app',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: point,
                          width: 52,
                          height: 52,
                          child: const Icon(Icons.traffic, color: Colors.blue, size: 42),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                constraints: const BoxConstraints(maxHeight: 260),
                padding: const EdgeInsets.all(12),
                child: alerts.isEmpty
                    ? const ListTile(
                        leading: Icon(Icons.check_circle, color: Colors.green),
                        title: Text('No approaching ambulances'),
                        subtitle: Text('You will be alerted within 1 km while on duty.'),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: alerts.length,
                        itemBuilder: (context, index) {
                          final doc = alerts[index];
                          final data = doc.data();
                          final distance =
                              (data['distanceMeters'] as num?)?.round() ?? 0;
                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.emergency, color: Colors.red),
                              title: Text('Ambulance ${data['dispatchId'] ?? ''}'),
                              subtitle: Text('$distance m away • ${data['signalState'] ?? 'NORMAL'}'),
                              trailing: Wrap(
                                spacing: 4,
                                children: [
                                  IconButton(
                                    tooltip: 'Override signal to green',
                                    color: Colors.green,
                                    onPressed: () => _adminService.overrideSignal(
                                      doc.id,
                                      data['dispatchId']?.toString() ?? '',
                                    ),
                                    icon: const Icon(Icons.traffic),
                                  ),
                                  IconButton(
                                    tooltip: 'Clear intersection',
                                    onPressed: () => _adminService.clearEmergencyAlert(doc.id),
                                    icon: const Icon(Icons.clear),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
