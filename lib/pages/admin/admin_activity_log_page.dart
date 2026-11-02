import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:velocity_x/velocity_x.dart';
import '../../constants/colors.dart';
import '../../models/models.dart';
import '../../services/admin_service.dart';

class AdminActivityLogPage extends StatelessWidget {
  const AdminActivityLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    final adminService = AdminService();
    return StreamBuilder<QuerySnapshot>(
      stream: adminService.adminLogsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
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
                const Icon(Icons.history_rounded,
                    size: 64, color: AppColors.textLight),
                16.heightBox,
                Text(
                  'No admin actions yet',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textGrey,
                  ),
                ),
                8.heightBox,
                Text(
                  'Actions taken by admins will appear here.',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppColors.textLight,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          itemCount: docs.length,
          separatorBuilder: (_, _) => 10.heightBox,
          itemBuilder: (context, index) {
            final log = AdminLog.fromDoc(docs[index]);
            return _LogTile(log: log);
          },
        );
      },
    );
  }
}

// ── Individual log entry ──────────────────────────────────────────────────────

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log});
  final AdminLog log;

  // Readable label + icon + color for each action key
  static const _actionMeta = {
    'approve_driver': (
      label: 'Approved Driver',
      icon: Icons.check_circle_rounded,
      color: AppColors.success,
    ),
    'reject_driver': (
      label: 'Rejected Driver',
      icon: Icons.cancel_rounded,
      color: Color(0xFFB71C1C),
    ),
    'approve_traffic_police': (
      label: 'Approved Traffic Officer',
      icon: Icons.verified_user_rounded,
      color: AppColors.success,
    ),
    'reject_traffic_police': (
      label: 'Rejected Traffic Officer',
      icon: Icons.gpp_bad_rounded,
      color: Color(0xFFB71C1C),
    ),
    'approve_hospital': (
      label: 'Approved Hospital',
      icon: Icons.local_hospital_rounded,
      color: AppColors.success,
    ),
    'reject_hospital': (
      label: 'Rejected Hospital',
      icon: Icons.local_hospital_rounded,
      color: Color(0xFFB71C1C),
    ),
    'make_admin': (
      label: 'Granted Admin Role',
      icon: Icons.admin_panel_settings_rounded,
      color: AppColors.accentOrange,
    ),
    'remove_admin': (
      label: 'Removed Admin Role',
      icon: Icons.admin_panel_settings_rounded,
      color: AppColors.warning,
    ),
    'delete_user': (
      label: 'Deleted User',
      icon: Icons.delete_rounded,
      color: Color(0xFFB71C1C),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final meta = _actionMeta[log.action];
    final color = meta?.color ?? AppColors.textGrey;
    final icon = meta?.icon ?? Icons.info_rounded;
    final actionLabel = meta?.label ?? log.action.replaceAll('_', ' ');

    final ts = log.timestamp;
    final String timeStr = ts == null
        ? '–'
        : _formatTimestamp(ts);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon badge
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          12.widthBox,

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Action label
                Text(
                  actionLabel,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                4.heightBox,

                // Target
                Row(
                  children: [
                    _targetIcon(log.targetType),
                    4.widthBox,
                    Expanded(
                      child: Text(
                        log.targetName.isEmpty ? log.targetId : log.targetName,
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
                6.heightBox,

                // Admin name + timestamp
                Row(
                  children: [
                    const Icon(Icons.person_rounded,
                        size: 12, color: AppColors.textLight),
                    3.widthBox,
                    Expanded(
                      child: Text(
                        log.adminName,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: AppColors.textLight,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Icon(Icons.access_time_rounded,
                        size: 11, color: AppColors.textLight),
                    3.widthBox,
                    Text(
                      timeStr,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: AppColors.textLight,
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

  Widget _targetIcon(String type) {
    final icon = switch (type) {
      'hospital' => Icons.local_hospital_outlined,
      'driver' => Icons.drive_eta_rounded,
      'traffic_police' => Icons.traffic_rounded,
      _ => Icons.person_outlined,
    };
    return Icon(icon, size: 13, color: AppColors.textLight);
  }

  String _formatTimestamp(Timestamp ts) {
    final dt = ts.toDate().toLocal();
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
