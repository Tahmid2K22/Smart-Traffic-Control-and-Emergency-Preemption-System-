import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../constants/colors.dart';
import '../../models/intersection_point.dart';
import '../../services/intersection_service.dart';
import '../../services/traffic_service.dart';

class IntersectionSearchPage extends StatefulWidget {
  const IntersectionSearchPage({super.key, this.dispatchId});

  final String? dispatchId;

  @override
  State<IntersectionSearchPage> createState() => _IntersectionSearchPageState();
}

class _IntersectionSearchPageState extends State<IntersectionSearchPage>
    with WidgetsBindingObserver {
  final _intersectionService = IntersectionService();
  final _trafficService = TrafficService();
  final _searchController = TextEditingController();
  late Stream<List<IntersectionPoint>> _intersections;
  StreamSubscription<Position>? _positionSub;
  Position? _position;
  String _query = '';
  String? _locationError;
  String? _sendingId;
  bool _locating = false;
  int _locationGeneration = 0;
  bool _locationServicesDisabled = false;
  bool _permissionDeniedForever = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _intersections = _intersectionService.watchIntersections();
    _startLocationUpdates();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startLocationUpdates();
    } else if (state == AppLifecycleState.paused) {
      _locationGeneration++;
      _positionSub?.cancel();
      _positionSub = null;
      // Do not enable requests using a position cached before leaving the app.
      setState(() {
        _position = null;
        _locating = false;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _startLocationUpdates() async {
    if (_locating || !mounted) return;
    final generation = ++_locationGeneration;
    setState(() {
      _locating = true;
      _position = null;
      _locationError = null;
      _locationServicesDisabled = false;
      _permissionDeniedForever = false;
    });
    try {
      final previousSubscription = _positionSub;
      _positionSub = null;
      await previousSubscription?.cancel();
      if (!mounted || generation != _locationGeneration) return;
      final servicesEnabled = await Geolocator.isLocationServiceEnabled();
      if (!mounted || generation != _locationGeneration) return;
      if (!servicesEnabled) {
        setState(() => _locationServicesDisabled = true);
        throw StateError(
          'Location services are off. Turn them on to see distances.',
        );
      }
      var permission = await Geolocator.checkPermission();
      if (!mounted || generation != _locationGeneration) return;
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (!mounted || generation != _locationGeneration) return;
      if (permission == LocationPermission.deniedForever) {
        setState(() => _permissionDeniedForever = true);
        throw StateError(
          'Location permission is blocked. Enable it in app settings.',
        );
      }
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        throw StateError(
          'Allow location access to see distances and request an emergency escape.',
        );
      }

      const settings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      );
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (!mounted || generation != _locationGeneration) return;
      setState(() => _position = position);
      _positionSub = Geolocator.getPositionStream(locationSettings: settings)
          .listen(
            (position) {
              if (!mounted || generation != _locationGeneration) return;
              setState(() {
                _position = position;
                _locationError = null;
              });
            },
            onError: (Object error) {
              if (generation == _locationGeneration) _locationFailed(error);
            },
            onDone: () {
              if (mounted && generation == _locationGeneration) {
                _locationFailed(
                  StateError(
                    'Live location stopped. Retry to update distances.',
                  ),
                );
              }
            },
            cancelOnError: true,
          );
    } catch (error) {
      if (generation == _locationGeneration) _locationFailed(error);
    } finally {
      if (mounted && generation == _locationGeneration) {
        setState(() => _locating = false);
      }
    }
  }

  void _locationFailed(Object error) {
    if (!mounted) return;
    setState(() {
      _position = null;
      _locationError = error is StateError ? error.message.toString() : 'Unable to get your location. Check GPS and permissions, then retry.';
    });
  }

  Future<void> _openSettings() async {
    try {
      final opened = _locationServicesDisabled
          ? await Geolocator.openLocationSettings()
          : await Geolocator.openAppSettings();
      if (!opened && mounted) {
        _showFeedback(
          'Could not open settings. Please enable location in your device settings.',
        );
      }
    } catch (_) {
      if (mounted) _showFeedback('Could not open device settings.');
    }
  }

  Future<void> _requestEscape(IntersectionPoint intersection) async {
    final position = _position;
    if (_sendingId != null || position == null || !intersection.isActive) {
      return;
    }
    if (intersection.distanceFrom(position.latitude, position.longitude) >
        500) {
      _showFeedback(
        'Move within 500 m of this intersection to request an emergency escape.',
      );
      return;
    }
    setState(() => _sendingId = intersection.id);
    try {
      // The service obtains fresh GPS and revalidates driver, range and officers.
      final count = await _trafficService.requestEmergencyEscape(
        intersectionId: intersection.id,
        dispatchId: widget.dispatchId,
      );
      if (!mounted) return;
      _showFeedback(
        'Emergency escape requested at ${intersection.name}. '
        '$count ${count == 1 ? 'officer' : 'officers'} notified.',
      );
    } catch (error) {
      if (!mounted) return;
      _showFeedback(
        error is StateError ? error.message.toString() : 'Could not send the emergency request. Check your connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _sendingId = null);
    }
  }

  void _showFeedback(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Intersections',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: TextField(
                controller: _searchController,
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Search name, city or Plus Code',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.clear_rounded),
                        ),
                  filled: true,
                  fillColor: AppColors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            _buildLocationStatus(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Browse anytime. Emergency escape requests require you to be within '
                '500 m. Your location and eligibility are checked again when sending.',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: AppColors.textGrey,
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<IntersectionPoint>>(
                stream: _intersections,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _buildMessage(
                      Icons.error_outline_rounded,
                      'Could not load intersections. Check your connection and retry.',
                      onRetry: () => setState(() {
                        _intersections = _intersectionService
                            .watchIntersections();
                      }),
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    );
                  }
                  final active = (snapshot.data ?? [])
                      .where((intersection) => intersection.isActive)
                      .toList();
                  final filtered = active.where((intersection) {
                    return _query.isEmpty ||
                        intersection.name.toLowerCase().contains(_query) ||
                        intersection.city.toLowerCase().contains(_query) ||
                        intersection.plusCode.toLowerCase().contains(_query);
                  }).toList();
                  final position = _position;
                  filtered.sort(
                    (a, b) => position == null
                        ? a.name.compareTo(b.name)
                        : a
                              .distanceFrom(
                                position.latitude,
                                position.longitude,
                              )
                              .compareTo(
                                b.distanceFrom(
                                  position.latitude,
                                  position.longitude,
                                ),
                              ),
                  );
                  if (filtered.isEmpty) {
                    return _buildMessage(
                      Icons.traffic_rounded,
                      active.isEmpty
                          ? 'No active intersections are available yet.'
                          : 'No intersections match your search.',
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    itemCount: filtered.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 12),
                    itemBuilder: (_, index) =>
                        _buildIntersection(filtered[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationStatus() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          if (_locating)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              _position == null
                  ? Icons.location_off_rounded
                  : Icons.my_location_rounded,
              color: _position == null ? AppColors.warning : AppColors.success,
              size: 20,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _locating
                  ? 'Getting your location…'
                  : _locationError ?? 'Live distances enabled · nearest first',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: AppColors.textGrey,
              ),
            ),
          ),
          if (!_locating && _position == null) ...[
            if (_locationServicesDisabled || _permissionDeniedForever)
              TextButton(
                onPressed: _openSettings,
                child: const Text('Settings'),
              ),
            TextButton(
              onPressed: _startLocationUpdates,
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIntersection(IntersectionPoint intersection) {
    final position = _position;
    final distance = position == null
        ? null
        : intersection.distanceFrom(position.latitude, position.longitude);
    final inRange = distance != null && distance <= 500;
    final sending = _sendingId == intersection.id;
    final distanceLabel = distance == null
        ? 'Distance unavailable'
        : distance < 1000
        ? '${distance.round()} m away'
        : '${(distance / 1000).toStringAsFixed(1)} km away';
    final plusCode = intersection.plusCode;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            intersection.name,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
          Text(
            intersection.city,
            style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textGrey),
          ),
          Text(
            '${intersection.wayCount}-way / '
            '${intersection.trafficLightCount} traffic lights',
            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textGrey),
          ),
          if (plusCode.isNotEmpty)
            Text(
              'Plus Code: $plusCode',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: AppColors.textGrey,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            distanceLabel,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: inRange ? AppColors.success : AppColors.textGrey,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: inRange && _sendingId == null
                  ? () => _requestEscape(intersection)
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.emergency_rounded),
              label: Text(sending ? 'Sending…' : 'Request emergency escape'),
            ),
          ),
          if (!inRange)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                distance == null
                    ? 'Enable live location to request.'
                    : 'Move within 500 m to request.',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: AppColors.textGrey,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessage(IconData icon, String message, {VoidCallback? onRetry}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppColors.textGrey),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: AppColors.textGrey),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
