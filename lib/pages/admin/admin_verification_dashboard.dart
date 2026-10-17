import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../constants/colors.dart';
import '../../services/admin_service.dart';

class AdminVerificationDashboard extends StatelessWidget {
  const AdminVerificationDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final service = AdminService();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Traffic Police Verification'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: service.pendingTrafficPoliceStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Unable to load requests: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final requests = snapshot.data!.docs;
          if (requests.isEmpty) {
            return const Center(child: Text('No pending officer requests.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final doc = requests[index];
              final data = doc.data()! as Map<String, dynamic>;
              return _VerificationCard(
                uid: doc.id,
                data: data,
                service: service,
              );
            },
          );
        },
      ),
    );
  }
}

class _VerificationCard extends StatefulWidget {
  const _VerificationCard({
    required this.uid,
    required this.data,
    required this.service,
  });

  final String uid;
  final Map<String, dynamic> data;
  final AdminService service;

  @override
  State<_VerificationCard> createState() => _VerificationCardState();
}

class _VerificationCardState extends State<_VerificationCard> {
  bool _busy = false;

  Future<void> _update(bool approve) async {
    setState(() => _busy = true);
    try {
      final name = widget.data['fullName'] ?? widget.data['name'] ?? 'Officer';
      if (approve) {
        await widget.service.verifyTrafficPolice(widget.uid, name: name.toString());
      } else {
        await widget.service.rejectTrafficPolice(widget.uid, name: name.toString());
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update request: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.data['fullName'] ?? widget.data['name'] ?? 'Officer').toString();
    final badgeUrl = widget.data['badgeImageUrl']?.toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (badgeUrl != null && badgeUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      badgeUrl,
                      width: 76,
                      height: 76,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _badgePlaceholder(),
                    ),
                  )
                else
                  _badgePlaceholder(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 5),
                      Text('Police ID: ${widget.data['policeId'] ?? 'Not provided'}'),
                      Text('Junction: ${widget.data['assignedIntersection'] ?? 'Not provided'}'),
                      Text(widget.data['email']?.toString() ?? ''),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _update(false),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                    onPressed: _busy ? null : () => _update(true),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _badgePlaceholder() => Container(
        width: 76,
        height: 76,
        color: AppColors.primaryLight,
        child: const Icon(Icons.badge_rounded, color: AppColors.primary),
      );
}
