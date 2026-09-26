import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/colors.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const _EmptyNotifications();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Notifications'), backgroundColor: Colors.transparent, elevation: 0),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('notifications').where('userId', isEqualTo: user.uid).orderBy('createdAt', descending: true).limit(50).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const _EmptyNotifications(message: 'Notifications are temporarily unavailable.');
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          final documents = snapshot.data!.docs;
          if (documents.isEmpty) return const _EmptyNotifications();
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            itemCount: documents.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _NotificationCard(data: documents[index].data()),
          );
        },
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.cardBorder)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const CircleAvatar(backgroundColor: AppColors.primaryLight, foregroundColor: AppColors.primary, child: Icon(Icons.notifications_active_rounded, size: 19)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(data['title']?.toString() ?? 'E-Ambulance update', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark)), const SizedBox(height: 4), Text(data['body']?.toString() ?? 'You have a new update.', style: const TextStyle(fontSize: 12, color: AppColors.textGrey))]))]));
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications({this.message = 'You are all caught up.'});
  final String message;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.notifications_none_rounded, size: 52, color: AppColors.textLight), const SizedBox(height: 12), Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textGrey))])));
}
