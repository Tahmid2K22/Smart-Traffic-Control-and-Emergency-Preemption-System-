import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/colors.dart';
import '../models/models.dart';

import '../services/map_search_service.dart';
import 'ambulance_booking_screen.dart';
import 'nearby_places_page.dart';
import 'notifications_page.dart';
import 'profile_page.dart';
import 'hospital_register_page.dart';
import 'login_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.isGuest = false});

  final bool isGuest;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  final _mapSearchService = MapSearchService();
  Geocoding? _geocoder;

  String _name = 'User';
  String _initials = 'U';
  String _region = 'Your area';
  int _unreadNotifications = 0;
  String _query = '';
  bool _loadingProfile = true;
  bool _isSearching = false;
  Timer? _searchDebounce;
  List<MapSearchSuggestion> _searchSuggestions = [];

  @override
  void initState() {
    super.initState();

    _loadDashboardData();
    _loadRegion();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _mapSearchService.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    if (widget.isGuest) {
      _name = 'Guest';
      _initials = 'G';
      _loadingProfile = false;
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    var name = user.displayName?.trim() ?? '';
    try {
      final profile = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = profile.data();
      final profileName = data?['name']?.toString().trim() ?? '';
      if (profileName.isNotEmpty) name = profileName;
      final unread = await FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: user.uid)
          .where('read', isEqualTo: false)
          .get();
      if (mounted) _unreadNotifications = unread.size;
    } on FirebaseException {
      // Auth data remains a reliable fallback when optional Firestore data is unavailable.
    }
    if (!mounted) return;
    final safeName = name.isEmpty ? 'User' : name;
    setState(() {
      _name = _firstName(safeName);
      _initials = _makeInitials(safeName);
      _loadingProfile = false;
    });
  }

  Future<void> _loadRegion() async {
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
          accuracy: LocationAccuracy.low,
          distanceFilter: 250,
        ),
      );

      _geocoder ??= Geocoding();
      final marks = await _geocoder!.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (!mounted || marks.isEmpty) return;
      final mark = marks.first;
      final area = mark.administrativeArea?.trim().isNotEmpty == true
          ? mark.administrativeArea!
          : mark.locality;
      if (area != null && area.trim().isNotEmpty) {
        setState(() => _region = area);
      }
    } catch (e) {
      // Catch all errors to prevent red screen when geocoding is unavailable
    }
  }

  String _firstName(String name) => name.split(RegExp(r'\s+')).first;

  String _makeInitials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  Future<void> _callEmergency() async {
    final uri = Uri(scheme: 'tel', path: '999');
    if (!await launchUrl(uri)) _showMessage('Unable to open the phone dialer.');
  }

  void _showMessage(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );

  void _openProtected(WidgetBuilder builder) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: widget.isGuest ? (_) => const LoginPage() : builder,
      ),
    );
  }

  void _openPlaces(NearbyPlaceType type) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => NearbyPlacesPage(type: type)));

  void _onSearchQueryChanged(String query) {
    setState(() => _query = query);
    _searchDebounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      setState(() {
        _searchSuggestions = [];
        _isSearching = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() => _isSearching = true);
      try {
        final suggestions = await _mapSearchService.search(trimmed);
        if (mounted && _query.trim() == trimmed) {
          setState(() {
            _searchSuggestions = suggestions;
            _isSearching = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  List<_RealSearchResult> get _combinedSearchResults {
    final trimmed = _query.trim().toLowerCase();
    if (trimmed.isEmpty) return const [];

    final results = <_RealSearchResult>[];

    for (final s in _searchSuggestions) {
      results.add(
        _RealSearchResult(
          title: s.displayName.split(',').first.trim(),
          subtitle: s.displayName,
          icon: Icons.place_rounded,
          suggestion: s,
        ),
      );
    }

    return results;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            if (widget.isGuest)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Browse freely. Log in to access services and book.',
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          _openProtected((_) => const ProfilePage()),
                      child: const Text('Log in'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            _buildSearchBar(),
            if (_query.trim().isNotEmpty) _buildSearchResults(),
            const SizedBox(height: 20),
            _buildEmergencyBanner(),
            const SizedBox(height: 24),
            _buildServiceGrid(context),
            const SizedBox(height: 24),
            _buildNearbyHospitals(context),
            const SizedBox(height: 16),
            _buildHospitalRequestSection(context),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          InkWell(
            onTap: () => _openProtected((_) => const ProfilePage()),
            borderRadius: BorderRadius.circular(24),
            child: _Avatar(initials: _initials),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _loadingProfile ? 'Hello, User!' : 'Hello, $_name!',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                Text(
                  'How can we help you today?',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ),
          _Badge(
            count: _unreadNotifications,
            child: IconButton(
              tooltip: 'Notifications',
              onPressed: () => _openProtected((_) => const NotificationsPage()),
              icon: const Icon(
                Icons.notifications_none_rounded,
                color: AppColors.textDark,
                size: 25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: TextField(
      controller: _searchController,
      focusNode: _searchFocus,
      onChanged: _onSearchQueryChanged,
      decoration: InputDecoration(
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppColors.textLight,
        ),
        suffixIcon: _query.isNotEmpty
            ? IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.clear_rounded, size: 20),
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _query = '';
                    _searchSuggestions = [];
                  });
                },
              )
            : IconButton(
                tooltip: 'Voice search',
                onPressed: () {
                  _searchFocus.requestFocus();
                  _showMessage(
                    'Voice search is ready. Type a hospital or pharmacy name.',
                  );
                },
                icon: const Icon(
                  Icons.mic_none_rounded,
                  color: AppColors.primary,
                ),
              ),
        hintText: 'Search hospitals, places...',
        filled: true,
        fillColor: AppColors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 15),
      ),
    ),
  );

  Widget _buildSearchResults() {
    final results = _combinedSearchResults;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          children: [
            if (_isSearching)
              const LinearProgressIndicator(
                minHeight: 2,
                color: AppColors.primary,
              ),
            if (results.isEmpty && !_isSearching)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No matching places found for "$_query"',
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 13,
                  ),
                ),
              )
            else
              ...results.map((item) {
                return ListTile(
                  dense: true,
                  leading: Icon(item.icon, color: AppColors.primary),
                  title: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () {
                    _searchController.text = item.title;
                    setState(() => _query = '');
                    _openProtected((_) => const AmbulanceBookingScreen());
                  },
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: InkWell(
        onTap: _callEmergency,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryDark],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: .3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '24/7 AVAILABLE',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Emergency\nResponse Ready',
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Call 999 for immediate help',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: .85),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.add_rounded,
                  size: 48,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServiceGrid(BuildContext context) {
    final services = [
      ServiceItem(
        icon: Icons.local_hospital_rounded,
        label: 'Ambulance',
        color: AppColors.primary,
        subtitle: 'Book Now',
      ),
      ServiceItem(
        icon: Icons.medication_rounded,
        label: 'Pharmacy',
        color: const Color(0xFFFF6F00),
        subtitle: 'Nearby',
      ),
      ServiceItem(
        icon: Icons.business_rounded,
        label: 'Hospitals',
        color: const Color(0xFF1565C0),
        subtitle: 'Find Nearby',
      ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Services',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: services
                .map(
                  (service) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: service == services.last ? 0 : 12,
                      ),
                      child: _serviceCard(context, service),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _serviceCard(BuildContext context, ServiceItem service) {
    final callback = service.label == 'Ambulance'
        ? () => _openProtected((_) => const AmbulanceBookingScreen())
        : service.label == 'Pharmacy'
        ? () => _openPlaces(NearbyPlaceType.pharmacies)
        : () => _openPlaces(NearbyPlaceType.hospitals);
    return InkWell(
      onTap: callback,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: service.color.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(service.icon, color: service.color, size: 30),
            ),
            const SizedBox(height: 12),
            Text(
              service.label,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              service.subtitle,
              style: GoogleFonts.poppins(fontSize: 11, color: service.color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNearbyHospitals(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nearby Hospitals',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      size: 14,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _region,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            TextButton.icon(
              onPressed: () => _openPlaces(NearbyPlaceType.hospitals),
              icon: const Icon(
                Icons.map_rounded,
                size: 16,
                color: AppColors.primary,
              ),
              label: Text(
                'View Map',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.local_hospital_outlined,
                size: 38,
                color: AppColors.primary,
              ),
              const SizedBox(height: 10),
              Text(
                'Find hospitals near you',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Use your current GPS location to scan for hospitals within 15 km and view live search results.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: AppColors.textGrey,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => _openPlaces(NearbyPlaceType.hospitals),
                icon: const Icon(Icons.explore_rounded, size: 16),
                label: const Text('Scan hospitals within 15 km'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _buildHospitalRequestSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const HospitalRegisterPage(),
            ),
          ),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.domain_add_rounded,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Request for registering a hospital',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Submit hospital details for admin approval',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: AppColors.textGrey,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials});
  final String initials;
  @override
  Widget build(BuildContext context) => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const LinearGradient(
        colors: [AppColors.primary, AppColors.primaryDark],
      ),
      boxShadow: [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: .3),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Center(
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count, required this.child});
  final int count;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (count > 0)
          Positioned(
            right: 4,
            top: 2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RealSearchResult {
  const _RealSearchResult({
    required this.title,
    required this.subtitle,
    required this.icon,

    this.suggestion,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  final MapSearchSuggestion? suggestion;
}
