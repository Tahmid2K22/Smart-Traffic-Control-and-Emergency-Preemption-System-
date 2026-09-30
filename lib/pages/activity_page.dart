import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:velocity_x/velocity_x.dart';

import '../constants/colors.dart';
import '../models/message_model.dart';
import '../models/request_model.dart';
import '../services/request_service.dart';
import 'chat_page.dart';
import 'tracking_page.dart';

class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedFilter = 0;
  bool _loading = true;
  List<AmbulanceRequest> _requests = [];

  final List<String> _filters = ['All', 'Active', 'Completed', 'Cancelled'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _filters.length, vsync: this);
    _loadRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    setState(() => _loading = true);
    try {
      final requests = await RequestService.getUserRequests();
      if (mounted) setState(() => _requests = requests);
    } catch (_) {
      // Graceful failure — show empty state
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<AmbulanceRequest> get _filtered {
    switch (_selectedFilter) {
      case 1: return _requests.where((r) => r.status == RequestStatus.accepted || r.status == RequestStatus.enRoute || r.status == RequestStatus.arrived).toList();
      case 2: return _requests.where((r) => r.status == RequestStatus.completed).toList();
      case 3: return _requests.where((r) => r.status == RequestStatus.cancelled).toList();
      default: return _requests;
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
            _buildFilterTabs(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _buildList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Activity', style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                Text('Your ambulance booking history', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textGrey)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadRequests,
            icon: const Icon(Icons.refresh_rounded, color: AppColors.textDark),
          ),
        ],
      ),
    );
  }

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
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : AppColors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isSelected ? AppColors.primary : AppColors.cardBorder),
                  boxShadow: isSelected
                      ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3))]
                      : [],
                ),
                child: Text(
                  _filters[index],
                  style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: isSelected ? AppColors.white : AppColors.textGrey),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildList() {
    final items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
              child: const Icon(Icons.receipt_long_rounded, size: 40, color: AppColors.primary),
            ),
            20.heightBox,
            Text('No activity found', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textDark)),
            8.heightBox,
            Text('You have no bookings in this category', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textGrey)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRequests,
      color: AppColors.primary,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, _) => 14.heightBox,
        itemBuilder: (context, index) => _requestCard(items[index]),
      ),
    );
  }

  Widget _requestCard(AmbulanceRequest req) {
    final isActive = req.status == RequestStatus.accepted ||
        req.status == RequestStatus.enRoute ||
        req.status == RequestStatus.arrived;
    final isCompleted = req.status == RequestStatus.completed;
    final isCancelled = req.status == RequestStatus.cancelled;

    Color statusColor;
    IconData statusIcon;
    String statusLabel;

    if (isActive) {
      statusColor = AppColors.primary;
      statusIcon = Icons.local_hospital_rounded;
      statusLabel = req.status.label;
    } else if (isCompleted) {
      statusColor = AppColors.success;
      statusIcon = Icons.check_circle_rounded;
      statusLabel = 'Completed';
    } else if (isCancelled) {
      statusColor = AppColors.warning;
      statusIcon = Icons.cancel_rounded;
      statusLabel = 'Cancelled';
    } else {
      statusColor = Colors.orange;
      statusIcon = Icons.access_time_rounded;
      statusLabel = 'Pending';
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          // Status bar
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                      child: Icon(statusIcon, color: statusColor, size: 20),
                    ),
                    10.widthBox,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(req.id.substring(0, 8).toUpperCase(), style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textGrey, letterSpacing: 0.5)),
                          2.heightBox,
                          Text(_formatDate(req.createdAt), style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textLight)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                      child: Text(statusLabel, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
                    ),
                  ],
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, color: Color(0xFFEFEFEF)),
                ),

                // Route info
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on_rounded, color: AppColors.primary, size: 18),
                    8.widthBox,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(req.destinationAddress, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textDark), maxLines: 1, overflow: TextOverflow.ellipsis),
                          4.heightBox,
                          Text(req.pickupAddress, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textGrey), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(req.estimatedFare > 0 ? 'BDT ${req.estimatedFare}' : 'No charge',
                          style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: req.estimatedFare > 0 ? AppColors.textDark : AppColors.textLight)),
                        4.heightBox,
                        Text('${req.distanceKm.toStringAsFixed(1)} km', style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textGrey)),
                      ],
                    ),
                  ],
                ),

                14.heightBox,

                // Details strip
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder)),
                  child: Row(
                    children: [
                      _infoChip(icon: Icons.local_hospital_rounded, label: req.ambulanceType, color: AppColors.primary),
                      const Spacer(),
                      if (req.driverName != null)
                        _infoChip(icon: Icons.person_outline_rounded, label: req.driverName!.split(' ').last, color: const Color(0xFF1565C0)),
                    ],
                  ),
                ),

                // Active trip — Track button
                if (isActive) ...[
                  12.heightBox,
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => TrackingPage(requestId: req.id, isDriver: false),
                        )),
                        icon: const Icon(Icons.my_location_rounded, size: 16),
                        label: Text('Track Driver', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    if (req.driverId != null) ...[
                      12.widthBox,
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => ChatPage(
                              requestId: req.id,
                              senderRole: SenderRole.user,
                              senderName: req.userName,
                              request: req,
                            ),
                          )),
                          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                          label: Text('Chat', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.infoBlue,
                            side: const BorderSide(color: AppColors.infoBlue),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ]),
                ],

                // Cancelled — cancel info
                if (isCancelled) ...[
                  12.heightBox,
                  Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFFE65100)),
                      6.widthBox,
                      Text('Booking was cancelled', style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFFE65100))),
                    ],
                  ),
                ],

                // Completed with driver — View Chat history
                if (isCompleted && req.driverId != null) ...[
                  12.heightBox,
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => ChatPage(
                          requestId: req.id,
                          senderRole: SenderRole.user,
                          senderName: req.userName,
                          request: req,
                        ),
                      )),
                      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                      label: Text('View Chat History', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.infoBlue,
                        side: const BorderSide(color: AppColors.infoBlue),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip({required IconData icon, required String label, required Color color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        5.widthBox,
        Text(label, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textGrey)),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today, ${_time(dt)}';
    if (diff.inDays == 1) return 'Yesterday, ${_time(dt)}';
    return '${dt.day} ${_month(dt.month)}, ${_time(dt)}';
  }

  String _time(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $period';
  }

  String _month(int m) => const ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m - 1];
}
