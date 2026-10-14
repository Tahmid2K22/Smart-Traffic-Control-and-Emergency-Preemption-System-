import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:velocity_x/velocity_x.dart';
import '../../constants/colors.dart';
import '../../services/admin_service.dart';
import '../../services/hospital_service.dart';

class HospitalsManagementPage extends StatefulWidget {
  const HospitalsManagementPage({super.key});

  @override
  State<HospitalsManagementPage> createState() =>
      _HospitalsManagementPageState();
}

class _HospitalsManagementPageState extends State<HospitalsManagementPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _adminService = AdminService();
  final _hospitalService = HospitalService();
  bool _seeding = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _seed() async {
    setState(() => _seeding = true);
    try {
      await _hospitalService.seedKhulnaHospitals();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Khulna hospitals seeded successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Seed failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tab bar + Seed button
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TabBar(
                    controller: _tabs,
                    indicator: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: Colors.white,
                    unselectedLabelColor: AppColors.textGrey,
                    labelStyle: GoogleFonts.poppins(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    tabs: const [
                      Tab(text: 'Pending'),
                      Tab(text: 'All'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Seed Khulna data button
              Tooltip(
                message: 'Seed real Khulna hospitals',
                child: ElevatedButton.icon(
                  onPressed: _seeding ? null : _seed,
                  icon: _seeding
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.download_rounded, size: 16),
                  label: Text(
                    'Seed',
                    style: GoogleFonts.poppins(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Tab views
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              // Pending
              _HospitalList(
                stream: _adminService.pendingHospitalsStream(),
                emptyMessage: 'No pending hospitals',
                emptyIcon: Icons.check_circle_outline_rounded,
                adminService: _adminService,
              ),
              // All
              _HospitalList(
                stream: _adminService.allHospitalsStream(),
                emptyMessage: 'No hospitals registered yet',
                emptyIcon: Icons.local_hospital_outlined,
                adminService: _adminService,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Hospital list ─────────────────────────────────────────────────────────────

class _HospitalList extends StatelessWidget {
  const _HospitalList({
    required this.stream,
    required this.emptyMessage,
    required this.emptyIcon,
    required this.adminService,
  });

  final Stream<QuerySnapshot> stream;
  final String emptyMessage;
  final IconData emptyIcon;
  final AdminService adminService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(emptyIcon, size: 64, color: AppColors.textLight),
                16.heightBox,
                Text(
                  emptyMessage,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textGrey,
                  ),
                ),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          itemCount: docs.length,
          separatorBuilder: (_, _) => 12.heightBox,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return _HospitalCard(
              id: doc.id,
              data: data,
              adminService: adminService,
            );
          },
        );
      },
    );
  }
}

// ── Hospital card ─────────────────────────────────────────────────────────────

class _HospitalCard extends StatefulWidget {
  const _HospitalCard({
    required this.id,
    required this.data,
    required this.adminService,
  });

  final String id;
  final Map<String, dynamic> data;
  final AdminService adminService;

  @override
  State<_HospitalCard> createState() => _HospitalCardState();
}

class _HospitalCardState extends State<_HospitalCard> {
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
    final data = widget.data;
    final String name = data['name'] as String? ?? 'Unknown';
    final String city = data['city'] as String? ?? '–';
    final int beds = (data['beds'] as num?)?.toInt() ?? 0;
    final double lat = (data['lat'] as num?)?.toDouble() ?? 0.0;
    final double lon = (data['lon'] as num?)?.toDouble() ?? 0.0;
    final bool isApproved = data['isApproved'] as bool? ?? false;
    final List<String> services =
        List<String>.from(data['services'] as List? ?? []);
    final List<String> diagnoses =
        List<String>.from(data['diagnoses'] as List? ?? []);

    final statusColor = isApproved ? AppColors.success : AppColors.warning;
    final statusLabel = isApproved ? 'Approved' : 'Pending';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // status top bar
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
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
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.local_hospital_rounded,
                          color: AppColors.primary, size: 20),
                    ),
                    10.widthBox,
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
                          2.heightBox,
                          Text(
                            '$city  •  $beds beds',
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
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: statusColor),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        statusLabel,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, color: Color(0xFFEFEFEF)),
                ),

                // Coordinates
                Row(
                  children: [
                    const Icon(Icons.pin_drop_rounded,
                        color: AppColors.infoBlue, size: 16),
                    6.widthBox,
                    Text(
                      'Lat ${lat.toStringAsFixed(4)}, Lon ${lon.toStringAsFixed(4)}',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: AppColors.textGrey),
                    ),
                  ],
                ),
                10.heightBox,

                // Services chips
                if (services.isNotEmpty) ...[
                  Text('Services',
                      style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textGrey)),
                  6.heightBox,
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: services
                        .map((s) => _chip(s, AppColors.primary))
                        .toList(),
                  ),
                  10.heightBox,
                ],

                // Diagnoses chips
                if (diagnoses.isNotEmpty) ...[
                  Text('Specialties',
                      style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textGrey)),
                  6.heightBox,
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: diagnoses
                        .map((d) => _chip(d, const Color(0xFF1565C0)))
                        .toList(),
                  ),
                  12.heightBox,
                ],

                // Action buttons
                if (_loading)
                  const Center(
                    child: SizedBox(
                        height: 32,
                        width: 32,
                        child:
                            CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: _actionBtn(
                          icon: isApproved
                              ? Icons.cancel_outlined
                              : Icons.check_circle_outline_rounded,
                          label: isApproved ? 'Revoke' : 'Approve',
                          color: isApproved
                              ? AppColors.warning
                              : AppColors.success,
                          onTap: () => _doAction(
                            () => isApproved
                                ? widget.adminService
                                    .rejectHospital(widget.id, name: name)
                                : widget.adminService
                                    .approveHospital(widget.id, name: name),
                          ),
                        ),
                      ),
                      8.widthBox,
                      Expanded(
                        child: _actionBtn(
                          icon: Icons.delete_outline_rounded,
                          label: 'Delete',
                          color: Colors.red.shade700,
                          onTap: () => _confirmDelete(context, name),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext ctx, String name) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Hospital',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text(
          'Delete "$name"? This cannot be undone.',
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
              _doAction(
                () => widget.adminService
                    .rejectHospital(widget.id, name: name),
              );
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

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: color),
        ),
      );

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label,
          style: GoogleFonts.poppins(
              fontSize: 12, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: color,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: color.withValues(alpha: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 10),
      ),
    );
  }
}
