import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../constants/colors.dart';
import '../../services/map_search_service.dart';

class EmergencyServiceMapSelection {
  const EmergencyServiceMapSelection({required this.location, this.address});

  final LatLng location;
  final String? address;
}

class EmergencyServiceLocationPickerPage extends StatefulWidget {
  const EmergencyServiceLocationPickerPage({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialAddress,
  });

  final double? initialLatitude;
  final double? initialLongitude;
  final String? initialAddress;

  @override
  State<EmergencyServiceLocationPickerPage> createState() =>
      _EmergencyServiceLocationPickerPageState();
}

class _EmergencyServiceLocationPickerPageState
    extends State<EmergencyServiceLocationPickerPage> {
  static const _defaultCenter = LatLng(22.8996, 89.5023);

  final _searchController = TextEditingController();
  final _mapSearch = MapSearchService();
  Timer? _searchTimer;
  GoogleMapController? _mapController;
  LatLng _center = _defaultCenter;
  LatLng? _selectedLocation;
  String? _selectedAddress;
  List<MapSearchSuggestion> _suggestions = const [];
  int _searchRequest = 0;
  bool _searching = false;
  bool _resolvingAddress = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final latitude = widget.initialLatitude;
    final longitude = widget.initialLongitude;
    if (latitude != null &&
        longitude != null &&
        latitude.isFinite &&
        longitude.isFinite &&
        latitude.abs() <= 90 &&
        longitude.abs() <= 180) {
      _center = LatLng(latitude, longitude);
      _selectedLocation = _center;
      _selectedAddress = widget.initialAddress;
      _searchController.text = widget.initialAddress ?? '';
    }
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    _mapSearch.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _searchTimer?.cancel();
    final request = ++_searchRequest;
    if (query.trim().isEmpty) {
      setState(() {
        _suggestions = const [];
        _searching = false;
        _error = null;
      });
      return;
    }
    _searchTimer = Timer(const Duration(milliseconds: 350), () async {
      setState(() {
        _searching = true;
        _error = null;
      });
      try {
        final suggestions = await _mapSearch.search(query);
        if (!mounted || request != _searchRequest) return;
        setState(() => _suggestions = suggestions);
      } on Exception catch (error) {
        if (!mounted || request != _searchRequest) return;
        setState(() {
          _suggestions = const [];
          _error = 'Could not search this location: $error';
        });
      } finally {
        if (mounted && request == _searchRequest) {
          setState(() => _searching = false);
        }
      }
    });
  }

  Future<void> _selectSuggestion(MapSearchSuggestion suggestion) async {
    final location = suggestion.location;
    setState(() {
      _selectedLocation = location;
      _selectedAddress = suggestion.displayName;
      _center = location;
      _searchController.text = suggestion.displayName;
      _suggestions = const [];
      _error = null;
    });
    await _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(location, 15),
    );
  }

  void _selectMapPoint(LatLng location) {
    setState(() {
      _selectedLocation = location;
      _selectedAddress = null;
      _center = location;
      _suggestions = const [];
      _error = null;
    });
  }

  Future<String?> _reverseGeocode(LatLng location) async {
    final marks = await Geocoding().placemarkFromCoordinates(
      location.latitude,
      location.longitude,
    );
    if (marks.isEmpty) return null;
    final mark = marks.first;
    final parts =
        [mark.street, mark.subLocality, mark.locality, mark.administrativeArea]
            .whereType<String>()
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty);
    return parts.toSet().join(', ');
  }

  Future<void> _confirmLocation() async {
    final location = _selectedLocation;
    if (location == null || _resolvingAddress) return;
    setState(() => _resolvingAddress = true);
    String? address = _selectedAddress;
    if (address == null || address.isEmpty) {
      try {
        address = await _reverseGeocode(location);
      } on Exception catch (error) {
        debugPrint('Could not resolve the selected map address: $error');
      }
    }
    if (!mounted) return;
    Navigator.of(
      context,
    ).pop(EmergencyServiceMapSelection(location: location, address: address));
  }

  @override
  Widget build(BuildContext context) {
    final location = _selectedLocation;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search and pin location'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _center, zoom: 11),
            onMapCreated: (controller) => _mapController = controller,
            onTap: _selectMapPoint,
            markers: {
              if (location != null)
                Marker(
                  markerId: const MarkerId('service-location'),
                  position: location,
                  draggable: true,
                  onDragEnd: _selectMapPoint,
                ),
            },
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Column(
              children: [
                Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search address, station or landmark',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                if (_suggestions.isNotEmpty || _error != null)
                  Card(
                    margin: const EdgeInsets.only(top: 6),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: _error != null
                          ? Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(_error!),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: _suggestions.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final suggestion = _suggestions[index];
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(
                                    Icons.place_outlined,
                                    color: AppColors.primary,
                                  ),
                                  title: Text(
                                    suggestion.displayName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () => _selectSuggestion(suggestion),
                                );
                              },
                            ),
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      location == null
                          ? 'Search for a place or tap the map to pin it.'
                          : 'Selected: ${location.latitude.toStringAsFixed(6)}, '
                                '${location.longitude.toStringAsFixed(6)}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: location == null || _resolvingAddress
                            ? null
                            : _confirmLocation,
                        icon: _resolvingAddress
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_rounded),
                        label: const Text('Use this location'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
