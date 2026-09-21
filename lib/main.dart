import 'package:flutter/material.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

import 'constants/colors.dart';
import 'pages/home_page.dart';
import 'pages/activity_page.dart';
import 'pages/profile_page.dart';
import 'pages/login_page.dart';
import 'pages/admin/admin_dashboard_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const AmbulanceApp());
}

class AmbulanceApp extends StatelessWidget {
  const AmbulanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'E-Ambulance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.background,
        textTheme: GoogleFonts.poppinsTextTheme(),
        colorSchemeSeed: AppColors.primary,
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Not signed in
        if (!snapshot.hasData) {
          return const LoginPage();
        }

        // Signed in → read role from Firestore to route correctly
        final uid = snapshot.data!.uid;
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get(),
          builder: (context, roleSnap) {
            if (roleSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final data =
                roleSnap.data?.data() as Map<String, dynamic>?;
            final role = data?['role'] ?? 'user';

            if (role == 'admin') {
              return const AdminDashboardPage();
            }
            return const DashboardPage();
          },
        );
      },
    );
  }
}

// main tab layout
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _selectedTab = 0;

  // tabs
  static const List<Widget> _pages = [
    HomePage(),
    ActivityPage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _pages[_selectedTab],
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // bottom navigation
  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: GNav(
            gap: 8,
            activeColor: AppColors.primary,
            iconSize: 22,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            duration: const Duration(milliseconds: 400),
            tabBackgroundColor: AppColors.primaryLight,
            color: AppColors.textLight,
            tabs: [
              GButton(
                icon: Icons.home_rounded,
                text: 'Home',
                textStyle: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              GButton(
                icon: Icons.receipt_long_rounded,
                text: 'Activity',
                textStyle: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              GButton(
                icon: Icons.person_rounded,
                text: 'Account',
                textStyle: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
            selectedIndex: _selectedTab,
            onTabChange: (index) => setState(() => _selectedTab = index),
          ),
        ),
      ),
    );
  }
}
