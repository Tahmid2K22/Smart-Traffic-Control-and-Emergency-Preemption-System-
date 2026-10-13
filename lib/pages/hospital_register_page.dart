import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../constants/colors.dart';
import '../constants/districts.dart';
import '../services/hospital_service.dart';

class HospitalRegisterPage extends StatefulWidget {
  const HospitalRegisterPage({super.key});

  @override
  State<HospitalRegisterPage> createState() => _HospitalRegisterPageState();
}

class _HospitalRegisterPageState extends State<HospitalRegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _latController = TextEditingController();
  final _lonController = TextEditingController();
  final _bedsController = TextEditingController();
  final _service = HospitalService();

  String? _selectedCity;
  bool _isLoading = false;

  // ── Multi-chip pickers ─────────────────────────────────────────────────────

  final List<String> _allServices = [
    'Emergency',
    'ICU',
    'Surgery',
    'OPD',
    'Cardiology',
    'Maternity',
    'Neonatal ICU',
    'Burn Unit',
    'Diagnostics',
    'Laboratory',
    'Imaging',
    'Pharmacy',
    'Physiotherapy',
    'Dialysis',
  ];

  final List<String> _allDiagnoses = [
    'General Medicine',
    'Cardiology',
    'Neurology',
    'Orthopedics',
    'Gynecology',
    'Pediatrics',
    'Oncology',
    'Dermatology',
    'Ophthalmology',
    'Dentistry',
    'Psychiatry',
    'Pathology',
    'Radiology',
    'Neonatology',
    'Obstetrics',
    'Urology',
  ];

  final Set<String> _selectedServices = {};
  final Set<String> _selectedDiagnoses = {};

  // ── Helpers ────────────────────────────────────────────────────────────────

  String? _required(String? v, String msg) =>
      (v == null || v.trim().isEmpty) ? msg : null;

  String? _validateDouble(String? v, String label) {
    if (v == null || v.trim().isEmpty) return 'Please enter $label.';
    if (double.tryParse(v.trim()) == null) return '$label must be a number.';
    return null;
  }

  String? _validateInt(String? v) {
    if (v == null || v.trim().isEmpty) return 'Please enter number of beds.';
    final n = int.tryParse(v.trim());
    if (n == null || n <= 0) return 'Beds must be a positive number.';
    return null;
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedServices.isEmpty) {
      _showMessage('Please select at least one service.');
      return;
    }
    if (_selectedDiagnoses.isEmpty) {
      _showMessage('Please select at least one diagnosis / specialty.');
      return;
    }

    // Must be logged in
    if (FirebaseAuth.instance.currentUser == null) {
      _showMessage('You must be logged in to register a hospital.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _service.registerHospital(
        name: _nameController.text.trim(),
        city: _selectedCity!,
        lat: double.parse(_latController.text.trim()),
        lon: double.parse(_lonController.text.trim()),
        beds: int.parse(_bedsController.text.trim()),
        services: _selectedServices.toList(),
        diagnoses: _selectedDiagnoses.toList(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Hospital registration submitted! Awaiting admin approval.'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) _showMessage('Registration failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _nameController.dispose();
    _latController.dispose();
    _lonController.dispose();
    _bedsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textDark),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Center(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.local_hospital_rounded,
                          size: 48,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Register a Hospital',
                        style: GoogleFonts.poppins(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Submit for admin review and approval',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: AppColors.textLight,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Section: Basic Info
                _sectionLabel('Basic Information'),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _nameController,
                  label: 'Hospital Name',
                  icon: Icons.business_rounded,
                  validator: (v) =>
                      _required(v, 'Please enter the hospital name.'),
                ),
                const SizedBox(height: 14),
                _buildCityDropdown(),
                const SizedBox(height: 14),
                _buildTextField(
                  controller: _bedsController,
                  label: 'Number of Beds',
                  icon: Icons.bed_rounded,
                  keyboardType: TextInputType.number,
                  validator: _validateInt,
                ),

                // Section: Location
                const SizedBox(height: 24),
                _sectionLabel('GPS Coordinates'),
                const SizedBox(height: 6),
                Text(
                  'Find coordinates at maps.google.com → right-click → copy lat/lon',
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: AppColors.textLight),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _latController,
                        label: 'Latitude',
                        icon: Icons.location_on_rounded,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        validator: (v) => _validateDouble(v, 'Latitude'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTextField(
                        controller: _lonController,
                        label: 'Longitude',
                        icon: Icons.explore_rounded,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        validator: (v) => _validateDouble(v, 'Longitude'),
                      ),
                    ),
                  ],
                ),

                // Section: Services
                const SizedBox(height: 24),
                _sectionLabel('Services Provided'),
                const SizedBox(height: 4),
                Text(
                  'Select all services this hospital offers.',
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: AppColors.textLight),
                ),
                const SizedBox(height: 10),
                _buildChipPicker(
                  options: _allServices,
                  selected: _selectedServices,
                  activeColor: AppColors.primary,
                ),

                // Section: Diagnoses
                const SizedBox(height: 24),
                _sectionLabel('Specialties / Diagnoses'),
                const SizedBox(height: 4),
                Text(
                  'Select all medical specialties available.',
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: AppColors.textLight),
                ),
                const SizedBox(height: 10),
                _buildChipPicker(
                  options: _allDiagnoses,
                  selected: _selectedDiagnoses,
                  activeColor: const Color(0xFF1565C0),
                ),

                // Submit
                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _submit,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded),
                    label: Text(
                      _isLoading ? 'Submitting...' : 'Submit for Approval',
                      style: GoogleFonts.poppins(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
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

  // ── Widget helpers ─────────────────────────────────────────────────────────

  Widget _sectionLabel(String label) => Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.textDark,
        ),
      );

  InputDecoration _inputDecoration(String label, IconData icon) =>
      InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.primary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: AppColors.textLight.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      );

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

  Widget _buildCityDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedCity,
      hint: const Text('Select City (District)'),
      items: bdDistricts
          .map((d) => DropdownMenuItem(value: d, child: Text(d)))
          .toList(),
      onChanged: (v) => setState(() => _selectedCity = v),
      validator: (v) =>
          v == null ? 'Please select the hospital city.' : null,
      decoration: _inputDecoration('City', Icons.location_city_rounded),
    );
  }

  Widget _buildChipPicker({
    required List<String> options,
    required Set<String> selected,
    required Color activeColor,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final isSelected = selected.contains(opt);
        return GestureDetector(
          onTap: () => setState(() {
            if (isSelected) {
              selected.remove(opt);
            } else {
              selected.add(opt);
            }
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? activeColor.withValues(alpha: 0.12)
                  : AppColors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isSelected ? activeColor : AppColors.cardBorder,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Text(
              opt,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? activeColor : AppColors.textGrey,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
