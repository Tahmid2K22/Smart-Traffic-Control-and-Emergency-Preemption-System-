import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../constants/colors.dart';
import '../models/models.dart';
import '../services/places_api_service.dart';
import '../services/request_service.dart';
import '../services/hospital_service.dart';
import 'tracking_page.dart';

class AmbulanceBookingScreen extends StatefulWidget {
  const AmbulanceBookingScreen({super.key});

  @override
  State<AmbulanceBookingScreen> createState() => _AmbulanceBookingScreenState();
}

enum _BookingMode { planning, pickingDestination, pickingPickup }

class _AmbulanceBookingScreenState extends State<AmbulanceBookingScreen> {
  static const _defaultCenter = LatLng(23.8103, 90.4125);

  final _pickupController = TextEditingController(text: 'Detecting current location...');
  final _destinationController = TextEditingController();
  final _destinationFocus = FocusNode();
  Geocoding? _geocoder;
  final _placesApi = PlacesApiService();
  Timer? _autocompleteTimer;
  List<PlaceSuggestion> _destinationSuggestions = const [];
  GoogleMapController? _mapController;
  LatLng? _pickup;
  LatLng? _destination;
  LatLng _mapCenter = _defaultCenter;
  _BookingMode _mode = _BookingMode.planning;
  bool _locationReady = false;
  bool _isSearching = false;
  int _selectedAmbulance = 0;

  final _tiers = const [
    _AmbulanceTier('Basic Ambulance', 'Standard transport', 'First aid, stretcher', '4 min', 800, 35, Icons.local_shipping_rounded, Color(0xFF4A90E2)),
    _AmbulanceTier('ICU Ambulance', 'Critical care equipped', 'Ventilator, monitor, nurse', '7 min', 1800, 55, Icons.monitor_heart_rounded, AppColors.primary),
    _AmbulanceTier('Oxygen / Neonatal', 'Specialized transport', 'Oxygen, incubator, specialist', '9 min', 2200, 65, Icons.air_rounded, Color(0xFF009688)),
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _destinationController.dispose();
    _destinationFocus.dispose();
    _autocompleteTimer?.cancel();
    _placesApi.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, distanceFilter: 50),
    );
    if (!mounted) return;
    final point = LatLng(position.latitude, position.longitude);
    setState(() {
      _pickup = point;
      _mapCenter = point;
      _locationReady = true;
      _pickupController.text = 'Current location';
    });
    await _mapController?.animateCamera(CameraUpdate.newLatLng(point));
    await _updateAddress(point, isPickup: true);
  }

  Future<void> _applyMapStyle(GoogleMapController controller) async {
    _mapController = controller;
    final style = await rootBundle.loadString('assets/map_style.json');
    // Retain this controller API for compatibility with older mobile plugin versions.
    // ignore: deprecated_member_use
    await controller.setMapStyle(style);
  }

  Future<void> _updateAddress(LatLng point, {required bool isPickup}) async {
    try {
      _geocoder ??= Geocoding();
      final marks = await _geocoder!.placemarkFromCoordinates(point.latitude, point.longitude);
      if (!mounted || marks.isEmpty) return;
      final mark = marks.first;
      final address = [mark.street, mark.locality, mark.administrativeArea]
          .where((part) => part != null && part.trim().isNotEmpty)
          .join(', ');
      if (isPickup) {
        _pickupController.text = address.isEmpty ? 'Current location' : address;
      } else {
        _destinationController.text = address.isEmpty ? 'Pin location' : address;
      }
      setState(() {});
    } on Exception {
      // Geocoding failure must not block map-based booking.
    }
  }

  Future<void> _geocode(String value, {required bool isPickup}) async {
    if (value.trim().isEmpty) return;
    setState(() => _isSearching = true);
    try {
      _geocoder ??= Geocoding();
      final locations = await _geocoder!.locationFromAddress(value.trim());
      if (!mounted || locations.isEmpty) return;
      final point = LatLng(locations.first.latitude, locations.first.longitude);
      setState(() {
        if (isPickup) {
          _pickup = point;
        } else {
          _destination = point;
          _destinationController.text = value.trim();
        }
        _mapCenter = point;
      });
      await _mapController?.animateCamera(CameraUpdate.newLatLng(point));
    } on Exception {
      if (mounted) _showMessage('Location not found. Try a more specific address.');
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _onDestinationChanged(String value) {
    _autocompleteTimer?.cancel();
    if (value.trim().length < 2 || _pickup == null || !_placesApi.isConfigured) {
      setState(() => _destinationSuggestions = const []);
      return;
    }
    _autocompleteTimer = Timer(const Duration(milliseconds: 400), () async {
      try {
        final suggestions = await _placesApi.autocomplete(input: value, bias: _pickup!);
        if (mounted && _destinationController.text == value) {
          setState(() => _destinationSuggestions = suggestions);
        }
      } on Exception {
        if (mounted) setState(() => _destinationSuggestions = const []);
      }
    });
  }

  Future<void> _selectDestinationSuggestion(PlaceSuggestion suggestion) async {
    NearbyPlaceResult? place;
    try {
      place = await _placesApi.getPlace(suggestion.placeId);
    } on Exception {
      if (mounted) _showMessage('Place details are temporarily unavailable.');
      return;
    }
    if (!mounted || place == null) return;
    final resolvedPlace = place;
    setState(() {
      _destination = resolvedPlace.location;
      _mapCenter = resolvedPlace.location;
      _destinationController.text = resolvedPlace.address;
      _destinationSuggestions = const [];
    });
    await _mapController?.animateCamera(CameraUpdate.newLatLng(resolvedPlace.location));
  }

  void _startMapPicking({required bool pickup}) {
    setState(() {
      _mode = pickup ? _BookingMode.pickingPickup : _BookingMode.pickingDestination;
      _mapCenter = pickup ? (_pickup ?? _defaultCenter) : (_destination ?? _mapCenter);
    });
    _mapController?.animateCamera(CameraUpdate.newLatLng(_mapCenter));
  }

  Future<void> _onCameraIdle() async {
    if (_mode == _BookingMode.planning) return;
    await _updateAddress(_mapCenter, isPickup: _mode == _BookingMode.pickingPickup);
  }

  void _confirmMapLocation() {
    setState(() {
      if (_mode == _BookingMode.pickingPickup) {
        _pickup = _mapCenter;
      } else {
        _destination = _mapCenter;
      }
      _mode = _BookingMode.planning;
    });
  }

  Future<void> _recenter() async {
    final point = _pickup ?? _defaultCenter;
    await _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: point, zoom: 15.5)),
    );
  }

  Future<void> _requestAmbulance() async {
    final pickup = _pickup;
    final destination = _destination;
    if (pickup == null || destination == null) {
      _showMessage('Add a pickup and destination before booking.');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('You must be logged in to book.');
      return;
    }

    // Show loading overlay
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
    );

    try {
      // Fetch user profile for name and phone
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data() ?? {};
      final userName = data['name'] ?? user.displayName ?? 'User';
      final userPhone = data['phone'] ?? '';

      // Create request in Supabase
      final requestId = await RequestService.createRequest(
        userFirebaseUid: user.uid,
        userName: userName,
        userPhone: userPhone,
        ambulanceType: _tiers[_selectedAmbulance].name,
        pickupLat: pickup.latitude,
        pickupLng: pickup.longitude,
        pickupAddress: _pickupController.text,
        destinationLat: destination.latitude,
        destinationLng: destination.longitude,
        destinationAddress: _destinationController.text,
        estimatedFare: _estimatedFare,
        distanceKm: _distanceKm,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loading

      // Navigate to tracking page
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => TrackingPage(requestId: requestId, isDriver: false),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loading
      _showMessage('Failed to book ambulance. Try again.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  double get _distanceKm {
    if (_pickup == null || _destination == null) return 0;
    return Geolocator.distanceBetween(
          _pickup!.latitude,
          _pickup!.longitude,
          _destination!.latitude,
          _destination!.longitude,
        ) /
        1000;
  }

  int get _estimatedFare =>
      (_tiers[_selectedAmbulance].baseFare + _distanceKm * _tiers[_selectedAmbulance].perKm).round();

  Set<Marker> _markers() {
    final markers = <Marker>{};
    if (_pickup != null) {
      markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: _pickup!,
        infoWindow: const InfoWindow(title: 'Pickup location'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ));
          // Removed simulated ambulance markers
    }
    if (_destination != null && _mode == _BookingMode.planning) {
      markers.add(Marker(
        markerId: const MarkerId('destination'),
        position: _destination!,
        infoWindow: const InfoWindow(title: 'Destination'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ));
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final picking = _mode != _BookingMode.planning;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Request ambulance'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(target: _defaultCenter, zoom: 14.5),
            onMapCreated: _applyMapStyle,
            onCameraMove: (position) => _mapCenter = position.target,
            onCameraIdle: _onCameraIdle,
            markers: _markers(),
            myLocationEnabled: _locationReady,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),
          if (picking) const _CenterPin(),
          if (picking)
            Positioned(
              top: 16,
              left: 16,
              child: _MapActionButton(
                icon: Icons.close_rounded,
                label: 'Close map picker',
                onPressed: () => setState(() => _mode = _BookingMode.planning),
              ),
            )
          else
            Positioned(
              top: 16,
              right: 16,
              child: _MapActionButton(icon: Icons.my_location_rounded, label: 'Recenter map', onPressed: _recenter),
            ),
          if (picking)
            _MapPinSheet(
              isPickup: _mode == _BookingMode.pickingPickup,
              address: _mode == _BookingMode.pickingPickup ? _pickupController.text : _destinationController.text,
              onConfirm: _confirmMapLocation,
            )
          else
            DraggableScrollableSheet(
              initialChildSize: .57,
              minChildSize: .40,
              maxChildSize: .88,
              snap: true,
              snapSizes: const [.57, .88],
              builder: (context, scrollController) => _TripPlanningSheet(
                scrollController: scrollController,
                pickupController: _pickupController,
                destinationController: _destinationController,
                destinationFocus: _destinationFocus,
                isSearching: _isSearching,
                destinationSuggestions: _destinationSuggestions,
                tiers: _tiers,
                selectedIndex: _selectedAmbulance,
                distanceKm: _distanceKm,
                estimatedFare: _estimatedFare,
                onPickupSubmitted: (value) => _geocode(value, isPickup: true),
                onDestinationSubmitted: (value) => _geocode(value, isPickup: false),
                onDestinationChanged: _onDestinationChanged,
                onSuggestionSelected: _selectDestinationSuggestion,
                onRecentSelected: (value) => _geocode(value, isPickup: false),
                onSetPickupOnMap: () => _startMapPicking(pickup: true),
                onSetDestinationOnMap: () => _startMapPicking(pickup: false),
                onSelected: (index) => setState(() => _selectedAmbulance = index),
                onRequest: _requestAmbulance,
                onHospitalSelected: (hospital) {
                  final point = LatLng(hospital.lat, hospital.lon);
                  setState(() {
                    _destination = point;
                    _mapCenter = point;
                    _destinationController.text = hospital.name;
                  });
                  _mapController?.animateCamera(CameraUpdate.newLatLng(point));
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _TripPlanningSheet extends StatelessWidget {
  const _TripPlanningSheet({
    required this.scrollController,
    required this.pickupController,
    required this.destinationController,
    required this.destinationFocus,
    required this.isSearching,
    required this.destinationSuggestions,
    required this.tiers,
    required this.selectedIndex,
    required this.distanceKm,
    required this.estimatedFare,
    required this.onPickupSubmitted,
    required this.onDestinationSubmitted,
    required this.onDestinationChanged,
    required this.onSuggestionSelected,
    required this.onRecentSelected,
    required this.onSetPickupOnMap,
    required this.onSetDestinationOnMap,
    required this.onSelected,
    required this.onRequest,
    // hospital destination
    required this.onHospitalSelected,
  });

  final ScrollController scrollController;
  final TextEditingController pickupController;
  final TextEditingController destinationController;
  final FocusNode destinationFocus;
  final bool isSearching;
  final List<PlaceSuggestion> destinationSuggestions;
  final List<_AmbulanceTier> tiers;
  final int selectedIndex;
  final double distanceKm;
  final int estimatedFare;
  final ValueChanged<String> onPickupSubmitted;
  final ValueChanged<String> onDestinationSubmitted;
  final ValueChanged<String> onDestinationChanged;
  final ValueChanged<PlaceSuggestion> onSuggestionSelected;
  final ValueChanged<String> onRecentSelected;
  final VoidCallback onSetPickupOnMap;
  final VoidCallback onSetDestinationOnMap;
  final ValueChanged<int> onSelected;
  final VoidCallback onRequest;
  final void Function(HospitalModel) onHospitalSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      elevation: 12,
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: AppColors.cardBorder, borderRadius: BorderRadius.circular(4)))),
          const SizedBox(height: 18),
          const Text('Plan your trip', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          const SizedBox(height: 4),
          const Text('Choose pickup and destination without map API searches.', style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
          const SizedBox(height: 16),
          _AddressField(controller: pickupController, icon: Icons.my_location_rounded, color: AppColors.infoBlue, hint: 'Pickup location', onSubmitted: onPickupSubmitted, onMapTap: onSetPickupOnMap),
          const SizedBox(height: 8),
          _AddressField(controller: destinationController, focusNode: destinationFocus, icon: Icons.location_on_rounded, color: AppColors.primary, hint: 'Where to?', onChanged: onDestinationChanged, onSubmitted: onDestinationSubmitted, onMapTap: onSetDestinationOnMap),
          if (destinationSuggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(color: AppColors.white, border: Border.all(color: AppColors.cardBorder), borderRadius: BorderRadius.circular(12)),
              child: Column(children: destinationSuggestions.map((suggestion) => ListTile(dense: true, leading: const Icon(Icons.location_on_outlined, color: AppColors.primary), title: Text(suggestion.description), onTap: () => onSuggestionSelected(suggestion))).toList()),
            ),
          if (isSearching) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(minHeight: 2)),
          const SizedBox(height: 14),
          Row(children: [Expanded(child: _QuickAction(icon: Icons.push_pin_rounded, label: 'Set on map', onTap: onSetDestinationOnMap)), const SizedBox(width: 8), const Expanded(child: _QuickAction(icon: Icons.star_rounded, label: 'Saved places')), const SizedBox(width: 8), const Expanded(child: _QuickAction(icon: Icons.public_rounded, label: 'Different city'))]),
          const SizedBox(height: 16),
          // ── Approved Hospitals ─────────────────────────────────────────────
          const Text('Select Hospital Destination',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          const SizedBox(height: 4),
          const Text('Only admin-approved hospitals are shown.',
              style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
          const SizedBox(height: 10),
          _ApprovedHospitalList(onSelected: onHospitalSelected),
          const SizedBox(height: 12),
          const Text('Choose ambulance type', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          const SizedBox(height: 10),
          ...List.generate(tiers.length, (index) => Padding(padding: const EdgeInsets.only(bottom: 9), child: _TierCard(tier: tiers[index], selected: index == selectedIndex, onTap: () => onSelected(index)))),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(distanceKm > 0 ? '${distanceKm.toStringAsFixed(1)} km estimated' : 'Distance after destination', style: const TextStyle(color: AppColors.textGrey)), Text('৳$estimatedFare estimated', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textDark))]),
          const SizedBox(height: 14),
          SizedBox(height: 54, child: FilledButton.icon(onPressed: onRequest, icon: const Icon(Icons.emergency_rounded), label: const Text('Book Ambulance', style: TextStyle(fontWeight: FontWeight.w700)), style: FilledButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))))),
        ],
      ),
    );
  }
}

class _MapPinSheet extends StatelessWidget {
  const _MapPinSheet({required this.isPickup, required this.address, required this.onConfirm});
  final bool isPickup;
  final String address;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Material(
        color: AppColors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        elevation: 12,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(isPickup ? 'Set your pickup' : 'Set your destination', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textDark)),
            const SizedBox(height: 4),
            const Text('Drag the map to move the pin', style: TextStyle(color: AppColors.textGrey)),
            const SizedBox(height: 12),
            Row(children: [const Icon(Icons.location_on_rounded, color: AppColors.primary), const SizedBox(width: 8), Expanded(child: Text(address.isEmpty ? 'Pin location' : address, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textDark)))]),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, height: 50, child: FilledButton(onPressed: onConfirm, style: FilledButton.styleFrom(backgroundColor: AppColors.textDark, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))), child: Text(isPickup ? 'Confirm pickup' : 'Confirm destination'))),
          ]),
        ),
      ),
    );
  }
}

class _CenterPin extends StatelessWidget {
  const _CenterPin();
  @override
  Widget build(BuildContext context) => IgnorePointer(child: Center(child: Padding(padding: const EdgeInsets.only(bottom: 24), child: SvgPicture.asset('assets/map_pin.svg', width: 30, height: 38))));
}

class _AddressField extends StatelessWidget {
  const _AddressField({required this.controller, required this.icon, required this.color, required this.hint, required this.onSubmitted, required this.onMapTap, this.onChanged, this.focusNode});
  final TextEditingController controller;
  final FocusNode? focusNode;
  final IconData icon;
  final Color color;
  final String hint;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String>? onChanged;
  final VoidCallback onMapTap;
  @override
  Widget build(BuildContext context) => TextField(controller: controller, focusNode: focusNode, textInputAction: TextInputAction.search, onChanged: onChanged, onSubmitted: onSubmitted, decoration: InputDecoration(prefixIcon: Icon(icon, color: color, size: 20), suffixIcon: IconButton(onPressed: onMapTap, tooltip: 'Set on map', icon: const Icon(Icons.push_pin_outlined)), hintText: hint, filled: true, fillColor: AppColors.background, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12)));
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: Container(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4), decoration: BoxDecoration(border: Border.all(color: AppColors.cardBorder), borderRadius: BorderRadius.circular(12)), child: Column(children: [Icon(icon, size: 19, color: AppColors.textDark), const SizedBox(height: 4), Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: AppColors.textGrey))])));
}

class _TierCard extends StatelessWidget {
  const _TierCard({required this.tier, required this.selected, required this.onTap});
  final _AmbulanceTier tier;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(14), child: AnimatedContainer(duration: const Duration(milliseconds: 180), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: selected ? tier.color.withValues(alpha: .08) : AppColors.white, border: Border.all(color: selected ? tier.color : AppColors.cardBorder, width: selected ? 1.5 : 1), borderRadius: BorderRadius.circular(14)), child: Row(children: [CircleAvatar(backgroundColor: tier.color.withValues(alpha: .12), foregroundColor: tier.color, child: Icon(tier.icon, size: 20)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tier.name, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark)), const SizedBox(height: 2), Text(tier.equipment, style: const TextStyle(fontSize: 11, color: AppColors.textGrey))])), Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(tier.eta, style: TextStyle(fontWeight: FontWeight.w700, color: tier.color)), Text(tier.subtitle, style: const TextStyle(fontSize: 10, color: AppColors.textLight))])])));
}

class _MapActionButton extends StatelessWidget {
  const _MapActionButton({required this.icon, required this.label, required this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Semantics(button: true, label: label, child: FloatingActionButton(heroTag: label, mini: true, backgroundColor: AppColors.white, foregroundColor: AppColors.textDark, onPressed: onPressed, child: Icon(icon)));
}

class _AmbulanceTier {
  const _AmbulanceTier(this.name, this.subtitle, this.equipment, this.eta, this.baseFare, this.perKm, this.icon, this.color);
  final String name;
  final String subtitle;
  final String equipment;
  final String eta;
  final int baseFare;
  final int perKm;
  final IconData icon;
  final Color color;
}

// ── Approved hospital list (live Firestore stream) ────────────────────────────

class _ApprovedHospitalList extends StatefulWidget {
  const _ApprovedHospitalList({required this.onSelected});
  final void Function(HospitalModel) onSelected;

  @override
  State<_ApprovedHospitalList> createState() => _ApprovedHospitalListState();
}

class _ApprovedHospitalListState extends State<_ApprovedHospitalList> {
  final _service = HospitalService();
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _service.approvedHospitalsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 2, color: AppColors.primary),
          );
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: const Text(
              'No approved hospitals available yet.',
              style: TextStyle(fontSize: 12, color: AppColors.textGrey),
            ),
          );
        }
        final hospitals =
            docs.map((d) => HospitalModel.fromDoc(d)).toList();
        return Column(
          children: hospitals.map((h) {
            final isSelected = _selectedId == h.id;
            return GestureDetector(
              onTap: () {
                setState(() => _selectedId = h.id);
                widget.onSelected(h);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.06)
                      : AppColors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.cardBorder,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.local_hospital_rounded,
                        color: AppColors.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            h.name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${h.city}  •  ${h.beds} beds',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textGrey,
                            ),
                          ),
                          if (h.services.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Wrap(
                                spacing: 4,
                                children: h.services.take(3).map((s) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.08),
                                      borderRadius:
                                          BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      s,
                                      style: const TextStyle(
                                          fontSize: 9,
                                          color: AppColors.primary),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textLight,
                      size: 20,
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
