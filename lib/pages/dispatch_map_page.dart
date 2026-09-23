import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/colors.dart';
import '../models/models.dart';

class DispatchMapPage extends StatefulWidget {
  final ActivityItem ride;

  const DispatchMapPage({super.key, required this.ride});

  @override
  State<DispatchMapPage> createState() => _DispatchMapPageState();
}

class _DispatchMapPageState extends State<DispatchMapPage> {
  static const _ambulance = LatLng(22.8456, 89.5403);
  static const _intersection = LatLng(22.8468, 89.5472);
  static const _hospital = LatLng(22.8397, 89.5500);

  final MapController _mapController = MapController();
  List<LatLng> _routePoints = const [];
  bool _isLoadingRoute = true;
  bool _routeFailed = false;

  @override
  void initState() {
    super.initState();
    _loadRoute();
  }

  Future<void> _loadRoute() async {
    setState(() {
      _isLoadingRoute = true;
      _routeFailed = false;
    });

    final coordinates =
        '${_ambulance.longitude},${_ambulance.latitude};'
        '${_intersection.longitude},${_intersection.latitude};'
        '${_hospital.longitude},${_hospital.latitude}';
    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/$coordinates'
      '?overview=full&geometries=geojson',
    );

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) throw Exception('OSRM error');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final geometry =
          (data['routes'] as List).first['geometry'] as Map<String, dynamic>;
      final rawPoints = geometry['coordinates'] as List;
      final route = rawPoints
          .map(
            (point) => LatLng(
              (point[1] as num).toDouble(),
              (point[0] as num).toDouble(),
            ),
          )
          .toList();

      if (!mounted) return;
      setState(() {
        _routePoints = route;
        _isLoadingRoute = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _routePoints = const [_ambulance, _intersection, _hospital];
        _routeFailed = true;
        _isLoadingRoute = false;
      });
    }
  }

  Future<void> _startNavigation() async {
    final nativeUri = Uri.parse(
      'google.navigation:q=${_hospital.latitude},${_hospital.longitude}&mode=d',
    );
    final fallbackUri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '${_hospital.latitude},${_hospital.longitude}',
      'waypoints': '${_intersection.latitude},${_intersection.longitude}',
    });

    if (await canLaunchUrl(nativeUri) &&
        await launchUrl(nativeUri, mode: LaunchMode.externalApplication)) {
      return;
    }
    await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: _intersection,
              initialZoom: 14.8,
              interactionOptions: InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.ambulance.bd.ambulanceDashboard',
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _routePoints,
                    color: AppColors.primary,
                    strokeWidth: 6,
                    borderColor: Colors.white,
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  _marker(
                    _ambulance,
                    Icons.local_shipping_rounded,
                    AppColors.primary,
                  ),
                  _marker(
                    _intersection,
                    Icons.traffic_rounded,
                    AppColors.accentOrange,
                  ),
                  _marker(
                    _hospital,
                    Icons.local_hospital_rounded,
                    AppColors.infoBlue,
                  ),
                ],
              ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _mapHeader(),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 270,
            child: Column(
              children: [
                _mapControl(
                  icon: _isLoadingRoute
                      ? Icons.sync_rounded
                      : Icons.refresh_rounded,
                  onPressed: _isLoadingRoute ? null : _loadRoute,
                ),
                const SizedBox(height: 10),
                _mapControl(
                  icon: Icons.my_location_rounded,
                  onPressed: () => _mapController.move(_intersection, 15.2),
                ),
              ],
            ),
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: _dispatchSheet()),
        ],
      ),
    );
  }

  Marker _marker(LatLng point, IconData icon, Color color) {
    return Marker(
      point: point,
      width: 52,
      height: 52,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
        ),
        child: Icon(icon, color: Colors.white, size: 25),
      ),
    );
  }

  Widget _mapHeader() {
    return Row(
      children: [
        _mapControl(
          icon: Icons.arrow_back_rounded,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: _cardDecoration(),
            child: Row(
              children: [
                const Icon(Icons.circle, color: AppColors.success, size: 10),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Live ambulance tracking',
                    style: GoogleFonts.poppins(
                      color: AppColors.textDark,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  _isLoadingRoute ? 'Routing...' : 'En route',
                  style: GoogleFonts.poppins(
                    color: _routeFailed ? AppColors.warning : AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _mapControl({
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Material(
      color: Colors.white,
      elevation: 5,
      borderRadius: BorderRadius.circular(14),
      child: IconButton(
        tooltip: icon == Icons.my_location_rounded
            ? 'My location'
            : 'Recalculate route',
        onPressed: onPressed,
        icon: Icon(icon, color: AppColors.textDark),
      ),
    );
  }

  Widget _dispatchSheet() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 18)],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.cardBorder,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Ambulance is on the way',
              style: GoogleFonts.poppins(
                color: AppColors.textDark,
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.ride.driver}  •  ${widget.ride.vehicle}',
              style: GoogleFonts.poppins(
                color: AppColors.textGrey,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _detail(
                  Icons.access_time_rounded,
                  widget.ride.eta ?? '8 min',
                  'ETA',
                ),
                const SizedBox(width: 10),
                _detail(Icons.route_rounded, widget.ride.distance, 'Distance'),
                const SizedBox(width: 10),
                _detail(Icons.traffic_rounded, '1 signal', 'Waypoint'),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _startNavigation,
                icon: const Icon(Icons.navigation_rounded),
                label: const Text('Start Google Maps Navigation'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 18),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 10,
                color: AppColors.textGrey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
    );
  }
}
