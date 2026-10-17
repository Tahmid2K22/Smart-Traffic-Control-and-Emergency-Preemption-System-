import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class PendingVerificationScreen extends StatelessWidget {
  const PendingVerificationScreen({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final rejected = status == 'REJECTED';
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                rejected ? Icons.cancel_outlined : Icons.pending_actions_rounded,
                size: 76,
                color: rejected ? Colors.redAccent : Colors.orange,
              ),
              const SizedBox(height: 24),
              Text(
                rejected ? 'Verification was not approved' : 'Officer badge verification pending',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                rejected
                    ? 'Please contact an administrator to correct your registration details.'
                    : 'Your officer badge is currently being verified by an administrator. Features will unlock upon approval.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              OutlinedButton.icon(
                onPressed: () => FirebaseAuth.instance.signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
