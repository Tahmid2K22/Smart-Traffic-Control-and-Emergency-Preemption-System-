import 'package:flutter/material.dart';
import 'package:velocity_x/velocity_x.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'package:badges/badges.dart' as badges;
import 'package:google_fonts/google_fonts.dart';

void main() => runApp(const AmbulanceApp());

// ─────────────────────────────────────────────
//  APP ROOT
// ─────────────────────────────────────────────
class AmbulanceApp extends StatelessWidget {
  const AmbulanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ambulance Service',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        textTheme: GoogleFonts.poppinsTextTheme(),
        colorSchemeSeed: const Color(0xFFD32F2F),
        useMaterial3: true,
      ),
      home: const DashboardPage(),
    );
  }
}

// ─────────────────────────────────────────────
//  DASHBOARD PAGE
// ─────────────────────────────────────────────
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _selectedTab = 0;

  // ── Red & White colour palette ──
  static const Color _primary = Color(0xFFD32F2F);
  static const Color _primaryDark = Color(0xFFB71C1C);
  static const Color _primaryLight = Color(0xFFFFEBEE);
  static const Color _white = Colors.white;
  static const Color _bg = Color(0xFFF8F9FA);
  static const Color _textDark = Color(0xFF1A1D1F);
  static const Color _textGrey = Color(0xFF6F767E);
  static const Color _textLight = Color(0xFF9A9FA5);
  static const Color _cardBorder = Color(0xFFEFEFEF);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              16.heightBox,
              _buildSearchBar(),
              20.heightBox,
              _buildPromoBanner(),
              24.heightBox,
              _buildServiceGrid(),
              24.heightBox,
              _buildActiveDispatchCard(),
              24.heightBox,
              _buildNearbyHospitals(),
              24.heightBox,
              _buildRecentSection(),
              20.heightBox,
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ═══════════════════════════════════════════
  //  1. HEADER — Greeting + Notification Bell
  // ═══════════════════════════════════════════
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          // Profile avatar
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [_primary, _primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: _primary.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Center(
              child: Text(
                'TC',
                style: TextStyle(
                  color: _white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          14.widthBox,
          // Greeting
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello, Tahmid!',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: _textDark,
                  ),
                ),
                Text(
                  'How can we help you today?',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: _textGrey,
                  ),
                ),
              ],
            ),
          ),
          // Notification bell
          badges.Badge(
            position: badges.BadgePosition.topEnd(top: -2, end: -2),
            badgeStyle: const badges.BadgeStyle(
              badgeColor: _primary,
              padding: EdgeInsets.all(5),
              elevation: 0,
            ),
            badgeContent: Text(
              '3',
              style: GoogleFonts.poppins(
                color: _white,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _cardBorder),
              ),
              child: const Icon(
                Icons.notifications_none_rounded,
                color: _textDark,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  2. SEARCH BAR
  // ═══════════════════════════════════════════
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, color: _textLight, size: 22),
            12.widthBox,
            Expanded(
              child: Text(
                'Search hospitals, pharmacies...',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: _textLight,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            Container(
              width: 1,
              height: 22,
              color: _cardBorder,
            ),
            12.widthBox,
            const Icon(Icons.mic_none_rounded, color: _primary, size: 22),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  3. PROMOTIONAL BANNER
  // ═══════════════════════════════════════════
  Widget _buildPromoBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            colors: [Color(0xFFD32F2F), Color(0xFFB71C1C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: _primary.withValues(alpha: 0.3),
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '24/7 AVAILABLE',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _white,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  12.heightBox,
                  Text(
                    'Emergency\nResponse Ready',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _white,
                      height: 1.3,
                    ),
                  ),
                  8.heightBox,
                  Text(
                    'Call 999 for immediate help',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: _white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Center(
                child: Text('🚑', style: TextStyle(fontSize: 40)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  4. SERVICE GRID — 3 services only
  // ═══════════════════════════════════════════
  Widget _buildServiceGrid() {
    final services = [
      _ServiceItem(
        icon: Icons.local_hospital_rounded,
        label: 'Ambulance',
        color: _primary,
        subtitle: 'Book Now',
      ),
      _ServiceItem(
        icon: Icons.medication_rounded,
        label: 'Pharmacy',
        color: const Color(0xFFFF6F00),
        subtitle: 'Order Medicine',
      ),
      _ServiceItem(
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
              color: _textDark,
            ),
          ),
          16.heightBox,
          Row(
            children: services.map((svc) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: svc != services.last ? 12 : 0,
                  ),
                  child: _serviceCard(svc),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _serviceCard(_ServiceItem svc) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: svc.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(svc.icon, color: svc.color, size: 30),
          ),
          12.heightBox,
          Text(
            svc.label,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _textDark,
            ),
            textAlign: TextAlign.center,
          ),
          4.heightBox,
          Text(
            svc.subtitle,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: svc.color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  5. ACTIVE DISPATCH / TRACKING CARD
  // ═══════════════════════════════════════════
  Widget _buildActiveDispatchCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _primaryLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.local_hospital_rounded,
                      color: _primary, size: 18),
                ),
                10.widthBox,
                Text(
                  'Active Dispatch',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _textDark,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _primaryLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'En Route',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _primary,
                    ),
                  ),
                ),
              ],
            ),
            16.heightBox,
            // Progress bar
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: _primary,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE0E0E0),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: 0.6,
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: _primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: 0.6,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: _primary,
                                shape: BoxShape.circle,
                              ),
                              child: const Text(
                                '🚑',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.location_on_rounded,
                    color: _primary, size: 20),
              ],
            ),
            14.heightBox,
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Khulna Medical College',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _textGrey,
                  ),
                ),
                Text(
                  'ETA: 8 min',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  6. NEARBY HOSPITALS
  // ═══════════════════════════════════════════
  Widget _buildNearbyHospitals() {
    final hospitals = [
      _HospitalData(
        name: 'Khulna Medical College Hospital',
        address: 'Moylapota, Khulna',
        distance: '1.2 km',
        rating: 4.5,
        isOpen: true,
        beds: 12,
        specialties: ['Emergency', 'ICU', 'Surgery'],
      ),
      _HospitalData(
        name: 'Shaheed Sheikh Abu Naser Hospital',
        address: 'Sonadanga, Khulna',
        distance: '2.8 km',
        rating: 4.3,
        isOpen: true,
        beds: 8,
        specialties: ['Emergency', 'Cardiology'],
      ),
      _HospitalData(
        name: 'Gazi Medical College',
        address: 'Chuknagar, Khulna',
        distance: '3.5 km',
        rating: 4.1,
        isOpen: true,
        beds: 5,
        specialties: ['General', 'Orthopedics'],
      ),
      _HospitalData(
        name: 'Ad-Din Hospital',
        address: 'Nirala, Khulna',
        distance: '4.1 km',
        rating: 4.6,
        isOpen: false,
        beds: 0,
        specialties: ['Gynecology', 'Pediatrics'],
      ),
      _HospitalData(
        name: 'Rupsha Upazila Health Complex',
        address: 'Rupsha, Khulna',
        distance: '5.7 km',
        rating: 3.9,
        isOpen: true,
        beds: 3,
        specialties: ['General', 'Emergency'],
      ),
    ];

    return Column(
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
                      color: _textDark,
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded,
                          size: 14, color: _primary),
                      4.widthBox,
                      Text(
                        'Khulna Division',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: _textGrey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.map_rounded, size: 16, color: _primary),
                label: Text(
                  'View Map',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        12.heightBox,
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: hospitals.length,
          separatorBuilder: (_, __) => 12.heightBox,
          itemBuilder: (context, index) =>
              _hospitalCard(hospitals[index]),
        ),
      ],
    );
  }

  Widget _hospitalCard(_HospitalData hospital) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: icon, name, open/closed badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.local_hospital_rounded,
                    color: _primary, size: 24),
              ),
              12.widthBox,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hospital.name,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _textDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    4.heightBox,
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 14, color: _textLight),
                        4.widthBox,
                        Expanded(
                          child: Text(
                            '${hospital.address}  •  ${hospital.distance}',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: _textGrey,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              8.widthBox,
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: hospital.isOpen
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  hospital.isOpen ? 'Open' : 'Closed',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: hospital.isOpen
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFFE65100),
                  ),
                ),
              ),
            ],
          ),
          14.heightBox,
          // Bottom row: rating, beds, specialties, directions
          Row(
            children: [
              // Rating
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded,
                        size: 14, color: Color(0xFFFFA000)),
                    4.widthBox,
                    Text(
                      hospital.rating.toString(),
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFF57F17),
                      ),
                    ),
                  ],
                ),
              ),
              10.widthBox,
              // Beds available
              if (hospital.isOpen) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _primaryLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bed_rounded,
                          size: 14, color: _primary),
                      4.widthBox,
                      Text(
                        '${hospital.beds} beds',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _primary,
                        ),
                      ),
                    ],
                  ),
                ),
                10.widthBox,
              ],
              // Specialties
              Expanded(
                child: Text(
                  hospital.specialties.join(' • '),
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    color: _textLight,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Directions button
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.directions_rounded,
                    color: _white, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  7. RECENT REQUESTS — Horizontal scroll
  // ═══════════════════════════════════════════
  Widget _buildRecentSection() {
    final requests = [
      _RequestData(
        location: 'Khulna Medical College',
        address: 'Moylapota, Khulna',
        time: '2 min ago',
        status: 'Pending',
      ),
      _RequestData(
        location: 'Sheikh Abu Naser Hospital',
        address: 'Sonadanga, Khulna',
        time: '8 min ago',
        status: 'Assigned',
      ),
      _RequestData(
        location: 'Rupsha Health Complex',
        address: 'Rupsha, Khulna',
        time: '15 min ago',
        status: 'Completed',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Requests',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _textDark,
                ),
              ),
              TextButton(
                onPressed: () {},
                child: Text(
                  'See All',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        8.heightBox,
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: requests.length,
            separatorBuilder: (_, __) => 12.widthBox,
            itemBuilder: (context, index) =>
                _recentRequestCard(requests[index]),
          ),
        ),
      ],
    );
  }

  Widget _recentRequestCard(_RequestData data) {
    final bool isPending = data.status == 'Pending';
    final bool isCompleted = data.status == 'Completed';

    final Color statusColor = isCompleted
        ? const Color(0xFF2E7D32)
        : isPending
            ? _primary
            : const Color(0xFFFF6F00);

    final Color statusBg = isCompleted
        ? const Color(0xFFE8F5E9)
        : isPending
            ? _primaryLight
            : const Color(0xFFFFF3E0);

    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.location_on_rounded,
                    color: _primary, size: 16),
              ),
              8.widthBox,
              Expanded(
                child: Text(
                  data.location,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.address,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: _textGrey,
                ),
              ),
              4.heightBox,
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.access_time_rounded,
                          size: 12, color: _textLight),
                      4.widthBox,
                      Text(
                        data.time,
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: _textLight,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      data.status,
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  8. BOTTOM NAVIGATION (4-tab)
  // ═══════════════════════════════════════════
  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: _white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: GNav(
            gap: 8,
            activeColor: _primary,
            iconSize: 22,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            duration: const Duration(milliseconds: 400),
            tabBackgroundColor: _primaryLight,
            color: _textLight,
            tabs: [
              GButton(
                icon: Icons.home_rounded,
                text: 'Home',
                textStyle: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _primary,
                ),
              ),
              GButton(
                icon: Icons.receipt_long_rounded,
                text: 'Activity',
                textStyle: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _primary,
                ),
              ),
              GButton(
                icon: Icons.account_balance_wallet_rounded,
                text: 'Payments',
                textStyle: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _primary,
                ),
              ),
              GButton(
                icon: Icons.person_rounded,
                text: 'Account',
                textStyle: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _primary,
                ),
              ),
            ],
            selectedIndex: _selectedTab,
            onTabChange: (index) => setState(() => _selectedTab = index),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  DATA MODELS (UI-only)
// ─────────────────────────────────────────────
class _ServiceItem {
  final IconData icon;
  final String label;
  final Color color;
  final String subtitle;

  const _ServiceItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.subtitle,
  });
}

class _HospitalData {
  final String name;
  final String address;
  final String distance;
  final double rating;
  final bool isOpen;
  final int beds;
  final List<String> specialties;

  const _HospitalData({
    required this.name,
    required this.address,
    required this.distance,
    required this.rating,
    required this.isOpen,
    required this.beds,
    required this.specialties,
  });
}

class _RequestData {
  final String location;
  final String address;
  final String time;
  final String status;

  const _RequestData({
    required this.location,
    required this.address,
    required this.time,
    required this.status,
  });
}
