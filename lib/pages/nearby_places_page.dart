import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../constants/colors.dart';
import '../models/models.dart';
import '../services/deep_link_navigation_service.dart';
import '../services/hospital_service.dart';
import '../services/places_api_service.dart';

enum NearbyPlaceType { hospitals, pharmacies }

class NearbyPlacesPage extends StatefulWidget {
  const NearbyPlacesPage({super.key, required this.type});
  final NearbyPlaceType type;

  @override
  State<NearbyPlacesPage> createState() => _NearbyPlacesPageState();
}

class _NearbyPlacesPageState extends State<NearbyPlacesPage> {
  static const _fallback = LatLng(23.8103, 90.4125);
  GoogleMapController? _mapController;
  LatLng _userLocation = _fallback;
  bool _showMap = false;
  bool _loadingPlaces = true;
  final _placesApi = PlacesApiService();
  final _hospitalService = HospitalService();
  StreamSubscription<QuerySnapshot>? _hospitalSubscription;
  List<NearbyPlaceResult> _apiPlaces = const [];
  List<HospitalModel> _registeredHospitals = const [];
  bool _locationReady = false;

  String get _title => widget.type == NearbyPlaceType.hospitals
      ? 'Nearby Hospitals'
      : 'Nearby Pharmacies';
  double get _radiusKm => widget.type == NearbyPlaceType.hospitals ? 15 : 5;

  @override
  void initState() {
    super.initState();
    _loadLocation();
    _loadNearbyPlaces(_fallback);
    if (widget.type == NearbyPlaceType.hospitals) {
      _hospitalSubscription = _hospitalService.approvedHospitalsStream().listen(
        (snapshot) {
          if (!mounted) return;
          setState(() {
            _registeredHospitals = snapshot.docs
                .map(HospitalModel.fromDoc)
                .where((hospital) => hospital.name.trim().isNotEmpty)
                .toList();
          });
        },
      );
    }
  }

  @override
  void dispose() {
    _placesApi.dispose();
    _hospitalSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: 100,
        ),
      );
      if (!mounted) return;
      setState(() {
        _userLocation = LatLng(position.latitude, position.longitude);
        _locationReady = true;
      });
      await _loadNearbyPlaces(_userLocation);
      await _mapController?.animateCamera(
        CameraUpdate.newLatLng(_userLocation),
      );
    } on Exception {
      // The curated fallback list remains available when location is unavailable.
    }
  }

  Future<void> _loadNearbyPlaces(LatLng center) async {
    try {
      final results = await _placesApi.nearby(
        center: center,
        type: widget.type == NearbyPlaceType.hospitals
            ? 'hospital'
            : 'pharmacy',
        radiusMeters: _radiusKm * 1000,
      );
      if (!mounted) return;
      setState(() {
        _apiPlaces = results.where((place) {
          final distance = Geolocator.distanceBetween(
            center.latitude,
            center.longitude,
            place.location.latitude,
            place.location.longitude,
          );
          return distance <= _radiusKm * 1000;
        }).toList();
        _loadingPlaces = false;
      });
    } on Exception {
      if (mounted) {
        setState(() => _loadingPlaces = false);
      }
    }
  }

  List<_Place> get _places {
    final registered = widget.type == NearbyPlaceType.hospitals
        ? _registeredHospitals
              .where((hospital) => hospital.lat != 0 && hospital.lon != 0)
              .map(
                (hospital) => _Place.registered(
                  hospital,
                  _distanceKm(
                    LatLng(hospital.lat, hospital.lon),
                    _userLocation,
                  ),
                ),
              )
              .where((place) => place.distanceKm <= _radiusKm)
              .toList()
        : <_Place>[];
    final googlePlaces = _apiPlaces
        .where((place) {
          final distance = Geolocator.distanceBetween(
            _userLocation.latitude,
            _userLocation.longitude,
            place.location.latitude,
            place.location.longitude,
          );
          return distance <= _radiusKm * 1000;
        })
        .map(
          (place) => _Place.google(
            place,
            _distanceKm(place.location, _userLocation),
            widget.type == NearbyPlaceType.hospitals
                ? Icons.local_hospital_rounded
                : Icons.medication_rounded,
          ),
        )
        .toList();
    return [...registered, ...googlePlaces]
      ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
  }

  double _distanceKm(LatLng first, LatLng second) =>
      Geolocator.distanceBetween(
        first.latitude,
        first.longitude,
        second.latitude,
        second.longitude,
      ) /
      1000;

  Future<void> _showHospitalDetails(HospitalModel hospital) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                hospital.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 12),
              _HospitalDetailRow(Icons.location_on_rounded, hospital.address),
              if (hospital.phone.trim().isNotEmpty)
                _HospitalDetailRow(Icons.phone_rounded, hospital.phone),
              if (hospital.email.trim().isNotEmpty)
                _HospitalDetailRow(Icons.email_rounded, hospital.email),
              _HospitalDetailRow(Icons.bed_rounded, '${hospital.beds} beds'),
              if (hospital.services.isNotEmpty)
                _HospitalDetailRow(
                  Icons.medical_services_rounded,
                  hospital.services.join(', '),
                ),
              if (hospital.diagnoses.isNotEmpty)
                _HospitalDetailRow(
                  Icons.local_hospital_rounded,
                  hospital.diagnoses.join(', '),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDirections(_Place place) async {
    final point = _placePoint(place);
    final opened = await DeepLinkNavigationService.openGoogleMaps(
      destinationLatitude: point.latitude,
      destinationLongitude: point.longitude,
      originLatitude: _userLocation.latitude,
      originLongitude: _userLocation.longitude,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No navigation app is available.')),
      );
    }
  }

  LatLng _placePoint(_Place place) {
    if (place.location != null) return place.location!;
    final index = _places.indexOf(place);
    return LatLng(
      _userLocation.latitude + (index + 1) * .004,
      _userLocation.longitude + (index.isEven ? .003 : -.003),
    );
  }

  Set<Marker> _markers() => _places.asMap().entries.map((entry) {
    final place = entry.value;
    return Marker(
      markerId: MarkerId('place-${entry.key}'),
      position: _placePoint(place),
      infoWindow: InfoWindow(title: place.name),
      icon: BitmapDescriptor.defaultMarkerWithHue(
        widget.type == NearbyPlaceType.hospitals
            ? BitmapDescriptor.hueRed
            : BitmapDescriptor.hueOrange,
      ),
    );
  }).toSet();

  @override
  Widget build(BuildContext context) {
    final places = _places;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('$_title within ${_radiusKm.toStringAsFixed(0)} km'),
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
      body: _showMap
          ? GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _userLocation,
                zoom: 13.8,
              ),
              onMapCreated: (controller) => _mapController = controller,
              markers: _markers(),
              myLocationEnabled: _locationReady,
              myLocationButtonEnabled: _locationReady,
              zoomControlsEnabled: false,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                _Header(type: widget.type),
                if (_loadingPlaces)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(
                      color: AppColors.primary,
                      minHeight: 2,
                    ),
                  ),
                const SizedBox(height: 16),
                if (!_loadingPlaces && places.isEmpty)
                  const _EmptyPlacesState()
                else
                  ...places.map(
                    (place) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PlaceCard(
                        place: place,
                        onDirections: () => _openDirections(place),
                        onDetails: place.hospital == null
                            ? null
                            : () => _showHospitalDetails(place.hospital!),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _EmptyPlacesState extends StatelessWidget {
  const _EmptyPlacesState();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.cardBorder),
    ),
    child: const Column(
      children: [
        Icon(Icons.location_off_rounded, size: 40, color: AppColors.textLight),
        SizedBox(height: 10),
        Text(
          'No places found nearby.',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: AppColors.textDark,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Allow location access and try again.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textGrey),
        ),
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.type});
  final NearbyPlaceType type;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.cardBorder),
    ),
    child: Row(
      children: [
        CircleAvatar(
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
          child: Text(
            type == NearbyPlaceType.hospitals
                ? 'Emergency-ready hospitals near you'
                : 'Open pharmacies near you',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
        ),
      ],
    ),
  );
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({
    required this.place,
    required this.onDirections,
    this.onDetails,
  });
  final _Place place;
  final VoidCallback onDirections;
  final VoidCallback? onDetails;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.cardBorder),
    ),
    child: InkWell(
      onTap: onDetails,
      borderRadius: BorderRadius.circular(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(place.icon, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  place.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  place.address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textGrey,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Text(
                      '${place.distanceKm.toStringAsFixed(1)} km',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textGrey,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusChip(isOpen: place.isOpen),
                    if (place.hospital != null) ...[
                      const SizedBox(width: 8),
                      const Text(
                        'Registered',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Open location in maps',
            onPressed: onDirections,
            icon: const Icon(
              Icons.directions_rounded,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    ),
  );
}

class _HospitalDetailRow extends StatelessWidget {
  const _HospitalDetailRow(this.icon, this.value);
  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(value, style: const TextStyle(color: AppColors.textDark)),
        ),
      ],
    ),
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.isOpen});
  final bool isOpen;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: isOpen ? AppColors.successLight : AppColors.warningLight,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      isOpen ? 'Open' : 'Closed',
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: isOpen ? AppColors.success : AppColors.warning,
      ),
    ),
  );
}

class _Place {
  _Place.google(NearbyPlaceResult place, this.distanceKm, this.icon)
    : name = place.name,
      address = place.address,
      isOpen = place.isOpen ?? true,
      location = place.location,
      hospital = null;

  _Place.registered(HospitalModel hospital, this.distanceKm)
    : name = hospital.name,
      address = hospital.address.isNotEmpty ? hospital.address : hospital.city,
      isOpen = true,
      icon = Icons.local_hospital_rounded,
      location = LatLng(hospital.lat, hospital.lon),
      hospital = hospital;

  final String name;
  final String address;
  final double distanceKm;
  final bool isOpen;
  final IconData icon;
  final LatLng? location;
  final HospitalModel? hospital;
}
