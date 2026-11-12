import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/colors.dart';
import '../services/hospital_service.dart';

class HospitalRegisterPage extends StatefulWidget {
  const HospitalRegisterPage({super.key});

  @override
  State<HospitalRegisterPage> createState() => _HospitalRegisterPageState();
}

class _HospitalRegisterPageState extends State<HospitalRegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _password = TextEditingController();
  final _service = HospitalService();
  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    for (final controller in [_name, _email, _phone, _address, _password]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _required(String? value, String label) =>
      value == null || value.trim().isEmpty ? 'Enter $label.' : null;

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    try {
      await _service.registerHospitalAccount(
        name: _name.text,
        email: _email.text,
        phone: _phone.text,
        password: _password.text,
        address: _address.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Registration submitted. Wait for admin approval.'),
        backgroundColor: AppColors.success,
      ));
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Registration failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Register Hospital'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textDark,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            const Icon(Icons.local_hospital_rounded,
                size: 64, color: AppColors.primary),
            const SizedBox(height: 12),
            Text('Create your hospital account',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark)),
            const SizedBox(height: 8),
            Text(
              'Only basic contact information is needed now. Services, specialties, beds, and map location can be added after approval.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: AppColors.textGrey),
            ),
            const SizedBox(height: 28),
            _field(_name, 'Hospital name', Icons.business_rounded,
                validator: (value) => _required(value, 'hospital name')),
            _field(_email, 'Email address', Icons.email_rounded,
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (_required(value, 'email address') != null) {
                    return _required(value, 'email address');
                  }
                  return value!.contains('@') ? null : 'Enter a valid email.';
                }),
            _field(_phone, 'Phone number', Icons.phone_rounded,
                keyboardType: TextInputType.phone,
                validator: (value) => _required(value, 'phone number')),
            _field(_address, 'Hospital address', Icons.location_on_rounded,
                maxLines: 2,
                validator: (value) => _required(value, 'hospital address')),
            _field(_password, 'Account password', Icons.lock_rounded,
                obscureText: _obscurePassword,
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(_obscurePassword
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded),
                ),
                validator: (value) => value == null || value.length < 6
                    ? 'Password must be at least 6 characters.'
                    : null),
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Submit for admin approval'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    int maxLines = 1,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        maxLines: obscureText ? 1 : maxLines,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: AppColors.primary),
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
        ),
      ),
    );
  }
}
