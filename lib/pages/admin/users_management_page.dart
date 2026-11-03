import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:velocity_x/velocity_x.dart';

import '../../constants/colors.dart';
import '../../services/admin_service.dart';

class UsersManagementPage extends StatefulWidget {
  const UsersManagementPage({super.key});

  @override
  State<UsersManagementPage> createState() => _UsersManagementPageState();
}

class _UsersManagementPageState extends State<UsersManagementPage> {
  final _adminService = AdminService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _adminService.allUsersStream(),
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
            return _UserCard(
              uid: doc.id,
              data: data,
              adminService: _adminService,
            );
          },
        );
      },
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.people_outline_rounded,
            size: 64,
            color: AppColors.textLight,
          ),
          16.heightBox,
          Text(
            'No users found',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textGrey,
            ),
          ),
        ],
      ),
    );
  }
}

// User card widget
class _UserCard extends StatefulWidget {
  final String uid;
  final Map<String, dynamic> data;
  final AdminService adminService;

  const _UserCard({
    required this.uid,
    required this.data,
    required this.adminService,
  });

  @override
  State<_UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<_UserCard> {
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
          'Delete User',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Are you sure you want to delete "${widget.data['name'] ?? 'User'}"? This action cannot be undone.',
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
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text('Delete', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }

  void _showMakeTrafficPoliceDialog(BuildContext ctx) {
    final policeIdCtrl = TextEditingController(
      text: widget.data['policeId']?.toString() ?? '',
    );
    final intersectionCtrl = TextEditingController(
      text: widget.data['assignedIntersection']?.toString() ?? '',
    );
    final name = (widget.data['name'] ?? widget.data['fullName'] ?? 'User').toString();

    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.local_police_rounded, color: Color(0xFF2E7D32), size: 22),
            ),
            10.widthBox,
            Expanded(
              child: Text(
                'Make Traffic Police',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Assign Traffic Police role to "$name". This authorizes the user to communicate with and control ESP32 traffic light signals.',
                style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textGrey),
              ),
              16.heightBox,
              TextField(
                controller: policeIdCtrl,
                decoration: InputDecoration(
                  labelText: 'Police / Badge ID (optional)',
                  hintText: 'e.g. TP-402',
                  prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              12.heightBox,
              TextField(
                controller: intersectionCtrl,
                decoration: InputDecoration(
                  labelText: 'Assigned Intersection (optional)',
                  hintText: 'e.g. Kakrail Crossing',
                  prefixIcon: const Icon(Icons.traffic_outlined, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Cancel', style: GoogleFonts.poppins(color: AppColors.textGrey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              _doAction(() => widget.adminService.makeTrafficPolice(
                widget.uid,
                name: name,
                policeId: policeIdCtrl.text.trim(),
                assignedIntersection: intersectionCtrl.text.trim(),
              ));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Assign Police Role', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final String role = (data['role'] as String? ?? 'user').toLowerCase();
    final bool isAdmin = role == 'admin';
    final bool isTrafficPolice = role == 'traffic_police';
    final String name = data['name'] ?? data['fullName'] ?? 'Unknown';
    final String email = data['email'] ?? 'Unknown';
    final String phone = data['phone'] ?? 'Unknown';
    final String city = data['city'] ?? 'Unknown';
    final String? policeId = data['policeId']?.toString();
    final String? intersection = data['assignedIntersection']?.toString();

    Color borderColor = AppColors.cardBorder;
    if (isAdmin) {
      borderColor = AppColors.accentOrange.withValues(alpha: 0.4);
    } else if (isTrafficPolice) {
      borderColor = const Color(0xFF2E7D32).withValues(alpha: 0.4);
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isTrafficPolice
                        ? const Color(0xFFE8F5E9)
                        : (isAdmin ? const Color(0xFFFFF3E0) : AppColors.background),
                  ),
                  child: Center(
                    child: Text(
                      _initials(name),
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isTrafficPolice
                            ? const Color(0xFF2E7D32)
                            : (isAdmin ? AppColors.accentOrange : AppColors.textGrey),
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
                        email,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: AppColors.textGrey,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Role badge
                _RoleBadge(role: role),
              ],
            ),
            12.heightBox,
            const Divider(height: 1, color: Color(0xFFF0F0F0)),
            12.heightBox,
            // Info Rows
            _infoRow(Icons.phone_outlined, 'Phone', phone),
            6.heightBox,
            _infoRow(Icons.location_city_rounded, 'City', city),

            if (isTrafficPolice && policeId != null && policeId.isNotEmpty) ...[
              6.heightBox,
              _infoRow(Icons.badge_outlined, 'Police ID', policeId),
            ],
            if (isTrafficPolice && intersection != null && intersection.isNotEmpty) ...[
              6.heightBox,
              _infoRow(Icons.traffic_outlined, 'Intersection', intersection),
            ],

            14.heightBox,
            // Actions
            if (_loading)
              const Center(
                child: SizedBox(
                  height: 36,
                  width: 36,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Row(
                children: [
                  // Role Toggle Button
                  if (isTrafficPolice) ...[
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.person_remove_rounded,
                        label: 'Remove Police',
                        color: Colors.orange.shade800,
                        onTap: () => _doAction(
                          () => widget.adminService.removeTrafficPolice(widget.uid, name: name),
                        ),
                      ),
                    ),
                  ] else if (isAdmin) ...[
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.person_remove_rounded,
                        label: 'Remove Admin',
                        color: AppColors.accentOrange,
                        onTap: () => _doAction(
                          () => widget.adminService.removeAdmin(widget.uid, name: name),
                        ),
                      ),
                    ),
                  ] else ...[
                    // User or Patient -> Provide "Make Traffic Police" + "Make Admin"
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.local_police_rounded,
                        label: 'Make Police',
                        color: const Color(0xFF2E7D32),
                        onTap: () => _showMakeTrafficPoliceDialog(context),
                      ),
                    ),
                    8.widthBox,
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.admin_panel_settings_rounded,
                        label: 'Make Admin',
                        color: AppColors.infoBlue,
                        onTap: () => _doAction(
                          () => widget.adminService.makeAdmin(widget.uid, name: name),
                        ),
                      ),
                    ),
                  ],

                  8.widthBox,
                  // Delete button
                  SizedBox(
                    width: 44,
                    height: 40,
                    child: OutlinedButton(
                      onPressed: () => _confirmDelete(context),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Icon(Icons.delete_outline_rounded, size: 20),
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

// Role badge with dynamic colors & icons
class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (role) {
      'admin'          => (AppColors.accentOrange, Icons.admin_panel_settings_rounded, 'Admin'),
      'traffic_police' => (const Color(0xFF2E7D32), Icons.local_police_rounded, 'Traffic Police'),
      'patient'        => (AppColors.infoBlue, Icons.person_rounded, 'Patient'),
      _                => (AppColors.primary, Icons.person_rounded, 'User'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          4.widthBox,
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
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
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600),
      ),
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
