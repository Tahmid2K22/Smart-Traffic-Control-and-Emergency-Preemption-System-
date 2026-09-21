import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:velocity_x/velocity_x.dart';
import '../../constants/colors.dart';
import '../../services/admin_service.dart';

class DriversManagementPage extends StatefulWidget {
  const DriversManagementPage({super.key});

  @override
  State<DriversManagementPage> createState() => _DriversManagementPageState();
}

class _DriversManagementPageState extends State<DriversManagementPage> {
  final _adminService = AdminService();

  // 0 = All, 1 = Pending, 2 = Verified, 3 = Rejected
  int _filterIndex = 0;

  static const _filters = ['All', 'Pending', 'Verified', 'Rejected'];

  Stream<QuerySnapshot> _buildStream() {
    final col = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'driver');

    switch (_filterIndex) {
      case 1:
        // Pending: isApproved == false AND never explicitly rejected
        return col.where('isApproved', isEqualTo: false).snapshots();
      case 2:
        return col.where('isApproved', isEqualTo: true).snapshots();
      case 3:
        return col.where('isApproved', isEqualTo: false).snapshots();
      default:
        return col.snapshots();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filter chips
        _buildFilterRow(),
        // Driver list
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _buildStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return _buildEmpty();
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                itemCount: docs.length,
                separatorBuilder: (context, index) => 12.heightBox,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  return _DriverCard(
                    uid: doc.id,
                    data: data,
                    adminService: _adminService,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(_filters.length, (i) {
            final isSelected = _filterIndex == i;
            return Padding(
              padding: EdgeInsets.only(right: i < _filters.length - 1 ? 8 : 0),
              child: FilterChip(
                label: Text(
                  _filters[i],
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : AppColors.textGrey,
                  ),
                ),
                selected: isSelected,
                onSelected: (_) => setState(() => _filterIndex = i),
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.background,
                checkmarkColor: Colors.white,
                side: BorderSide(
                  color: isSelected ? AppColors.primary : AppColors.cardBorder,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_taxi_rounded, size: 64, color: AppColors.textLight),
          16.heightBox,
          Text(
            'No drivers found',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textGrey,
            ),
          ),
          8.heightBox,
          Text(
            'Drivers will appear here once registered',
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: AppColors.textLight,
            ),
          ),
        ],
      ),
    );
  }
}

// driver card widget
class _DriverCard extends StatefulWidget {
  final String uid;
  final Map<String, dynamic> data;
  final AdminService adminService;

  const _DriverCard({
    required this.uid,
    required this.data,
    required this.adminService,
  });

  @override
  State<_DriverCard> createState() => _DriverCardState();
}

class _DriverCardState extends State<_DriverCard> {
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

  void _confirmDelete(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete Driver',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Are you sure you want to delete "${widget.data['name']}"? This action cannot be undone.',
          style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _doAction(() => widget.adminService.deleteUser(widget.uid));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Delete', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final bool isApproved = data['isApproved'] == true;
    final String name = data['name'] ?? 'Unknown';
    final String phone = data['phone'] ?? '–';
    final String city = data['city'] ?? '–';
    final String vehicleType = data['vehicleType'] ?? '–';
    final String vehicleNumber = data['vehicleNumber'] ?? '–';
    final String license = data['drivingLicense'] ?? '–';

    return Container(
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                // avatar
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryDark],
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _initials(name),
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
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
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                      Text(
                        phone,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: AppColors.textGrey,
                        ),
                      ),
                    ],
                  ),
                ),
                // status badge
                _StatusBadge(isApproved: isApproved),
              ],
            ),
            12.heightBox,
            const Divider(height: 1, color: Color(0xFFF0F0F0)),
            12.heightBox,
            // Info grid
            _infoRow(Icons.location_city_rounded, 'City', city),
            6.heightBox,
            _infoRow(Icons.directions_car_rounded, 'Vehicle', '$vehicleType • $vehicleNumber'),
            6.heightBox,
            _infoRow(Icons.badge_rounded, 'License', license),
            12.heightBox,
            // Action buttons
            if (_loading)
              const Center(child: SizedBox(height: 36, width: 36, child: CircularProgressIndicator(strokeWidth: 2)))
            else
              Row(
                children: [
                  // Verify / Verified toggle
                  Expanded(
                    child: _ActionButton(
                      icon: isApproved
                          ? Icons.cancel_outlined
                          : Icons.check_circle_outline_rounded,
                      label: isApproved ? 'Revoke' : 'Verify',
                      color: isApproved ? AppColors.warning : AppColors.success,
                      onTap: () => _doAction(
                        () => isApproved
                            ? widget.adminService.rejectDriver(widget.uid)
                            : widget.adminService.verifyDriver(widget.uid),
                      ),
                    ),
                  ),
                  8.widthBox,
                  // Delete
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.delete_outline_rounded,
                      label: 'Delete',
                      color: Colors.red.shade700,
                      onTap: () => _confirmDelete(context),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        6.widthBox,
        Text(
          '$label: ',
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: AppColors.textLight,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: AppColors.textDark,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }
}

// reusable small widgets
class _StatusBadge extends StatelessWidget {
  final bool isApproved;
  const _StatusBadge({required this.isApproved});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isApproved ? AppColors.successLight : AppColors.warningLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isApproved ? Icons.verified_rounded : Icons.pending_rounded,
            size: 12,
            color: isApproved ? AppColors.success : AppColors.warning,
          ),
          4.widthBox,
          Text(
            isApproved ? 'Verified' : 'Pending',
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isApproved ? AppColors.success : AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            6.widthBox,
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
