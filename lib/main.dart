import 'package:flutter/material.dart';
import 'package:velocity_x/velocity_x.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'package:badges/badges.dart' as badges;
import 'package:google_fonts/google_fonts.dart';

void main() => runApp(const AmbulanceApp());

// app entry point
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

// holds the bottom nav and switches between pages
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _selectedTab = 0;

  // shared colors used everywhere
  static const Color _primary = Color(0xFFD32F2F);
  static const Color _primaryDark = Color(0xFFB71C1C);
  static const Color _primaryLight = Color(0xFFFFEBEE);
  static const Color _white = Colors.white;
  static const Color _bg = Color(0xFFF8F9FA);
  static const Color _textDark = Color(0xFF1A1D1F);
  static const Color _textGrey = Color(0xFF6F767E);
  static const Color _textLight = Color(0xFF9A9FA5);
  static const Color _cardBorder = Color(0xFFEFEFEF);

  // one widget per tab
  late final List<Widget> _pages = [
    _HomeBody(
      primary: _primary,
      primaryDark: _primaryDark,
      primaryLight: _primaryLight,
      white: _white,
      bg: _bg,
      textDark: _textDark,
      textGrey: _textGrey,
      textLight: _textLight,
      cardBorder: _cardBorder,
    ),
    const ActivityPage(),
    const _PlaceholderPage(label: 'Payments'),
    const _PlaceholderPage(label: 'Account'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: _pages[_selectedTab],
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // bottom nav bar
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

// stub page until that tab is built
class _PlaceholderPage extends StatelessWidget {
  final String label;
  const _PlaceholderPage({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF1A1D1F),
        ),
      ),
    );
  }
}

// --- Activity Page ---

class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage>
    with SingleTickerProviderStateMixin {
  static const Color _primary = Color(0xFFD32F2F);
  static const Color _primaryLight = Color(0xFFFFEBEE);
  static const Color _white = Colors.white;
  static const Color _bg = Color(0xFFF8F9FA);
  static const Color _textDark = Color(0xFF1A1D1F);
  static const Color _textGrey = Color(0xFF6F767E);
  static const Color _textLight = Color(0xFF9A9FA5);
  static const Color _cardBorder = Color(0xFFEFEFEF);

  late TabController _tabController;
  int _selectedFilter = 0;

  final List<String> _filters = ['All', 'Active', 'Completed', 'Cancelled'];

  // sample booking history
  final List<_ActivityItem> _allItems = [
    _ActivityItem(
      id: 'AMB-2024-0045',
      destination: 'Khulna Medical College Hospital',
      address: 'Moylapota, Khulna',
      date: 'Today, 06:42 AM',
      status: ActivityStatus.active,
      ambulanceType: 'Advanced Life Support',
      driver: 'Md. Rafiqul Islam',
      vehicle: 'KHU-ALS-003',
      amount: 850,
      eta: '8 min',
      distance: '1.2 km',
    ),
    _ActivityItem(
      id: 'AMB-2024-0044',
      destination: 'Shaheed Sheikh Abu Naser Hospital',
      address: 'Sonadanga, Khulna',
      date: 'Today, 05:10 AM',
      status: ActivityStatus.completed,
      ambulanceType: 'Basic Life Support',
      driver: 'Md. Alamgir Hossain',
      vehicle: 'KHU-BLS-007',
      amount: 600,
      eta: null,
      distance: '2.8 km',
    ),
    _ActivityItem(
      id: 'AMB-2024-0043',
      destination: 'Gazi Medical College',
      address: 'Chuknagar, Khulna',
      date: 'Yesterday, 09:30 PM',
      status: ActivityStatus.completed,
      ambulanceType: 'Basic Life Support',
      driver: 'Md. Karim Mia',
      vehicle: 'KHU-BLS-002',
      amount: 750,
      eta: null,
      distance: '3.5 km',
    ),
    _ActivityItem(
      id: 'AMB-2024-0042',
      destination: 'Ad-Din Hospital',
      address: 'Nirala, Khulna',
      date: 'Yesterday, 02:15 PM',
      status: ActivityStatus.cancelled,
      ambulanceType: 'Advanced Life Support',
      driver: 'Md. Hasan Ali',
      vehicle: 'KHU-ALS-001',
      amount: 0,
      eta: null,
      distance: '4.1 km',
    ),
    _ActivityItem(
      id: 'AMB-2024-0041',
      destination: 'Rupsha Upazila Health Complex',
      address: 'Rupsha, Khulna',
      date: '18 Sep, 11:00 AM',
      status: ActivityStatus.completed,
      ambulanceType: 'Patient Transport',
      driver: 'Md. Jubayer Ahmed',
      vehicle: 'KHU-PT-005',
      amount: 500,
      eta: null,
      distance: '5.7 km',
    ),
    _ActivityItem(
      id: 'AMB-2024-0040',
      destination: 'Khulna Medical College Hospital',
      address: 'Moylapota, Khulna',
      date: '17 Sep, 03:45 PM',
      status: ActivityStatus.completed,
      ambulanceType: 'Neonatal Ambulance',
      driver: 'Md. Shafiqul Baree',
      vehicle: 'KHU-NEO-001',
      amount: 1200,
      eta: null,
      distance: '1.2 km',
    ),
    _ActivityItem(
      id: 'AMB-2024-0039',
      destination: 'Shaheed Sheikh Abu Naser Hospital',
      address: 'Sonadanga, Khulna',
      date: '15 Sep, 08:20 AM',
      status: ActivityStatus.cancelled,
      ambulanceType: 'Basic Life Support',
      driver: 'Md. Nazmul Haque',
      vehicle: 'KHU-BLS-010',
      amount: 0,
      eta: null,
      distance: '2.8 km',
    ),
  ];

  List<_ActivityItem> get _filteredItems {
    if (_selectedFilter == 0) return _allItems;
    final statusMap = {
      1: ActivityStatus.active,
      2: ActivityStatus.completed,
      3: ActivityStatus.cancelled,
    };
    return _allItems
        .where((e) => e.status == statusMap[_selectedFilter])
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _filters.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildFilterTabs(),
            Expanded(child: _buildActivityList()),
          ],
        ),
      ),
    );
  }

  // title, subtitle, search and filter buttons
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Activity',
                  style: GoogleFonts.poppins(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: _textDark,
                  ),
                ),
                Text(
                  'Your ambulance booking history',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: _textGrey,
                  ),
                ),
              ],
            ),
          ),
          // search button
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _cardBorder),
            ),
            child: const Icon(
              Icons.search_rounded,
              color: _textDark,
              size: 22,
            ),
          ),
          12.widthBox,
          // filter button
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _cardBorder),
            ),
            child: const Icon(
              Icons.tune_rounded,
              color: _textDark,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }


  // filter pills that narrow down the list
  Widget _buildFilterTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 0, 0),
      child: SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _filters.length,
          separatorBuilder: (_, _) => 10.widthBox,
          itemBuilder: (context, index) {
            final isSelected = _selectedFilter == index;
            return GestureDetector(
              onTap: () => setState(() => _selectedFilter = index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? _primary : _white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? _primary : _cardBorder,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: _primary.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : [],
                ),
                child: Text(
                  _filters[index],
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? _white : _textGrey,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // the main list, filtered by the selected tab
  Widget _buildActivityList() {
    final items = _filteredItems;

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.receipt_long_rounded,
                size: 40,
                color: _primary,
              ),
            ),
            20.heightBox,
            Text(
              'No activity found',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _textDark,
              ),
            ),
            8.heightBox,
            Text(
              'You have no bookings in this category',
              style: GoogleFonts.poppins(fontSize: 13, color: _textGrey),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      physics: const BouncingScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, _) => 14.heightBox,
      itemBuilder: (context, index) => _activityCard(items[index]),
    );
  }

  // builds one booking card
  Widget _activityCard(_ActivityItem item) {
    final statusConfig = _statusConfig(item.status);

    return Container(
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
        children: [
          // colored bar at the top shows the status
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: statusConfig.color,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // booking id, date, and status badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: statusConfig.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        statusConfig.icon,
                        color: statusConfig.color,
                        size: 20,
                      ),
                    ),
                    10.widthBox,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.id,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _textGrey,
                              letterSpacing: 0.5,
                            ),
                          ),
                          2.heightBox,
                          Text(
                            item.date,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: _textLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusConfig.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        statusConfig.label,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: statusConfig.color,
                        ),
                      ),
                    ),
                  ],
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, color: Color(0xFFEFEFEF)),
                ),

                // hospital name, address, and fare
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      color: _primary,
                      size: 18,
                    ),
                    8.widthBox,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.destination,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _textDark,
                            ),
                          ),
                          4.heightBox,
                          Text(
                            item.address,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: _textGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          item.amount > 0
                              ? 'BDT ${item.amount}'
                              : 'No charge',
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color:
                                item.amount > 0 ? _textDark : _textLight,
                          ),
                        ),
                        4.heightBox,
                        Text(
                          item.distance,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: _textGrey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                14.heightBox,

                // ambulance type, driver, and vehicle
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _cardBorder),
                  ),
                  child: Row(
                    children: [
                      _infoChip(
                        icon: Icons.local_hospital_rounded,
                        label: item.ambulanceType,
                        color: _primary,
                      ),
                      const Spacer(),
                      _infoChip(
                        icon: Icons.person_outline_rounded,
                        label: item.driver.split(' ').last,
                        color: const Color(0xFF1565C0),
                      ),
                      const Spacer(),
                      _infoChip(
                        icon: Icons.directions_car_rounded,
                        label: item.vehicle,
                        color: const Color(0xFF2E7D32),
                      ),
                    ],
                  ),
                ),

                // show arrival time only when booking is active
                if (item.status == ActivityStatus.active && item.eta != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _primaryLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.access_time_rounded,
                            color: _primary,
                            size: 16,
                          ),
                          8.widthBox,
                          Text(
                            'Ambulance arriving in ',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: _primary,
                            ),
                          ),
                          Text(
                            item.eta!,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _primary,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Track',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),


                // let them rebook if the trip is done
                if (item.status == ActivityStatus.completed)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: () {},
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _primaryLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.refresh_rounded,
                                color: _primary,
                                size: 14,
                              ),
                              6.widthBox,
                              Text(
                                'Rebook',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // show cancellation notice with a rebook option
                if (item.status == ActivityStatus.cancelled)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: Color(0xFFE65100),
                        ),
                        6.widthBox,
                        Text(
                          'Booking was cancelled',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: const Color(0xFFE65100),
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {},
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFEBEE),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Book Again',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // icon with a label beside it
  Widget _infoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        5.widthBox,
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: _textGrey,
          ),
        ),
      ],
    );
  }

  // maps each status to its color and icon
  _StatusConfig _statusConfig(ActivityStatus status) {
    switch (status) {
      case ActivityStatus.active:
        return _StatusConfig(
          color: _primary,
          icon: Icons.local_hospital_rounded,
          label: 'En Route',
        );
      case ActivityStatus.completed:
        return _StatusConfig(
          color: const Color(0xFF2E7D32),
          icon: Icons.check_circle_rounded,
          label: 'Completed',
        );
      case ActivityStatus.cancelled:
        return _StatusConfig(
          color: const Color(0xFFE65100),
          icon: Icons.cancel_rounded,
          label: 'Cancelled',
        );
    }
  }
}

// --- Home Page ---

class _HomeBody extends StatelessWidget {
  final Color primary;
  final Color primaryDark;
  final Color primaryLight;
  final Color white;
  final Color bg;
  final Color textDark;
  final Color textGrey;
  final Color textLight;
  final Color cardBorder;

  const _HomeBody({
    required this.primary,
    required this.primaryDark,
    required this.primaryLight,
    required this.white,
    required this.bg,
    required this.textDark,
    required this.textGrey,
    required this.textLight,
    required this.cardBorder,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
            _buildNearbyHospitals(),
            24.heightBox,
            _buildRecentSection(),
            20.heightBox,
          ],
        ),
      ),
    );
  }

  // greeting row with avatar and notifications
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          // user initials avatar
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [primary, primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: primary.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Center(
              child: Text(
                'TC',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          14.widthBox,
          // user greeting
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello, Tahmid!',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: textDark,
                  ),
                ),
                Text(
                  'How can we help you today?',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: textGrey,
                  ),
                ),
              ],
            ),
          ),
          // bell with unread count badge
          badges.Badge(
            position: badges.BadgePosition.topEnd(top: -2, end: -2),
            badgeStyle: badges.BadgeStyle(
              badgeColor: primary,
              padding: const EdgeInsets.all(5),
              elevation: 0,
            ),
            badgeContent: Text(
              '3',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cardBorder),
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                color: textDark,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // search field at the top
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cardBorder),
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
            Icon(Icons.search_rounded, color: textLight, size: 22),
            12.widthBox,
            Expanded(
              child: Text(
                'Search hospitals, pharmacies...',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: textLight,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            Container(width: 1, height: 22, color: cardBorder),
            12.widthBox,
            Icon(Icons.mic_none_rounded, color: primary, size: 22),
          ],
        ),
      ),
    );
  }

  // emergency call-to-action banner
  Widget _buildPromoBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: [primary, primaryDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: primary.withValues(alpha: 0.3),
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
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '24/7 AVAILABLE',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
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
                      color: Colors.white,
                      height: 1.3,
                    ),
                  ),
                  8.heightBox,
                  Text(
                    'Call 999 for immediate help',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            // icon on the right side of the banner
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Icon(
                  Icons.local_hospital_rounded,
                  color: Colors.white,
                  size: 44,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // quick-access service tiles
  Widget _buildServiceGrid() {
    final services = [
      _ServiceItem(
        icon: Icons.local_hospital_rounded,
        label: 'Ambulance',
        color: primary,
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
              color: textDark,
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
        color: white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cardBorder),
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
              color: textDark,
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


  // nearby hospitals list
  Widget _buildNearbyHospitals() {
    final hospitals = [
      _HospitalData(
        name: 'Khulna Medical College Hospital',
        address: 'Moylapota, Khulna',
        distance: '1.2 km',
        isOpen: true,
        beds: 12,
        specialties: ['Emergency', 'ICU', 'Surgery'],
      ),
      _HospitalData(
        name: 'Shaheed Sheikh Abu Naser Hospital',
        address: 'Sonadanga, Khulna',
        distance: '2.8 km',
        isOpen: true,
        beds: 8,
        specialties: ['Emergency', 'Cardiology'],
      ),
      _HospitalData(
        name: 'Gazi Medical College',
        address: 'Chuknagar, Khulna',
        distance: '3.5 km',
        isOpen: true,
        beds: 5,
        specialties: ['General', 'Orthopedics'],
      ),
      _HospitalData(
        name: 'Ad-Din Hospital',
        address: 'Nirala, Khulna',
        distance: '4.1 km',
        isOpen: false,
        beds: 0,
        specialties: ['Gynecology', 'Pediatrics'],
      ),
      _HospitalData(
        name: 'Rupsha Upazila Health Complex',
        address: 'Rupsha, Khulna',
        distance: '5.7 km',
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
                      color: textDark,
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_rounded,
                        size: 14,
                        color: primary,
                      ),
                      4.widthBox,
                      Text(
                        'Khulna Division',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: textGrey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: () {},
                icon: Icon(Icons.map_rounded, size: 16, color: primary),
                label: Text(
                  'View Map',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: primary,
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
          separatorBuilder: (_, _) => 12.heightBox,
          itemBuilder: (context, index) => _hospitalCard(hospitals[index]),
        ),
      ],
    );
  }

  Widget _hospitalCard(_HospitalData hospital) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder),
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
          // name, address, and open/closed badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.local_hospital_rounded,
                  color: primary,
                  size: 24,
                ),
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
                        color: textDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    4.heightBox,
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: textLight,
                        ),
                        4.widthBox,
                        Expanded(
                          child: Text(
                            '${hospital.address}  •  ${hospital.distance}',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: textGrey,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
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
          // bed count, specialties, and directions button
          Row(
            children: [
              if (hospital.isOpen) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: primaryLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bed_rounded, size: 14, color: primary),
                      4.widthBox,
                      Text(
                        '${hospital.beds} beds',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: primary,
                        ),
                      ),
                    ],
                  ),
                ),
                10.widthBox,
              ],
              Expanded(
                child: Text(
                  hospital.specialties.join(' • '),
                  style: GoogleFonts.poppins(fontSize: 10, color: textLight),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.directions_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // last few bookings shown as horizontal cards
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
                  color: textDark,
                ),
              ),
              TextButton(
                onPressed: () {},
                child: Text(
                  'See All',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: primary,
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
            separatorBuilder: (_, _) => 12.widthBox,
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
        ? primary
        : const Color(0xFFFF6F00);

    final Color statusBg = isCompleted
        ? const Color(0xFFE8F5E9)
        : isPending
        ? primaryLight
        : const Color(0xFFFFF3E0);

    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder),
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
                  color: primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.location_on_rounded,
                  color: primary,
                  size: 16,
                ),
              ),
              8.widthBox,
              Expanded(
                child: Text(
                  data.location,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textDark,
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
                style: GoogleFonts.poppins(fontSize: 11, color: textGrey),
              ),
              4.heightBox,
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 12,
                        color: textLight,
                      ),
                      4.widthBox,
                      Text(
                        data.time,
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: textLight,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
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
}

// --- Data Models ---

enum ActivityStatus { active, completed, cancelled }

class _StatusConfig {
  final Color color;
  final IconData icon;
  final String label;
  const _StatusConfig({
    required this.color,
    required this.icon,
    required this.label,
  });
}

class _ActivityItem {
  final String id;
  final String destination;
  final String address;
  final String date;
  final ActivityStatus status;
  final String ambulanceType;
  final String driver;
  final String vehicle;
  final int amount;
  final String? eta;
  final String distance;

  const _ActivityItem({
    required this.id,
    required this.destination,
    required this.address,
    required this.date,
    required this.status,
    required this.ambulanceType,
    required this.driver,
    required this.vehicle,
    required this.amount,
    required this.eta,
    required this.distance,
  });
}

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
  final bool isOpen;
  final int beds;
  final List<String> specialties;

  const _HospitalData({
    required this.name,
    required this.address,
    required this.distance,
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
