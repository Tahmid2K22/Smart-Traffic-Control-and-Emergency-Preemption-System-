import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:velocity_x/velocity_x.dart';
import '../../constants/colors.dart';
import '../../services/admin_service.dart';
import 'drivers_management_page.dart';
import 'users_management_page.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _adminService = AdminService();

  String _adminName = 'Admin';
  Map<String, int> _stats = {
    'totalUsers': 0,
    'totalDrivers': 0,
    'pendingDrivers': 0,
    'totalAdmins': 0,
  };
  bool _statsLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOverviewTab(),
                  const DriversManagementPage(),
                  const UsersManagementPage(),
                ],
              ),
            ),
          ],
        ),
      ),
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

  // tab bar
  Widget _buildTabBar() {
    return Container(
      color: AppColors.white,
      child: TabBar(
        controller: _tabController,
        labelStyle: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textGrey,
        indicatorColor: AppColors.primary,
        indicatorWeight: 3,
        tabs: const [
          Tab(
            icon: Icon(Icons.dashboard_rounded, size: 20),
            text: 'Overview',
          ),
          Tab(
            icon: Icon(Icons.local_taxi_rounded, size: 20),
            text: 'Drivers',
          ),
          Tab(
            icon: Icon(Icons.people_rounded, size: 20),
            text: 'Users',
          ),
        ],
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
          _buildPendingSection(),
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
        title: 'Pending',
        value: _stats['pendingDrivers'] ?? 0,
        icon: Icons.pending_actions_rounded,
        color: AppColors.warning,
        bgColor: AppColors.warningLight,
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
              color: card.bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(card.icon, color: card.color, size: 20),
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

  // shows pending drivers at a glance
  Widget _buildPendingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Pending Verifications',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            TextButton(
              onPressed: () => _tabController.animateTo(1),
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
        StreamBuilder(
          stream: _adminService.pendingDriversStream(),
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
              separatorBuilder: (context, index) => 10.heightBox,
              itemBuilder: (context, index) {
                final data =
                    docs[index].data() as Map<String, dynamic>;
                return _PendingDriverTile(
                  uid: docs[index].id,
                  data: data,
                  adminService: _adminService,
                );
              },
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
        color: AppColors.successLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
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
                  'No pending driver verifications',
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

// compact tile shown in the overview pending list
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
        border: Border.all(color: AppColors.warningLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.warningLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.local_taxi_rounded,
              color: AppColors.warning,
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
                // approve
                _iconAction(
                  icon: Icons.check_circle_rounded,
                  color: AppColors.success,
                  onTap: () =>
                      _doAction(() => widget.adminService.verifyDriver(widget.uid)),
                ),
                6.widthBox,
                // reject
                _iconAction(
                  icon: Icons.cancel_rounded,
                  color: Colors.red,
                  onTap: () =>
                      _doAction(() => widget.adminService.rejectDriver(widget.uid)),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 22),
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
