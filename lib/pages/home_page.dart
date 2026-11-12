import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/colors.dart';
import '../models/models.dart';
import 'ambulance_booking_screen.dart';
import 'nearby_places_page.dart';
import 'notifications_page.dart';
import 'profile_page.dart';
import 'hospital_register_page.dart';
import '../services/hospital_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  String _name = 'User';
  String _initials = 'U';
  int _unreadNotifications = 0;
  String _query = '';
  bool _loadingProfile = true;
  final _hospitalService = HospitalService();
  StreamSubscription<QuerySnapshot>? _hospitalSubscription;
  List<_SearchItem> _searchItems = [];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _hospitalSubscription = _hospitalService.approvedHospitalsStream().listen((
      snapshot,
    ) {
      if (!mounted) return;
      setState(() {
        _searchItems = snapshot.docs
            .map(HospitalModel.fromDoc)
            .where((hospital) => hospital.name.trim().isNotEmpty)
            .map(
              (hospital) => _SearchItem(
                hospital.name,
                'Hospital',
                Icons.local_hospital_rounded,
              ),
            )
            .toList();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _hospitalSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
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

  void _openPlaces(NearbyPlaceType type) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => NearbyPlacesPage(type: type)));

  List<_SearchItem> get _filteredResults {
    final value = _query.trim().toLowerCase();
    if (value.isEmpty) return const [];
    return _searchItems
        .where(
          (item) =>
              '${item.name} ${item.category}'.toLowerCase().contains(value),
        )
        .toList();
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
            const SizedBox(height: 16),
            _buildSearchBar(),
            if (_filteredResults.isNotEmpty) _buildSearchResults(),
            const SizedBox(height: 20),
            _buildEmergencyBanner(),
            const SizedBox(height: 24),
            _buildServiceGrid(context),
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
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ProfilePage()),
            ),
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
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const NotificationsPage(),
                ),
              ),
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
      onChanged: (value) => setState(() => _query = value),
      decoration: InputDecoration(
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppColors.textLight,
        ),
        suffixIcon: IconButton(
          tooltip: 'Voice search',
          onPressed: () {
            _searchFocus.requestFocus();
            _showMessage(
              'Voice search is ready. Type a hospital or pharmacy name.',
            );
          },
          icon: const Icon(Icons.mic_none_rounded, color: AppColors.primary),
        ),
        hintText: 'Search hospitals, pharmacies...',
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          children: _filteredResults.map((item) {
            return ListTile(
              dense: true,
              leading: Icon(item.icon, color: AppColors.primary),
              title: Text(item.name),
              subtitle: Text(item.category),
              onTap: () {
                _searchController.text = item.name;
                setState(() => _query = '');
              },
            );
          }).toList(),
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
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Image.asset(
                  'assets/e ambulance logo.png',
                  fit: BoxFit.contain,
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
        ? () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AmbulanceBookingScreen(),
            ),
          )
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

class _SearchItem {
  const _SearchItem(this.name, this.category, this.icon);
  final String name;
  final String category;
  final IconData icon;
}
