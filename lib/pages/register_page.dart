import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/colors.dart';
import '../constants/districts.dart';
import '../services/auth_service.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _licenseController = TextEditingController();
  final _vehicleNumberController = TextEditingController();
  final _imagePicker = ImagePicker();
  final _authService = AuthService();

  String _role = 'user';
  String? _selectedCity;
  String? _selectedVehicleType;
  XFile? _licenseImage;
  bool _licenseImageError = false;
  bool _isLoading = false;

  bool get _isDriver => _role == 'driver';

  Future<void> _register() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_isDriver && _licenseImage == null) {
      setState(() => _licenseImageError = true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _authService.register(
        name: _nameController.text,
        email: _emailController.text,
        phone: _phoneController.text,
        password: _passwordController.text,
        city: _selectedCity!,
        role: _role,
        drivingLicense: _licenseController.text,
        vehicleType: _selectedVehicleType,
        vehicleNumber: _vehicleNumberController.text,
        licenseImagePath: _licenseImage?.path,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isDriver
                ? 'Registration submitted for admin approval.'
                : 'Account created successfully.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pop(context);
    } on FirebaseAuthException catch (error) {
      _showError(error.message ?? 'Could not create your account.');
    } catch (error) {
      _showError('Could not save your profile. Please try again.');
      debugPrint('Registration error: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.primary),
    );
  }

  Future<void> _showImageSourceSheet() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: AppColors.primary),
              title: const Text('Take a Photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: AppColors.primary),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) return;
    try {
      final image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (mounted && image != null) {
        setState(() {
          _licenseImage = image;
          _licenseImageError = false;
        });
      }
    } catch (error) {
      _showError('Could not select the image. Please try again.');
      debugPrint('Image picker error: $error');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _licenseController.dispose();
    _vehicleNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textDark),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Column(
              children: [
                Icon(Icons.person_add_rounded, size: 80, color: AppColors.primary),
                const SizedBox(height: 24),
                Text(
                  'Create an Account',
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Join E-Ambulance today',
                  style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textLight),
                ),
                const SizedBox(height: 32),
                _buildRoleSwitcher(),
                const SizedBox(height: 24),
                _buildTextField(
                  controller: _nameController,
                  label: 'Full Name',
                  icon: Icons.person_rounded,
                  keyboardType: TextInputType.name,
                  validator: (value) => _required(value, 'Please enter your full name.'),
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _phoneController,
                  label: 'Phone Number',
                  icon: Icons.phone_rounded,
                  keyboardType: TextInputType.phone,
                  validator: (value) => _required(value, 'Please enter your phone number.'),
                ),
                const SizedBox(height: 16),
                _buildCityDropdown(),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _emailController,
                  label: 'Email Address',
                  icon: Icons.email_rounded,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (email.isEmpty) return 'Please enter your email address.';
                    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                      return 'Please enter a valid email address.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _passwordController,
                  label: 'Password',
                  icon: Icons.lock_rounded,
                  obscureText: true,
                  validator: (value) {
                    if ((value ?? '').length < 6) return 'Password must be at least 6 characters.';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _confirmPasswordController,
                  label: 'Confirm Password',
                  icon: Icons.lock_outline_rounded,
                  obscureText: true,
                  validator: (value) => value != _passwordController.text
                      ? 'Passwords do not match.'
                      : null,
                ),
                if (_isDriver) ...[
                  const SizedBox(height: 16),
                  _buildVehicleDropdown(),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _licenseController,
                    label: 'Driving License Number',
                    icon: Icons.badge_rounded,
                    validator: (value) => _required(value, 'Please enter your license number.'),
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _vehicleNumberController,
                    label: 'Vehicle Registration Number',
                    icon: Icons.directions_car_rounded,
                    validator: (value) => _required(value, 'Please enter your vehicle number.'),
                  ),
                  const SizedBox(height: 16),
                  _buildLicenseImagePicker(),
                ],
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _register,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text('Register', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _required(String? value, String message) =>
      value == null || value.trim().isEmpty ? message : null;

  Widget _buildRoleSwitcher() {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'user', label: Text('User'), icon: Icon(Icons.person_rounded)),
        ButtonSegment(value: 'driver', label: Text('Rider / Driver'), icon: Icon(Icons.drive_eta_rounded)),
      ],
      selected: {_role},
      onSelectionChanged: (selection) {
        setState(() => _role = selection.first);
        _formKey.currentState?.reset();
      },
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(AppColors.primary),
        side: WidgetStatePropertyAll(BorderSide(color: AppColors.primary.withValues(alpha: 0.35))),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String? Function(String?) validator,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      decoration: _inputDecoration(label, icon),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.primary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.textLight.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
      );

  Widget _buildCityDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedCity,
      hint: const Text('Select City (District)'),
      items: bdDistricts.map((district) => DropdownMenuItem(value: district, child: Text(district))).toList(),
      onChanged: (value) => setState(() => _selectedCity = value),
      validator: (value) => value == null ? 'Please select your city (district).' : null,
      decoration: _inputDecoration('City', Icons.location_city_rounded),
    );
  }

  Widget _buildVehicleDropdown() {
    const vehicleTypes = ['Bike', 'Car', 'CNG', 'Ambulance'];
    return DropdownButtonFormField<String>(
      initialValue: _selectedVehicleType,
      hint: const Text('Select Vehicle Type'),
      items: vehicleTypes.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
      onChanged: (value) => setState(() => _selectedVehicleType = value),
      validator: (value) => value == null ? 'Please select your vehicle type.' : null,
      decoration: _inputDecoration('Vehicle Type', Icons.two_wheeler_rounded),
    );
  }

  Widget _buildLicenseImagePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _showImageSourceSheet,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 150,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _licenseImageError ? AppColors.primary : AppColors.textLight.withValues(alpha: 0.3),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: _licenseImage == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo_rounded, size: 34, color: AppColors.primary),
                      const SizedBox(height: 8),
                      Text('Upload Driving License / NID Photo', style: GoogleFonts.poppins(color: AppColors.textGrey)),
                    ],
                  )
                : FutureBuilder(
                    future: _licenseImage!.readAsBytes(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      return Image.memory(snapshot.data!, fit: BoxFit.cover);
                    },
                  ),
          ),
        ),
        if (_licenseImageError)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 8),
            child: Text(
              'Please upload your driving license or NID photo.',
              style: TextStyle(color: AppColors.primary, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
