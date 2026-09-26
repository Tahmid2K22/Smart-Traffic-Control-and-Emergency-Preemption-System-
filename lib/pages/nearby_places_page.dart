import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../constants/colors.dart';
import '../services/deep_link_navigation_service.dart';
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
  List<NearbyPlaceResult> _apiPlaces = const [];
  bool _locationReady = false;

  final _hospitals = const [
    _Place('Dhaka Medical College Hospital', 'Secretariat Road, Dhaka', 1.2, true, Icons.local_hospital_rounded),
    _Place('Square Hospital', 'Panthapath, Dhaka', 2.8, true, Icons.local_hospital_rounded),
    _Place('Shaheed Suhrawardy Medical College', 'Sher-e-Bangla Nagar, Dhaka', 4.1, true, Icons.local_hospital_rounded),
    _Place('Ad-Din Hospital', 'Moghbazar, Dhaka', 5.7, false, Icons.local_hospital_rounded),
  ];
  final _pharmacies = const [
    _Place('Lazz Pharma', 'Dhanmondi 27, Dhaka', .8, true, Icons.medication_rounded),
    _Place('Popular Pharmacy', 'Panthapath, Dhaka', 1.5, true, Icons.medication_rounded),
    _Place('MediCare Pharmacy', 'Kalabagan, Dhaka', 2.4, false, Icons.medication_rounded),
  ];

  String get _title => widget.type == NearbyPlaceType.hospitals ? 'Nearby Hospitals' : 'Nearby Pharmacies';

  @override
  void initState() {
    super.initState();
    _loadLocation();
    _loadNearbyPlaces(_fallback);
  }

  @override
  void dispose() {
    _placesApi.dispose();
    super.dispose();
  }

  Future<void> _loadLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, distanceFilter: 100));
      if (!mounted) return;
      setState(() {
        _userLocation = LatLng(position.latitude, position.longitude);
        _locationReady = true;
      });
      await _loadNearbyPlaces(_userLocation);
      await _mapController?.animateCamera(CameraUpdate.newLatLng(_userLocation));
    } on Exception {
      // The curated fallback list remains available when location is unavailable.
    }
  }

  Future<void> _loadNearbyPlaces(LatLng center) async {
    try {
      final results = await _placesApi.nearby(
        center: center,
        type: widget.type == NearbyPlaceType.hospitals ? 'hospital' : 'pharmacy',
      );
      if (!mounted) return;
      setState(() {
        _apiPlaces = results;
        _loadingPlaces = false;
      });
    } on Exception {
      if (mounted) setState(() => _loadingPlaces = false);
    }
  }

  List<_Place> get _places {
    if (_apiPlaces.isNotEmpty) {
      return _apiPlaces.map((place) => _Place(
            place.name,
            place.address,
            Geolocator.distanceBetween(_userLocation.latitude, _userLocation.longitude, place.location.latitude, place.location.longitude) / 1000,
            place.isOpen ?? true,
            widget.type == NearbyPlaceType.hospitals ? Icons.local_hospital_rounded : Icons.medication_rounded,
            place.location,
          )).toList();
    }
    return widget.type == NearbyPlaceType.hospitals ? _hospitals : _pharmacies;
  }

  Future<void> _openDirections(_Place place) async {
    final point = _placePoint(place);
    final opened = await DeepLinkNavigationService.openGoogleMaps(destinationLatitude: point.latitude, destinationLongitude: point.longitude, originLatitude: _userLocation.latitude, originLongitude: _userLocation.longitude);
    if (!opened && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No navigation app is available.')));
  }

  LatLng _placePoint(_Place place) {
    if (place.location != null) return place.location!;
    final index = _places.indexOf(place);
    return LatLng(_userLocation.latitude + (index + 1) * .004, _userLocation.longitude + (index.isEven ? .003 : -.003));
  }

  Set<Marker> _markers() => _places.asMap().entries.map((entry) {
        final place = entry.value;
        return Marker(markerId: MarkerId('place-${entry.key}'), position: _placePoint(place), infoWindow: InfoWindow(title: place.name), icon: BitmapDescriptor.defaultMarkerWithHue(widget.type == NearbyPlaceType.hospitals ? BitmapDescriptor.hueRed : BitmapDescriptor.hueOrange));
      }).toSet();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(_title), backgroundColor: Colors.transparent, elevation: 0, actions: [IconButton(tooltip: _showMap ? 'Show list' : 'Show map', onPressed: () => setState(() => _showMap = !_showMap), icon: Icon(_showMap ? Icons.view_list_rounded : Icons.map_rounded))]),
      body: _showMap ? GoogleMap(initialCameraPosition: CameraPosition(target: _userLocation, zoom: 13.8), onMapCreated: (controller) => _mapController = controller, markers: _markers(), myLocationEnabled: _locationReady, myLocationButtonEnabled: _locationReady, zoomControlsEnabled: false) : ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [_Header(type: widget.type), if (_loadingPlaces) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator(color: AppColors.primary, minHeight: 2)), const SizedBox(height: 16), ..._places.map((place) => Padding(padding: const EdgeInsets.only(bottom: 12), child: _PlaceCard(place: place, onDirections: () => _openDirections(place))))]),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.type});
  final NearbyPlaceType type;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.cardBorder)), child: Row(children: [CircleAvatar(backgroundColor: AppColors.primaryLight, foregroundColor: AppColors.primary, child: Icon(type == NearbyPlaceType.hospitals ? Icons.local_hospital_rounded : Icons.medication_rounded)), const SizedBox(width: 12), Expanded(child: Text(type == NearbyPlaceType.hospitals ? 'Emergency-ready hospitals near you' : 'Open pharmacies near you', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark)))]));
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.place, required this.onDirections});
  final _Place place;
  final VoidCallback onDirections;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.cardBorder)), child: Row(children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(12)), child: Icon(place.icon, color: AppColors.primary)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(place.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark)), const SizedBox(height: 4), Text(place.address, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textGrey)), const SizedBox(height: 7), Row(children: [Text('${place.distanceKm.toStringAsFixed(1)} km', style: const TextStyle(fontSize: 12, color: AppColors.textGrey)), const SizedBox(width: 8), _StatusChip(isOpen: place.isOpen)])])), const SizedBox(width: 8), IconButton(tooltip: 'Open directions', onPressed: onDirections, icon: const Icon(Icons.directions_rounded, color: AppColors.primary))]));
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.isOpen});
  final bool isOpen;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: isOpen ? AppColors.successLight : AppColors.warningLight, borderRadius: BorderRadius.circular(10)), child: Text(isOpen ? 'Open' : 'Closed', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: isOpen ? AppColors.success : AppColors.warning)));
}

class _Place {
  const _Place(this.name, this.address, this.distanceKm, this.isOpen, this.icon, [this.location]);
  final String name;
  final String address;
  final double distanceKm;
  final bool isOpen;
  final IconData icon;
  final LatLng? location;
}
