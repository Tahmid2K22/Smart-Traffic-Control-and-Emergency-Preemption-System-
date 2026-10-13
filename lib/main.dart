import 'package:flutter/material.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'firebase_options.dart';

import 'constants/colors.dart';
import 'pages/home_page.dart';
import 'pages/activity_page.dart';
import 'pages/profile_page.dart';
import 'pages/login_page.dart';
import 'pages/driver/driver_dashboard_page.dart';
import 'pages/admin/admin_dashboard_page.dart';
import 'models/request_model.dart';
import 'services/request_service.dart';
import 'constants/app_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env — never crash if file is missing
  try { await AppConfig.load(); } catch (_) {}

  // Firebase is required — crash loudly if it fails
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Supabase is optional — driver features degrade if keys are not set
  try {
    final url = AppConfig.supabaseUrl;
    final key = AppConfig.supabaseAnonKey;
    // ignore: deprecated_member_use
    await Supabase.initialize(url: url, anonKey: key);
  } catch (_) {
    // No Supabase keys yet — app still runs for regular users
  }

  runApp(const AmbulanceApp());
}

class SetupErrorApp extends StatelessWidget {
  const SetupErrorApp({super.key, required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 64),
                const SizedBox(height: 24),
                const Text('Setup Required', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)),
                const SizedBox(height: 16),
                const Text('The app could not start because some environment variables are missing or invalid:', style: TextStyle(fontSize: 16, color: Colors.black54)),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade200)),
                  child: Text(error, style: TextStyle(fontSize: 14, fontFamily: 'monospace', color: Colors.red.shade900)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
        if (!snapshot.hasData) {
          return const LoginPage();
        }
        // Role-based routing: check Firestore role
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(snapshot.data!.uid)
              .get(),
          builder: (context, roleSnap) {
            if (!roleSnap.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
              );
            }
            final data = (roleSnap.data?.data() as Map<String, dynamic>?) ?? {};
            final role = data['role'] as String? ?? 'user';

            if (role == 'admin') {
              return const AdminDashboardPage();
            }
            if (role == 'driver') {
              return _DriverGate(
                firebaseUid: snapshot.data!.uid,
                firestoreData: data,
              );
            }
            return const DashboardPage();
          },
        );
      },
    );
  }
}

/// Loads or creates the driver's Supabase profile, checks approval, then shows
/// [DriverDashboardPage] or a pending-approval screen.
class _DriverGate extends StatefulWidget {
  const _DriverGate({required this.firebaseUid, required this.firestoreData});
  final String firebaseUid;
  final Map<String, dynamic> firestoreData;

  @override
  State<_DriverGate> createState() => _DriverGateState();
}

class _DriverGateState extends State<_DriverGate> {
  DriverProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDriver();
  }

  Future<void> _loadDriver() async {
    final data = widget.firestoreData;
    final isApprovedInFirestore = data['isApproved'] == true;

    // Upsert driver profile, including approval status from Firestore
    await RequestService.upsertDriverProfile(
      firebaseUid: widget.firebaseUid,
      name: data['name'] as String? ?? 'Driver',
      phone: data['phone'] as String? ?? '',
      vehicleType: data['vehicleType'] as String? ?? 'Basic',
      vehicleNumber: data['vehicleNumber'] as String? ?? '',
      isApproved: isApprovedInFirestore,
    );

    final profile = await RequestService.getMyDriverProfile();
    if (mounted) setState(() { _profile = profile; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    // Not yet approved — show a holding screen
    if (_profile == null || !_profile!.isApproved) {
      return _PendingApprovalScreen(
        driverName: widget.firestoreData['name'] as String? ?? 'Driver',
      );
    }

    return DriverDashboardPage(driver: _profile!);
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

// ── Pending approval holding screen ──────────────────────────────────────────

class _PendingApprovalScreen extends StatelessWidget {
  const _PendingApprovalScreen({required this.driverName});
  final String driverName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  color: AppColors.warningLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.pending_actions_rounded,
                  size: 56,
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Account Pending Approval',
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Hi $driverName, your driver account is under review.\n\nAn admin will verify your credentials and approve your account shortly.',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: AppColors.textGrey,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.warningLight,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.hourglass_top_rounded, color: AppColors.warning, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Status: Pending',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        color: AppColors.warning,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              // Logout button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  icon: const Icon(Icons.logout_rounded),
                  label: Text(
                    'Logout',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textGrey,
                    side: const BorderSide(color: AppColors.cardBorder),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
