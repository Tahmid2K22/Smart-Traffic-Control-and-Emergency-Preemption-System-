import 'package:flutter/material.dart';
import 'package:velocity_x/velocity_x.dart';
import 'package:badges/badges.dart' as badges;
import 'package:google_fonts/google_fonts.dart';
import '../constants/colors.dart';
import '../models/models.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

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

  // top bar
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          // avatar
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
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
          // greeting
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello, Tahmid!',
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
                    fontWeight: FontWeight.w400,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          ),
          // notifications
          badges.Badge(
            position: badges.BadgePosition.topEnd(top: -2, end: -2),
            badgeStyle: const badges.BadgeStyle(
              badgeColor: AppColors.primary,
              padding: EdgeInsets.all(5),
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
                color: AppColors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: const Icon(
                Icons.notifications_none_rounded,
                color: AppColors.textDark,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // search bar
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder),
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
            const Icon(Icons.search_rounded, color: AppColors.textLight, size: 22),
            12.widthBox,
            Expanded(
              child: Text(
                'Search hospitals, pharmacies...',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: AppColors.textLight,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            Container(width: 1, height: 22, color: AppColors.cardBorder),
            12.widthBox,
            const Icon(Icons.mic_none_rounded, color: AppColors.primary, size: 22),
          ],
        ),
      ),
    );
  }

  // emergency banner
  Widget _buildPromoBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
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
              child: const Center(
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

  // services
  Widget _buildServiceGrid() {
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
        subtitle: 'Order Medicine',
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

  Widget _serviceCard(ServiceItem svc) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
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
              color: AppColors.textDark,
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

  // nearby hospitals
  Widget _buildNearbyHospitals() {
    final hospitals = [
      const HospitalData(
        name: 'Khulna Medical College Hospital',
        address: 'Moylapota, Khulna',
        distance: '1.2 km',
        isOpen: true,
        beds: 12,
        specialties: ['Emergency', 'ICU', 'Surgery'],
      ),
      const HospitalData(
        name: 'Shaheed Sheikh Abu Naser Hospital',
        address: 'Sonadanga, Khulna',
        distance: '2.8 km',
        isOpen: true,
        beds: 8,
        specialties: ['Emergency', 'Cardiology'],
      ),
      const HospitalData(
        name: 'Gazi Medical College',
        address: 'Chuknagar, Khulna',
        distance: '3.5 km',
        isOpen: true,
        beds: 5,
        specialties: ['General', 'Orthopedics'],
      ),
      const HospitalData(
        name: 'Ad-Din Hospital',
        address: 'Nirala, Khulna',
        distance: '4.1 km',
        isOpen: false,
        beds: 0,
        specialties: ['Gynecology', 'Pediatrics'],
      ),
      const HospitalData(
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
                      4.widthBox,
                      Text(
                        'Khulna Division',
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
                onPressed: () {},
                icon: const Icon(Icons.map_rounded, size: 16, color: AppColors.primary),
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

  Widget _hospitalCard(HospitalData hospital) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
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
          // hospital info
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                        color: AppColors.textDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    4.heightBox,
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: AppColors.textLight,
                        ),
                        4.widthBox,
                        Expanded(
                          child: Text(
                            '${hospital.address}  •  ${hospital.distance}',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: AppColors.textGrey,
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
          // hospital details
          Row(
            children: [
              if (hospital.isOpen) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bed_rounded, size: 14, color: AppColors.primary),
                      4.widthBox,
                      Text(
                        '${hospital.beds} beds',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
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
                  style: GoogleFonts.poppins(fontSize: 10, color: AppColors.textLight),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary,
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

  // recent requests
  Widget _buildRecentSection() {
    final requests = [
      const RequestData(
        location: 'Khulna Medical College',
        address: 'Moylapota, Khulna',
        time: '2 min ago',
        status: 'Pending',
      ),
      const RequestData(
        location: 'Sheikh Abu Naser Hospital',
        address: 'Sonadanga, Khulna',
        time: '8 min ago',
        status: 'Assigned',
      ),
      const RequestData(
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
                  color: AppColors.textDark,
                ),
              ),
              TextButton(
                onPressed: () {},
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

  Widget _recentRequestCard(RequestData data) {
    final bool isPending = data.status == 'Pending';
    final bool isCompleted = data.status == 'Completed';

    final Color statusColor = isCompleted
        ? const Color(0xFF2E7D32)
        : isPending
        ? AppColors.primary
        : const Color(0xFFFF6F00);

    final Color statusBg = isCompleted
        ? const Color(0xFFE8F5E9)
        : isPending
        ? AppColors.primaryLight
        : const Color(0xFFFFF3E0);

    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
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
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: AppColors.primary,
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
                    color: AppColors.textDark,
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
                style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textGrey),
              ),
              4.heightBox,
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.access_time_rounded,
                        size: 12,
                        color: AppColors.textLight,
                      ),
                      4.widthBox,
                      Text(
                        data.time,
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: AppColors.textLight,
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
