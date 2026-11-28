import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/colors.dart';
import '../models/emergency_service_location.dart';
import '../services/deep_link_navigation_service.dart';
import '../services/emergency_service_directory_service.dart';

class EmergencyServicesPage extends StatefulWidget {
  const EmergencyServicesPage({super.key});

  @override
  State<EmergencyServicesPage> createState() => _EmergencyServicesPageState();
}

class _EmergencyServicesPageState extends State<EmergencyServicesPage> {
  final _directory = EmergencyServiceDirectoryService();

  LatLng? _userLocation;
  List<EmergencyServiceLocation> _nearbyServices = const [];
  EmergencyServiceCategory? _selectedCategory;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _error = null;
      _nearbyServices = const [];
      _userLocation = null;
    });

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const _NearbyServiceFailure(
          'Turn on location services to find 999 services nearby.',
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        throw const _NearbyServiceFailure(
          'Allow location access to find 999 services near you.',
        );
      }

      final cachedPosition = await Geolocator.getLastKnownPosition();
      List<EmergencyServiceLocation>? services;
      if (cachedPosition != null && _isValidPosition(cachedPosition)) {
        final cachedLocation = LatLng(
          cachedPosition.latitude,
          cachedPosition.longitude,
        );
        setState(() => _userLocation = cachedLocation);
        services = await _directory.fetchActive();
        _applyNearbyServices(cachedLocation, services);
      }

      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 8),
          ),
        );
        if (!_isValidPosition(position)) {
          throw const _NearbyServiceFailure(
            'GPS returned an invalid location. Please retry outdoors.',
          );
        }
        final location = LatLng(position.latitude, position.longitude);
        services ??= await _directory.fetchActive();
        if (!mounted) return;
        setState(() => _userLocation = location);
        _applyNearbyServices(location, services);
      } on TimeoutException {
        if (services == null) rethrow;
      } on _NearbyServiceFailure catch (error) {
        if (services == null) rethrow;
        debugPrint('Current location refresh failed: ${error.message}');
      } on Exception catch (error) {
        if (services == null) rethrow;
        debugPrint('Current location refresh failed: $error');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is _NearbyServiceFailure
            ? error.message
            : error is TimeoutException
            ? 'Could not get your location within 8 seconds. Please retry.'
            : 'Could not load nearby 999 services. Please retry.\n$error';
      });
    }
  }

  bool _isValidPosition(Position position) {
    final age = DateTime.now().difference(position.timestamp);
    return position.latitude.isFinite &&
        position.longitude.isFinite &&
        position.latitude.abs() <= 90 &&
        position.longitude.abs() <= 180 &&
        age >= const Duration(minutes: -2) &&
        age <= const Duration(minutes: 10);
  }

  void _applyNearbyServices(
    LatLng center,
    Iterable<EmergencyServiceLocation> services,
  ) {
    if (!mounted) return;
    setState(() {
      _userLocation = center;
      _nearbyServices = EmergencyServiceDirectoryService.withinRadius(
        services: services,
        center: center,
      );
      _loading = false;
      _error = null;
    });
  }

  List<EmergencyServiceLocation> get _visibleServices {
    final category = _selectedCategory;
    if (category == null) return _nearbyServices;
    return _nearbyServices
        .where((service) => service.category == category)
        .toList();
  }

  String get _summary => _loading
      ? _userLocation == null
            ? 'Finding your location...'
            : 'Refreshing GPS location...'
      : _error != null
      ? 'Could not load services'
      : '${_visibleServices.length} services within 15 km';

  Future<void> _showDetails(EmergencyServiceLocation service) async {
    final center = _userLocation;
    final distanceMeters = center == null
        ? null
        : Geolocator.distanceBetween(
            center.latitude,
            center.longitude,
            service.latitude,
            service.longitude,
          );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                service.name,
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              Text(
                service.category.label,
                style: const TextStyle(color: AppColors.primary),
              ),
              const SizedBox(height: 12),
              _DetailLine(
                icon: Icons.location_on_outlined,
                text: service.address,
              ),
              if (service.phone.isNotEmpty)
                _DetailLine(icon: Icons.phone_outlined, text: service.phone),
              if (service.description.isNotEmpty)
                _DetailLine(
                  icon: Icons.info_outline,
                  text: service.description,
                ),
              if (distanceMeters != null)
                _DetailLine(
                  icon: Icons.near_me_outlined,
                  text: '${(distanceMeters / 1000).toStringAsFixed(1)} km away',
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (service.phone.isNotEmpty)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _callService(service.phone),
                        icon: const Icon(Icons.call_rounded),
                        label: const Text('Call'),
                      ),
                    ),
                  if (service.phone.isNotEmpty) const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _openDirections(service),
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

  Future<void> _callService(String phone) async {
    if (!await launchUrl(Uri(scheme: 'tel', path: phone)) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the phone dialer.')),
      );
    }
  }

  Future<void> _openDirections(EmergencyServiceLocation service) async {
    final center = _userLocation;
    if (center == null) return;
    final opened = await DeepLinkNavigationService.openGoogleMaps(
      destinationLatitude: service.latitude,
      destinationLongitude: service.longitude,
      originLatitude: center.latitude,
      originLongitude: center.longitude,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No navigation app is available.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = _visibleServices;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('999 Services'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Scan again',
            onPressed: _loading ? null : _scan,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            _summary,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _categoryChip('All', null),
                for (final category in EmergencyServiceCategory.values)
                  _categoryChip(category.label, category),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_loading) ...[
            const LinearProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 12),
            Text(
              _userLocation == null
                  ? 'Finding your current location...'
                  : 'Showing nearby results while GPS refreshes...',
              textAlign: TextAlign.center,
            ),
          ] else if (_error != null) ...[
            _EmptyState(
              icon: Icons.location_off_outlined,
              message: _error!,
              onRetry: _scan,
            ),
          ] else if (services.isEmpty) ...[
            _EmptyState(
              icon: Icons.emergency_outlined,
              message: _selectedCategory == null
                  ? 'No 999 services found within 15 km.'
                  : 'No ${_selectedCategory!.label.toLowerCase()} found within 15 km.',
              onRetry: _scan,
            ),
          ] else ...[
            for (final service in services)
              _EmergencyServiceCard(
                service: service,
                distanceKm:
                    Geolocator.distanceBetween(
                      _userLocation!.latitude,
                      _userLocation!.longitude,
                      service.latitude,
                      service.longitude,
                    ) /
                    1000,
                onTap: () => _showDetails(service),
              ),
          ],
        ],
      ),
    );
  }

  Widget _categoryChip(String label, EmergencyServiceCategory? category) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: _selectedCategory == category,
          onSelected: (_) => setState(() => _selectedCategory = category),
          selectedColor: AppColors.primaryLight,
          labelStyle: TextStyle(
            color: _selectedCategory == category
                ? AppColors.primary
                : AppColors.textDark,
          ),
        ),
      );
}

class _EmergencyServiceCard extends StatelessWidget {
  const _EmergencyServiceCard({
    required this.service,
    required this.distanceKm,
    required this.onTap,
  });

  final EmergencyServiceLocation service;
  final double distanceKm;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: AppColors.primaryLight,
        foregroundColor: AppColors.primary,
        child: Icon(
          service.category == EmergencyServiceCategory.policeStation
              ? Icons.local_police_rounded
              : service.category == EmergencyServiceCategory.fireService
              ? Icons.fire_truck_rounded
              : Icons.emergency_rounded,
        ),
      ),
      title: Text(
        service.name,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${service.category.label} · ${service.address}'
        '${service.phone.isEmpty ? '' : '\n${service.phone}'}',
      ),
      isThreeLine: service.phone.isNotEmpty,
      trailing: Text('${distanceKm.toStringAsFixed(1)} km'),
    ),
  );
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.message,
    required this.onRetry,
  });

  final IconData icon;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 12),
    child: Column(
      children: [
        Icon(icon, size: 42, color: AppColors.textLight),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
        ),
      ],
    ),
  );
}

class _NearbyServiceFailure implements Exception {
  const _NearbyServiceFailure(this.message);

  final String message;
}
