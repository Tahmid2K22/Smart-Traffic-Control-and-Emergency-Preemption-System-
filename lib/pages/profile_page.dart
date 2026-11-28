import 'package:flutter/material.dart';
import 'package:velocity_x/velocity_x.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/colors.dart';
import '../constants/districts.dart';
import '../services/user_service.dart';

import 'hospital_register_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {

  // Raw values; placeholders ('No Name', ...) are display-only, never cached
  // in prefs or written to the database.
  String _name = '';
  String _email = '';
  String _phone = '';
  String? _city;
  bool _loaded = false;

  static const Set<String> _placeholderValues = {
    'Loading...',
    'No Name',
    'No Email',
    'No Phone',
    'User',
  };

  String get _displayName =>
      _name.isNotEmpty ? _name : (_loaded ? 'No Name' : 'Loading...');

  String get _displayEmail =>
      _email.isNotEmpty ? _email : (_loaded ? 'No Email' : 'Loading...');

  String get _displayPhone =>
      _phone.isNotEmpty ? _phone : (_loaded ? 'No Phone' : 'Loading...');


  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: _name);
    _emailCtrl = TextEditingController(text: _email);
    _phoneCtrl = TextEditingController(text: _phone);
    _loadUserData();
  }

  /// Reads a cached pref, treating legacy placeholder junk ('No Name', etc.)
  /// as empty so it never pre-fills the edit form or reaches the database.
  String _cached(SharedPreferences prefs, String key) {
    final value = prefs.getString(key)?.trim() ?? '';
    return _placeholderValues.contains(value) ? '' : value;
  }

  Future<void> _cache(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;

    // Auth email is the sign-in source of truth; prefs only cover signed-out
    // or pre-fetch states.
    var name = _cached(prefs, 'userName');
    var email = user?.email?.trim() ?? _cached(prefs, 'userEmail');
    var phone = _cached(prefs, 'userPhone');
    var city = prefs.getString('userCity')?.trim();

    if (user != null) {
      try {
        final profile = await UserService.instance.fetch(user.uid);
        if (profile != null) {
          if (profile.name.trim().isNotEmpty) {
            name = profile.name.trim();
          } else if (profile.fullName.trim().isNotEmpty) {
            name = profile.fullName.trim();
          } else if (name.isEmpty) {
            name = user.displayName?.trim() ?? '';
          }
          if (email.isEmpty && profile.email.trim().isNotEmpty) {
            email = profile.email.trim();
          }
          if (profile.phone.trim().isNotEmpty) phone = profile.phone.trim();
          final cityFromProfile = profile.city?.trim() ?? '';
          if (cityFromProfile.isNotEmpty) city = cityFromProfile;
        } else if (name.isEmpty) {
          name = user.displayName?.trim() ?? '';
        }
      } catch (error) {
        debugPrint('Failed to fetch profile: $error');
      }
    }

    // Cache only real values so placeholders never come back from prefs.
    await _cache('userName', name);
    await _cache('userEmail', email);
    await _cache('userPhone', phone);

    if (!mounted) return;
    setState(() {
      _name = name;
      _email = email;
      _phone = phone;
      _city = city?.isNotEmpty == true ? city : null;
      _loaded = true;
      _nameCtrl.text = _name;
      _emailCtrl.text = _email;
      _phoneCtrl.text = _phone;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              _buildProfileCard(),
              24.heightBox,
              _buildInfoSection(),
              24.heightBox,
              _buildActionButtons(context),
              32.heightBox,
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Account',
            style: GoogleFonts.poppins(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          Text(
            'Manage your profile information',
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppColors.textGrey,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildProfileCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [

            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.25),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.6),
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(
                  _initials(_displayName),
                  style: GoogleFonts.poppins(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            16.widthBox,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayName,
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  4.heightBox,
                  Text(
                    _displayEmail,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildInfoSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Personal Information',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          16.heightBox,
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                _infoRow(
                  icon: Icons.person_outline_rounded,
                  label: 'Full Name',
                  value: _displayName,
                  isFirst: true,
                ),
                _divider(),
                _infoRow(
                  icon: Icons.phone_outlined,
                  label: 'Phone Number',
                  value: _displayPhone,
                ),
                _divider(),
                _infoRow(
                  icon: Icons.email_outlined,
                  label: 'Email Address',
                  value: _displayEmail,
                ),
                _divider(),
                _infoRow(
                  icon: Icons.location_city_outlined,
                  label: 'City',
                  value: _city ?? 'Not set',
                  isLast: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, isFirst ? 16 : 12, 16, isLast ? 16 : 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          12.widthBox,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: AppColors.textLight,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                2.heightBox,
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 16),
    child: Divider(height: 1, color: Color(0xFFEFEFEF)),
  );


  Widget _buildActionButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () => _showUpdateDialog(context),
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: Text(
                'Update Profile',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
          16.heightBox,
          
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const HospitalRegisterPage(),
                ),
              ),
              icon: const Icon(Icons.local_hospital_rounded, size: 18),
              label: Text(
                'Request for registering a hospital',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          16.heightBox,
          
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () => _showLogoutDialog(context),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: Text(
                'Logout',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  void _showUpdateDialog(BuildContext context) {

    // Prefill raw values; placeholders are display-only.
    _nameCtrl.text = _name;
    _emailCtrl.text = _email;
    _phoneCtrl.text = _phone;
    String? tempCity = _city;
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext bottomSheetContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.cardBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  20.heightBox,
                  Text(
                    'Update Profile',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  4.heightBox,
                  Text(
                    'Edit your personal information below',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: AppColors.textGrey,
                    ),
                  ),
                  20.heightBox,
                  _editField(
                    controller: _nameCtrl,
                    label: 'Full Name',
                    icon: Icons.person_outline_rounded,
                  ),
                  12.heightBox,
                  _editField(
                    controller: _phoneCtrl,
                    label: 'Phone Number',
                    icon: Icons.phone_outlined,
                    inputType: TextInputType.phone,
                  ),
                  12.heightBox,
                  _editField(
                    controller: _emailCtrl,
                    label: 'Email Address',
                    icon: Icons.email_outlined,
                    inputType: TextInputType.emailAddress,
                  ),
                  12.heightBox,
                  DropdownButtonFormField<String>(
                    initialValue: tempCity ?? '',
                    hint: Text(
                      'Select City (District)',
                      style: GoogleFonts.poppins(fontSize: 13),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text('Not set'),
                      ),
                      ...bdDistricts.map((String district) {
                        return DropdownMenuItem<String>(
                          value: district,
                          child: Text(
                            district,
                            style: GoogleFonts.poppins(fontSize: 14),
                          ),
                        );
                      }),
                    ],
                    onChanged: (String? newValue) {
                      setModalState(() {
                        tempCity =
                            newValue == null || newValue.isEmpty
                            ? null
                            : newValue;
                      });
                    },
                    decoration: InputDecoration(
                      labelText: 'City',
                      prefixIcon: const Icon(
                        Icons.location_city_outlined,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppColors.textLight.withValues(alpha: 0.2),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppColors.textLight.withValues(alpha: 0.2),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  24.heightBox,
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: saving
                        ? null
                        : () async {
                            if (saving) return;
                            saving = true;
                            setModalState(() {});

                            final nav = Navigator.of(context);
                            final messenger = ScaffoldMessenger.of(context);
                            final sheetRoute = ModalRoute.of(context);

                            final result = await _saveProfile(
                              tempCity: tempCity,
                            );

                            if (result.error != null) {
                              saving = false;
                              // The sheet may have been dismissed while
                              // saving; only touch it if it is still around.
                              if (sheetRoute?.isActive ?? false) {
                                setModalState(() {});
                              }
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    result.error!,
                                    style: GoogleFonts.poppins(fontSize: 13),
                                  ),
                                  backgroundColor: AppColors.warning,
                                ),
                              );
                              return;
                            }

                            // Close the sheet only if the user didn't
                            // dismiss it while the save was running.
                            if (sheetRoute?.isActive ?? false) {
                              nav.pop();
                            }
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  result.emailVerificationSent
                                      ? 'Profile saved. Check your new email '
                                          'inbox to confirm the address '
                                          'change.'
                                      : 'Profile updated successfully!',
                                  style: GoogleFonts.poppins(fontSize: 13),
                                ),
                                backgroundColor: const Color(0xFF2E7D32),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            );
                          },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Save Changes',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Validates the form, pushes the changes to the backends, and only then
  /// commits to local state and prefs. Returns an error message on failure;
  /// [result.error] null means success.
  Future<({String? error, bool emailVerificationSent})> _saveProfile({
    required String? tempCity,
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    final newName = _nameCtrl.text.trim();
    final newPhone = _phoneCtrl.text.trim();
    final newEmail = _emailCtrl.text.trim();
    final newCity = tempCity == null || tempCity.isEmpty ? null : tempCity;

    // Blank fields keep their current value.
    final name = newName.isEmpty ? _name : newName;
    final phone = newPhone.isEmpty ? _phone : newPhone;
    final email = newEmail.isEmpty ? _email : newEmail;

    if (phone.isNotEmpty) {
      final digits = phone.replaceAll(RegExp(r'\D'), '');
      if (digits.length < 6 || digits.length > 15) {
        return (
          error: 'Please enter a valid phone number.',
          emailVerificationSent: false,
        );
      }
    }

    final emailChanged =
        user != null && email.isNotEmpty && email != (user.email?.trim() ?? '');
    if (emailChanged &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return (
        error: 'Please enter a valid email address.',
        emailVerificationSent: false,
      );
    }

    bool emailVerificationSent = false;
    if (user != null) {
      // Auth owns the sign-in email, so confirm the new address first. The
      // Auth email only changes after the user clicks the verification link,
      // which is why local state keeps showing the current address.
      if (emailChanged) {
        try {
          await user.verifyBeforeUpdateEmail(email);
          emailVerificationSent = true;
        } on FirebaseAuthException catch (e) {
          debugPrint('Failed to start email change: $e');
          return (
            error: e.message ?? 'Could not update the email address.',
            emailVerificationSent: false,
          );
        } catch (e) {
          debugPrint('Failed to start email change: $e');
          return (
            error: 'Could not update the email address.',
            emailVerificationSent: false,
          );
        }
      }

      try {
        await UserService.instance.update(user.uid, {
          if (name.isNotEmpty) 'name': name,
          if (phone.isNotEmpty) 'phone': phone,
          'city': newCity,
        });
      } catch (e) {
        debugPrint('Failed to update profile: $e');
        return (
          error: 'Could not save profile to the database.',
          emailVerificationSent: false,
        );
      }

      // Best-effort; a stale Auth display name is cosmetic.
      if (name.isNotEmpty) {
        try {
          await user.updateDisplayName(name);
        } catch (e) {
          debugPrint('Failed to update display name: $e');
        }
      }
    }

    // Remote writes succeeded; commit locally.
    await _cache('userName', name);
    await _cache('userEmail', email);
    await _cache('userPhone', phone);
    await _cache('userCity', newCity ?? '');

    if (mounted) {
      setState(() {
        _name = name;
        _email = email;
        _phone = phone;
        _city = newCity;
        _loaded = true;
      });
    }
    return (error: null, emailVerificationSent: emailVerificationSent);
  }

  Widget _editField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType inputType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: inputType,
      style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textDark),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(
          fontSize: 13,
          color: AppColors.textGrey,
        ),
        prefixIcon: Icon(icon, size: 20, color: AppColors.primary),
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }

  // logout dialog
  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.logout_rounded,
                color: AppColors.primary,
                size: 32,
              ),
            ),
            20.heightBox,
            Text(
              'Logout',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            8.heightBox,
            Text(
              'Are you sure you want to log out of your account?',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: AppColors.textGrey,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textGrey,
                    side: const BorderSide(color: AppColors.cardBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              12.widthBox,
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    navigator.pop();
                    try {
                      await FirebaseAuth.instance.signOut();
                    } catch (e) {
                      debugPrint('Failed to sign out: $e');
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Could not log out. Please try again.'),
                          backgroundColor: AppColors.warning,
                        ),
                      );
                      return;
                    }
                    // Only drop the cached user data once sign-out succeeded.
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.clear();
                    // Back to public home.
                    if (navigator.mounted) {
                      navigator.popUntil((route) => route.isFirst);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    'Logout',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // get initials
  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    final word = parts.first;
    return word.substring(0, word.length >= 2 ? 2 : 1).toUpperCase();
  }
}
