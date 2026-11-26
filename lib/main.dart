import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import 'firebase_options.dart';

import 'constants/colors.dart';
import 'models/user_profile.dart';
import 'pages/home_page.dart';
import 'pages/activity_page.dart';
import 'pages/profile_page.dart';
import 'pages/login_page.dart';
import 'pages/driver/driver_dashboard_page.dart';
import 'pages/admin/admin_dashboard_page.dart';
import 'pages/hospital/hospital_dashboard_page.dart';
import 'pages/traffic/pending_verification_screen.dart';
import 'pages/simple_traffic_page.dart';
import 'models/request_model.dart';
import 'services/request_service.dart';
import 'services/user_service.dart';
import 'constants/app_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await AppConfig.load();
  } catch (_) {}

  try {
    await _initializeFirebase();
  } catch (error) {
    runApp(SetupErrorApp(error: 'Firebase failed to start:\n\n$error'));
    return;
  }


  try {
    final url = AppConfig.supabaseUrl;
    final key = AppConfig.supabaseAnonKey;
    await Supabase.initialize(url: url, anonKey: key); // ignore: deprecated_member_use
  } catch (_) {
    // No Supabase keys — app still runs for regular users
  }

  runApp(const AmbulanceApp());
}

/// Reuse the existing app if duplicate-app fires; RTDB passes its URL explicitly.
Future<void> _initializeFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (error) {
    if (error.code != 'duplicate-app' || Firebase.apps.isEmpty) rethrow;
    Firebase.app();
  }
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
                const Icon(
                  Icons.error_outline_rounded,
                  color: Colors.redAccent,
                  size: 64,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Setup Required',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'The app could not start. Details:',
                  style: TextStyle(fontSize: 16, color: Colors.black54),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    error,
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: 'monospace',
                      color: Colors.red.shade900,
                    ),
                  ),
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
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }
        final user = snapshot.data;
        if (user == null) {
          return const DashboardPage(key: ValueKey('guest'), isGuest: true);
        }
        return _ProfileGate(
          key: ValueKey(user.uid),
          uid: user.uid,
          fallbackName: user.displayName,
          fallbackEmail: user.email,
        );
      },
    );
  }
}

/// Loads profile by role; streams updates for role/approval changes.
class _ProfileGate extends StatefulWidget {
  const _ProfileGate({
    super.key,
    required this.uid,
    this.fallbackName,
    this.fallbackEmail,
  });

  final String uid;
  final String? fallbackName;
  final String? fallbackEmail;

  @override
  State<_ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<_ProfileGate> {
  UserProfile? _profile;
  bool _loading = true;
  StreamSubscription<UserProfile?>? _watch;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    UserProfile? profile;
    try {
      profile = await UserService.instance.fetchOrMigrate(
        widget.uid,
        fallbackName: widget.fallbackName,
        fallbackEmail: widget.fallbackEmail,
      );
    } catch (error) {
      debugPrint('Profile load failed: $error');
    }
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _loading = false;
    });

    _watch = UserService.instance.watchProfile(widget.uid).listen(
      (updated) {
        if (!mounted || updated == null) return;
        setState(() => _profile = updated);
      },
      onError: (Object error) {
        debugPrint('Profile stream error: $error');
      },
    );
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final profile = _profile;
    // No profile (offline/unconfigured): keep app usable as regular user.
    if (profile == null) {
      return DashboardPage(key: ValueKey('profile-${widget.uid}'));
    }

    if (profile.isAdmin) {
      return const AdminDashboardPage();
    }
    if (profile.isTrafficOfficer) {
      if (!profile.isVerifiedOfficer) {
        return PendingVerificationScreen(status: profile.verificationStatus);
      }
      return SimpleTrafficPage(
        assignedIntersection: profile.assignedIntersection,
      );
    }
    if (profile.isDriver) {
      return _DriverGate(profile: profile);
    }
    if (profile.isHospital) {
      if (!profile.isApproved) {
        return _HospitalPendingScreen(hospitalName: profile.displayName);
      }
      return HospitalDashboardPage(profile: profile.toData());
    }
    return DashboardPage(key: ValueKey(profile.uid));
  }
}

class _HospitalPendingScreen extends StatelessWidget {
  const _HospitalPendingScreen({required this.hospitalName});

  final String hospitalName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.hourglass_top_rounded,
                size: 64,
                color: AppColors.warning,
              ),
              const SizedBox(height: 20),
              Text(
                '$hospitalName is awaiting approval',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'An administrator will review your registration. After approval, sign in again to manage services, specialties, beds, and map location.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => FirebaseAuth.instance.signOut(),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Loads/creates driver profile, checks approval, then routes.
class _DriverGate extends StatefulWidget {
  const _DriverGate({required this.profile});
  final UserProfile profile;

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
    final profile = widget.profile;

    await RequestService.upsertDriverProfile(
      firebaseUid: profile.uid,
      name: profile.name.isEmpty ? 'Driver' : profile.name,
      phone: profile.phone,
      vehicleType: profile.vehicleType ?? 'Basic',
      vehicleNumber: profile.vehicleNumber ?? '',
      isApproved: profile.isApproved,
    );

    final driver = await RequestService.getMyDriverProfile();
    if (mounted) {
      setState(() {
        _profile = driver;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (_profile == null || !_profile!.isApproved) {
      return _PendingApprovalScreen(
        driverName: widget.profile.displayName,
      );
    }

    return DriverDashboardPage(driver: _profile!);
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, this.isGuest = false});

  final bool isGuest;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _selectedTab = 0;

  void _selectTab(int index) {
    setState(() => _selectedTab = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: widget.isGuest
          ? HomePage(isGuest: true)
          : switch (_selectedTab) {
              1 => const ActivityPage(),
              2 => const ProfilePage(),
              _ => const HomePage(),
            },
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    // Guests only see Home + a Login shortcut; Activity and Account are hidden.
    final guestTabs = [
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
        icon: Icons.login_rounded,
        text: 'Login',
        textStyle: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    ];

    final fullTabs = [
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
    ];

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
          child: widget.isGuest
              ? GNav(
                  gap: 8,
                  activeColor: AppColors.primary,
                  iconSize: 22,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  duration: const Duration(milliseconds: 400),
                  tabBackgroundColor: AppColors.primaryLight,
                  color: AppColors.textLight,
                  tabs: guestTabs,
                  selectedIndex: 0,
                  onTabChange: (index) {
                    if (index == 1) {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const LoginPage(),
                        ),
                      );
                    }
                  },
                )
              : GNav(
                  gap: 8,
                  activeColor: AppColors.primary,
                  iconSize: 22,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  duration: const Duration(milliseconds: 400),
                  tabBackgroundColor: AppColors.primaryLight,
                  color: AppColors.textLight,
                  tabs: fullTabs,
                  selectedIndex: _selectedTab,
                  onTabChange: _selectTab,
                ),
        ),
      ),
    );
  }
}



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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warningLight,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.hourglass_top_rounded,
                      color: AppColors.warning,
                      size: 18,
                    ),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
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
