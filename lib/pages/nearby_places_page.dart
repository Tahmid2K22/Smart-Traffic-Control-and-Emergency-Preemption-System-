import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/colors.dart';
import '../services/deep_link_navigation_service.dart';
import '../services/hospital_service.dart';
import '../services/places_api_service.dart';

enum NearbyPlaceType { hospitals, pharmacies }

enum _LocationSettingsTarget { app, location }

class NearbyPlacesPage extends StatefulWidget {
  const NearbyPlacesPage({
    super.key,
    required this.type,
    this.placesApi,
    this.locate,
  });

  final NearbyPlaceType type;
  final PlacesApiService? placesApi;
  final Future<Position> Function()? locate;

  @override
  State<NearbyPlacesPage> createState() => _NearbyPlacesPageState();
}

class _NearbyPlacesPageState extends State<NearbyPlacesPage> {
  late final PlacesApiService _placesApi;
  LatLng? _userLocation;
  bool _showMap = false;
  bool _loading = true;
  List<NearbyPlaceResult> _places = const [];
  String? _error;
  _LocationSettingsTarget? _settingsTarget;

  String get _facility =>
      widget.type == NearbyPlaceType.hospitals ? 'hospitals' : 'pharmacies';

  String get _title => widget.type == NearbyPlaceType.hospitals
      ? 'Nearby Hospitals'
      : 'Nearby Pharmacies';

  @override
  void initState() {
    super.initState();
    _placesApi = widget.placesApi ?? PlacesApiService();
    _scan();
  }

  @override
  void dispose() {
    // Injected service owned by caller.
    if (widget.placesApi == null) _placesApi.dispose();
    super.dispose();
  }

  Future<Position> _locate() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationServiceDisabledException();
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const _LocationFailure(
        'Location permission is permanently denied. Enable it in Settings, then retry.',
        _LocationSettingsTarget.app,
      );
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      throw const PermissionDeniedException(
        'Allow location access to find nearby facilities.',
      );
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
  }

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _places = const [];
      _userLocation = null;
      _error = null;
      _settingsTarget = null;
    });
    var locating = true;
    try {
      final position = await (widget.locate ?? _locate)();
      if (!mounted) return;
      if (!position.latitude.isFinite ||
          !position.longitude.isFinite ||
          position.latitude.abs() > 90 ||
          position.longitude.abs() > 180) {
        throw const _LocationFailure(
          'GPS returned an invalid location. Please retry outdoors.',
        );
      }
      final center = LatLng(position.latitude, position.longitude);
      setState(() => _userLocation = center);
      locating = false;
      final fetched = await _placesApi.nearby(
        center: center,
        type: widget.type == NearbyPlaceType.hospitals
            ? 'hospital'
            : 'pharmacy',
        radiusMeters: PlacesApiService.nearbyRadiusMeters,
      );
      if (!mounted) return;
      double distance(NearbyPlaceResult place) => Geolocator.distanceBetween(
        center.latitude,
        center.longitude,
        place.location.latitude,
        place.location.longitude,
      );
      var combined = fetched.toList();

      if (widget.type == NearbyPlaceType.hospitals) {
        try {
          final hospitals = await HospitalService().approvedHospitalsOnce();
          for (final hospital in hospitals) {
            if (hospital.lat == 0 || hospital.lon == 0) continue;
            combined.removeWhere(
              (place) =>
                  place.name.toLowerCase().trim() ==
                  hospital.name.toLowerCase().trim(),
            );
            combined.add(
              NearbyPlaceResult(
                id: 'registered-${hospital.id}',
                name: hospital.name,
                address: hospital.address.isNotEmpty
                    ? hospital.address
                    : hospital.city,
                location: LatLng(hospital.lat, hospital.lon),
                isOpen: null,
                types: const ['hospital'],
                phone: hospital.phone.isNotEmpty ? hospital.phone : null,
              ),
            );
          }
        } catch (_) {
          // OSM results stay if Firestore down.
        }
      }

      final nearby =
          combined
              .where(
                (place) =>
                    distance(place) <= PlacesApiService.nearbyRadiusMeters,
              )
              .toList()
            ..sort((a, b) => distance(a).compareTo(distance(b)));
      setState(() {
        _places = nearby;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      String message;
      _LocationSettingsTarget? settings;
      if (error is _LocationFailure) {
        message = error.message;
        settings = error.settingsTarget;
      } else if (error is LocationServiceDisabledException) {
        message = 'Location services are disabled. Turn on GPS in Settings, then retry.';
        settings = _LocationSettingsTarget.location;
      } else if (error is PermissionDeniedException) {
        message = 'Location permission denied. Allow location access in Settings, then retry.';
        settings = _LocationSettingsTarget.app;
      } else if (locating && error is TimeoutException) {
        message = 'Could not get a fresh GPS location within 20 seconds. Please retry outdoors.';
      } else {
        message = locating
            ? 'Could not get your current GPS location. Please retry.\n$error'
            : 'Could not load nearby $_facility. Check your connection and retry.\n$error';
      }
      setState(() {
        _loading = false;
        _places = const [];
        _error = message;
        _settingsTarget = settings;
      });
    }
  }

  Future<void> _openSettings() async {
    try {
      final opened = _settingsTarget == _LocationSettingsTarget.location
          ? await Geolocator.openLocationSettings()
          : await Geolocator.openAppSettings();
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please open location settings manually.'),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please open location settings manually.'),
        ),
      );
    }
  }

  Future<void> _openDirections(NearbyPlaceResult place) async {
    final center = _userLocation;
    if (center == null) return;
    final opened = await DeepLinkNavigationService.openGoogleMaps(
      destinationLatitude: place.location.latitude,
      destinationLongitude: place.location.longitude,
      originLatitude: center.latitude,
      originLongitude: center.longitude,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No navigation app is available.')),
      );
    }
  }

  Future<void> _callPlace(String? phone) async {
    final number = phone?.trim();
    if (number == null || number.isEmpty) return;
    if (!await launchUrl(Uri(scheme: 'tel', path: number)) && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not dial $number')));
    }
  }

  Future<void> _showPlaceDetails(NearbyPlaceResult place) async {
    final distanceMeters = _userLocation == null
        ? null
        : Geolocator.distanceBetween(
            _userLocation!.latitude,
            _userLocation!.longitude,
            place.location.latitude,
            place.location.longitude,
          );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                place.name,
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 10),
              _DetailRow(icon: Icons.location_on_outlined, text: place.address),
              if (place.phone?.trim().isNotEmpty == true)
                _DetailRow(icon: Icons.phone_outlined, text: place.phone!),
              if (distanceMeters != null)
                _DetailRow(
                  icon: Icons.near_me_outlined,
                  text: '${(distanceMeters / 1000).toStringAsFixed(1)} km away',
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _callPlace(place.phone),
                      icon: const Icon(Icons.call_rounded),
                      label: const Text('Call'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _openDirections(place),
                      icon: const Icon(Icons.directions_rounded),
                      label: const Text('Directions'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scanButton() => OutlinedButton.icon(
    onPressed: _loading ? null : _scan,
    icon: const Icon(Icons.refresh_rounded, size: 18),
    label: Text(
      _loading
          ? 'Scanning...'
          : _error != null
          ? 'Retry scan'
          : 'Scan again',
    ),
  );

  String get _summary => _loading
      ? _userLocation == null
            ? 'Getting your current GPS location...'
            : 'Searching within 15 km...'
      : _error != null
      ? 'Scan unsuccessful'
      : '${_places.length} facilities found nearby';

  Widget _scanStatus() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_loading) ...[
        const LinearProgressIndicator(color: AppColors.primary),
        const SizedBox(height: 12),
        Text(_summary, textAlign: TextAlign.center),
      ] else if (_error != null) ...[
        const Icon(
          Icons.error_outline_rounded,
          color: AppColors.warning,
          size: 36,
        ),
        const SizedBox(height: 8),
        Text(_error!, textAlign: TextAlign.center),
        if (_settingsTarget != null)
          TextButton.icon(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_rounded),
            label: const Text('Settings'),
          ),
      ] else if (_places.isEmpty) ...[
        Icon(
          widget.type == NearbyPlaceType.hospitals
              ? Icons.local_hospital_outlined
              : Icons.medication_outlined,
          size: 42,
          color: AppColors.textLight,
        ),
        const SizedBox(height: 12),
        Text(
          'No $_facility found within 15 km',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'No facilities were returned for your current location. You can scan again.',
          textAlign: TextAlign.center,
        ),
      ],
      const SizedBox(height: 12),
      _scanButton(),
    ],
  );

  Widget _map(LatLng center) => Stack(
    children: [
      GoogleMap(
        initialCameraPosition: CameraPosition(target: center, zoom: 11),
        markers: _places
            .map(
              (place) => Marker(
                markerId: MarkerId(place.id),
                position: place.location,
                infoWindow: InfoWindow(
                  title: place.name,
                  snippet: place.address,
                ),
                onTap: () => _showPlaceDetails(place),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  widget.type == NearbyPlaceType.hospitals
                      ? BitmapDescriptor.hueRed
                      : BitmapDescriptor.hueOrange,
                ),
              ),
            )
            .toSet(),
        circles: {
          Circle(
            circleId: const CircleId('nearby-radius'),
            center: center,
            radius: PlacesApiService.nearbyRadiusMeters,
            strokeWidth: 2,
            strokeColor: AppColors.primary,
            fillColor: AppColors.primary.withValues(alpha: 0.08),
          ),
        },
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        zoomControlsEnabled: false,
      ),
      Positioned(
        top: 12,
        left: 16,
        right: 16,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$_title • 15 km'),
                if (!_loading && _error == null && _places.isNotEmpty)
                  Text(_summary),
                _scanStatus(),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final center = _userLocation;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          '$_title (15 km)',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: _showMap ? 'Show list' : 'Show map',
            onPressed: () => setState(() => _showMap = !_showMap),
            icon: Icon(_showMap ? Icons.view_list_rounded : Icons.map_rounded),
          ),
        ],
      ),
      body: _showMap && center != null
          ? _map(center)
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                _Header(type: widget.type, summary: _summary),
                const SizedBox(height: 16),
                _scanStatus(),
                const SizedBox(height: 16),
                if (center != null)
                  ..._places.map(
                    (place) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PlaceCard(
                        place: place,
                        distanceKm:
                            Geolocator.distanceBetween(
                              center.latitude,
                              center.longitude,
                              place.location.latitude,
                              place.location.longitude,
                            ) /
                            1000,
                        onDirections: () => _openDirections(place),
                        onCall: place.phone?.trim().isNotEmpty == true
                            ? () => _callPlace(place.phone)
                            : null,
                        onDetails: () => _showPlaceDetails(place),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _LocationFailure implements Exception {
  const _LocationFailure(this.message, [this.settingsTarget]);

  final String message;
  final _LocationSettingsTarget? settingsTarget;
}

class _Header extends StatelessWidget {
  const _Header({required this.type, required this.summary});

  final NearbyPlaceType type;
  final String summary;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.cardBorder),
    ),
    child: Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: AppColors.primaryLight,
          foregroundColor: AppColors.primary,
          child: Icon(
            type == NearbyPlaceType.hospitals
                ? Icons.local_hospital_rounded
                : Icons.medication_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                type == NearbyPlaceType.hospitals
                    ? 'Hospitals within 15 km'
                    : 'Pharmacies within 15 km',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                summary,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: AppColors.textGrey,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({
    required this.place,
    required this.distanceKm,
    required this.onDirections,
    required this.onCall,
    required this.onDetails,
  });

  final NearbyPlaceResult place;
  final double distanceKm;
  final VoidCallback onDirections;
  final VoidCallback? onCall;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onDetails,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              place.types.contains('hospital')
                  ? Icons.local_hospital_rounded
                  : Icons.medication_rounded,
              color: AppColors.primary,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  place.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  place.address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppColors.textGrey,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${distanceKm.toStringAsFixed(1)} km away',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    _StatusChip(isOpen: place.isOpen),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Directions',
                onPressed: onDirections,
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.directions_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
              if (onCall != null)
                IconButton(
                  tooltip: 'Call facility',
                  onPressed: onCall,
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.successLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.call_rounded,
                      color: AppColors.success,
                      size: 18,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textGrey),
          ),
        ),
      ],
    ),
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.isOpen});
  final bool? isOpen;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: isOpen == null
          ? AppColors.background
          : isOpen!
          ? AppColors.successLight
          : AppColors.warningLight,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      isOpen == null
          ? 'Hours unavailable'
          : isOpen!
          ? 'Open now'
          : 'Closed',
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: isOpen == null
            ? AppColors.textGrey
            : isOpen!
            ? AppColors.success
            : AppColors.warning,
      ),
    ),
  );
}
