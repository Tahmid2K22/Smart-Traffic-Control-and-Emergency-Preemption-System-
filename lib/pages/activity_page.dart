import 'package:flutter/material.dart';
import 'package:velocity_x/velocity_x.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/colors.dart';
import '../models/models.dart';

class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedFilter = 0;

  final List<String> _filters = ['All', 'Active', 'Completed', 'Cancelled'];

  // dummy data
  final List<ActivityItem> _allItems = [
    const ActivityItem(
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
    const ActivityItem(
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
    const ActivityItem(
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
    const ActivityItem(
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
    const ActivityItem(
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
    const ActivityItem(
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
    const ActivityItem(
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

  List<ActivityItem> get _filteredItems {
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
      backgroundColor: AppColors.background,
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

  // header
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
                    color: AppColors.textDark,
                  ),
                ),
                Text(
                  'Your ambulance booking history',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ),
          // search button
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: const Icon(
              Icons.search_rounded,
              color: AppColors.textDark,
              size: 22,
            ),
          ),
          12.widthBox,
          // filter button
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: const Icon(
              Icons.tune_rounded,
              color: AppColors.textDark,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  // filter tabs
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
                  color: isSelected ? AppColors.primary : AppColors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.cardBorder,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.25),
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
                    color: isSelected ? AppColors.white : AppColors.textGrey,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // activity list
  Widget _buildActivityList() {
    final items = _filteredItems;

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.receipt_long_rounded,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            20.heightBox,
            Text(
              'No activity found',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
            8.heightBox,
            Text(
              'You have no bookings in this category',
              style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textGrey),
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

  // card builder
  Widget _activityCard(ActivityItem item) {
    final statusConfig = _statusConfig(item.status);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cardBorder),
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
          // status indicator
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
                // booking info
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
                              color: AppColors.textGrey,
                              letterSpacing: 0.5,
                            ),
                          ),
                          2.heightBox,
                          Text(
                            item.date,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: AppColors.textLight,
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

                // destination details
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      color: AppColors.primary,
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
                              color: AppColors.textDark,
                            ),
                          ),
                          4.heightBox,
                          Text(
                            item.address,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: AppColors.textGrey,
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
                                item.amount > 0 ? AppColors.textDark : AppColors.textLight,
                          ),
                        ),
                        4.heightBox,
                        Text(
                          item.distance,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: AppColors.textGrey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                14.heightBox,

                // ride details
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Row(
                    children: [
                      _infoChip(
                        icon: Icons.local_hospital_rounded,
                        label: item.ambulanceType,
                        color: AppColors.primary,
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

                // eta for active rides
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
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.access_time_rounded,
                            color: AppColors.primary,
                            size: 16,
                          ),
                          8.widthBox,
                          Text(
                            'Ambulance arriving in ',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: AppColors.primary,
                            ),
                          ),
                          Text(
                            item.eta!,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Track',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // rebook option
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
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.refresh_rounded,
                                color: AppColors.primary,
                                size: 14,
                              ),
                              6.widthBox,
                              Text(
                                'Rebook',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // cancelled notice
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
                                color: AppColors.primary,
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

  // helper for info chips
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
            color: AppColors.textGrey,
          ),
        ),
      ],
    );
  }

  // status config
  StatusConfig _statusConfig(ActivityStatus status) {
    switch (status) {
      case ActivityStatus.active:
        return const StatusConfig(
          color: AppColors.primary,
          icon: Icons.local_hospital_rounded,
          label: 'En Route',
        );
      case ActivityStatus.completed:
        return const StatusConfig(
          color: Color(0xFF2E7D32),
          icon: Icons.check_circle_rounded,
          label: 'Completed',
        );
      case ActivityStatus.cancelled:
        return const StatusConfig(
          color: Color(0xFFE65100),
          icon: Icons.cancel_rounded,
          label: 'Cancelled',
        );
    }
  }
}
