import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velocity_x/velocity_x.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import '../../constants/colors.dart';
import '../../services/admin_service.dart';
import 'drivers_management_page.dart';
import 'users_management_page.dart';
import 'hospitals_management_page.dart';
import 'admin_activity_log_page.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage>
    with SingleTickerProviderStateMixin {
  int _selectedTab = 0;
  final _adminService = AdminService();

  String _adminName = 'Admin';
  Map<String, int> _stats = {
    'totalUsers': 0,
    'totalDrivers': 0,
    'pendingDrivers': 0,
    'totalAdmins': 0,
    'totalHospitals': 0,
    'pendingHospitals': 0,
  };
  bool _statsLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAdminName();
    _loadStats();
  }

  Future<void> _loadAdminName() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _adminName = prefs.getString('userName') ?? 'Admin';
      });
    }
  }

  Future<void> _loadStats() async {
    try {
      final stats = await _adminService.fetchStats();
      if (mounted) {
        setState(() {
          _stats = stats;
          _statsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            Expanded(
              child: IndexedStack(
                index: _selectedTab,
                children: [
                  _buildOverviewTab(),
                  const DriversManagementPage(),
                  const UsersManagementPage(),
                  const HospitalsManagementPage(),
                  const AdminActivityLogPage(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // top header with gradient + logout button
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // icon
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.admin_panel_settings_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              12.widthBox,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Admin Panel',
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Hello, $_adminName',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              // logout
              GestureDetector(
                onTap: _showLogoutDialog,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.logout_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // bottom nav bar — 5 tabs
  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: GNav(
            gap: 6,
            activeColor: AppColors.primary,
            iconSize: 20,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            duration: const Duration(milliseconds: 400),
            tabBackgroundColor: AppColors.primaryLight,
            color: AppColors.textLight,
            tabs: [
              GButton(
                icon: Icons.dashboard_rounded,
                text: 'Overview',
                textStyle: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              GButton(
                icon: Icons.local_taxi_rounded,
                text: 'Drivers',
                textStyle: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              GButton(
                icon: Icons.people_rounded,
                text: 'Users',
                textStyle: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              GButton(
                icon: Icons.local_hospital_rounded,
                text: 'Hospitals',
                textStyle: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              GButton(
                icon: Icons.history_rounded,
                text: 'Logs',
                textStyle: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
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

  // overview/home tab
  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // title + refresh button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Overview',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() => _statsLoading = true);
                  _loadStats();
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.refresh_rounded,
                    color: AppColors.primary,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
          20.heightBox,
          // stat cards
          if (_statsLoading)
            const Center(child: CircularProgressIndicator())
          else
            _buildStatsGrid(),
          28.heightBox,
          // pending drivers preview
          _buildPendingSection(
            title: 'Pending Driver Verifications',
            stream: _adminService.pendingDriversStream(),
            onSeeAll: () => setState(() => _selectedTab = 1),
            tileBuilder: (doc) => _PendingDriverTile(
              uid: doc.id,
              data: doc.data() as Map<String, dynamic>,
              adminService: _adminService,
            ),
          ),
          24.heightBox,
          // pending hospitals preview
          _buildPendingSection(
            title: 'Pending Hospital Approvals',
            stream: _adminService.pendingHospitalsStream(),
            onSeeAll: () => setState(() => _selectedTab = 3),
            tileBuilder: (doc) => _PendingHospitalTile(
              id: doc.id,
              data: doc.data() as Map<String, dynamic>,
              adminService: _adminService,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    final cards = [
      _StatCardData(
        title: 'Total Users',
        value: _stats['totalUsers'] ?? 0,
        icon: Icons.people_rounded,
        color: AppColors.infoBlue,
        bgColor: const Color(0xFFE3F2FD),
      ),
      _StatCardData(
        title: 'Total Drivers',
        value: _stats['totalDrivers'] ?? 0,
        icon: Icons.local_taxi_rounded,
        color: AppColors.success,
        bgColor: AppColors.successLight,
      ),
      _StatCardData(
        title: 'Pending Drivers',
        value: _stats['pendingDrivers'] ?? 0,
        icon: Icons.pending_actions_rounded,
        color: AppColors.warning,
        bgColor: AppColors.warningLight,
      ),
      _StatCardData(
        title: 'Hospitals',
        value: _stats['totalHospitals'] ?? 0,
        icon: Icons.local_hospital_rounded,
        color: AppColors.primary,
        bgColor: AppColors.primaryLight,
      ),
      _StatCardData(
        title: 'Pending Hospitals',
        value: _stats['pendingHospitals'] ?? 0,
        icon: Icons.hourglass_top_rounded,
        color: const Color(0xFF6A1B9A),
        bgColor: const Color(0xFFF3E5F5),
      ),
      _StatCardData(
        title: 'Admins',
        value: _stats['totalAdmins'] ?? 0,
        icon: Icons.admin_panel_settings_rounded,
        color: AppColors.accentOrange,
        bgColor: const Color(0xFFFFF3E0),
      ),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.4,
      children: cards.map((c) => _buildStatCard(c)).toList(),
    );
  }

  Widget _buildStatCard(_StatCardData card) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(card.icon, color: card.color, size: 24),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${card.value}',
                style: GoogleFonts.poppins(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                  height: 1,
                ),
              ),
              Text(
                card.title,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: AppColors.textGrey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Generic pending section builder
  Widget _buildPendingSection({
    required String title,
    required Stream<QuerySnapshot> stream,
    required VoidCallback onSeeAll,
    required Widget Function(QueryDocumentSnapshot doc) tileBuilder,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            TextButton(
              onPressed: onSeeAll,
              child: Text(
                'See All',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        8.heightBox,
        StreamBuilder<QuerySnapshot>(
          stream: stream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return _buildNoPending();
            }
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length > 3 ? 3 : docs.length,
              separatorBuilder: (_, _) => 10.heightBox,
              itemBuilder: (context, index) => tileBuilder(docs[index]),
            );
          },
        ),
      ],
    );
  }

  Widget _buildNoPending() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded,
              color: AppColors.success, size: 32),
          16.widthBox,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'All caught up!',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.success,
                  ),
                ),
                Text(
                  'No pending items',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // logout confirmation
  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Logout',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Are you sure you want to log out of the admin panel?',
          style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              await FirebaseAuth.instance.signOut();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Logout', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }
}

// ── Pending Driver Tile (overview) ─────────────────────────────────────────────

class _PendingDriverTile extends StatefulWidget {
  final String uid;
  final Map<String, dynamic> data;
  final AdminService adminService;

  const _PendingDriverTile({
    required this.uid,
    required this.data,
    required this.adminService,
  });

  @override
  State<_PendingDriverTile> createState() => _PendingDriverTileState();
}

class _PendingDriverTileState extends State<_PendingDriverTile> {
  bool _loading = false;

  Future<void> _doAction(Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String name = widget.data['name'] ?? 'Unknown';
    final String city = widget.data['city'] ?? '–';
    final String vehicleType = widget.data['vehicleType'] ?? '–';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.person_rounded,
              color: AppColors.textGrey,
              size: 20,
            ),
          ),
          12.widthBox,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
                Text(
                  '$vehicleType • $city',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ),
          if (_loading)
            const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Row(
              children: [
                _iconAction(
                  icon: Icons.check_circle_rounded,
                  color: AppColors.success,
                  onTap: () => _doAction(() => widget.adminService
                      .verifyDriver(widget.uid, name: name)),
                ),
                6.widthBox,
                _iconAction(
                  icon: Icons.cancel_rounded,
                  color: Colors.red,
                  onTap: () => _doAction(() => widget.adminService
                      .rejectDriver(widget.uid, name: name)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _iconAction({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

// ── Pending Hospital Tile (overview) ──────────────────────────────────────────

class _PendingHospitalTile extends StatefulWidget {
  final String id;
  final Map<String, dynamic> data;
  final AdminService adminService;

  const _PendingHospitalTile({
    required this.id,
    required this.data,
    required this.adminService,
  });

  @override
  State<_PendingHospitalTile> createState() => _PendingHospitalTileState();
}

class _PendingHospitalTileState extends State<_PendingHospitalTile> {
  bool _loading = false;

  Future<void> _doAction(Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String name = widget.data['name'] as String? ?? 'Unknown';
    final String city = widget.data['city'] as String? ?? '–';
    final int beds = (widget.data['beds'] as num?)?.toInt() ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.local_hospital_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          12.widthBox,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$city  •  $beds beds',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ),
          if (_loading)
            const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Row(
              children: [
                _iconAction(
                  icon: Icons.check_circle_rounded,
                  color: AppColors.success,
                  onTap: () => _doAction(() => widget.adminService
                      .approveHospital(widget.id, name: name)),
                ),
                6.widthBox,
                _iconAction(
                  icon: Icons.cancel_rounded,
                  color: Colors.red,
                  onTap: () => _doAction(() => widget.adminService
                      .rejectHospital(widget.id, name: name)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _iconAction({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

// simple data holder for each stat card
class _StatCardData {
  final String title;
  final int value;
  final IconData icon;
  final Color color;
  final Color bgColor;

  const _StatCardData({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.bgColor,
  });
}
