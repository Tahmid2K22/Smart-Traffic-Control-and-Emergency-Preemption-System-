import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../constants/colors.dart';
import '../../services/hospital_service.dart';

class HospitalDashboardPage extends StatefulWidget {
  const HospitalDashboardPage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<HospitalDashboardPage> createState() => _HospitalDashboardPageState();
}

class _HospitalDashboardPageState extends State<HospitalDashboardPage> {
  final _service = HospitalService();
  final _address = TextEditingController();
  final _beds = TextEditingController();
  final _services = <String>{
    'Emergency',
    'ICU',
    'Surgery',
    'OPD',
    'Pharmacy',
    'Diagnostics',
  };
  final _specialties = <String>{
    'General Medicine',
    'Cardiology',
    'Neurology',
    'Orthopedics',
    'Pediatrics',
    'Gynecology',
  };
  String? _hospitalId;
  double? _latitude;
  double? _longitude;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadHospital();
  }

  Future<void> _loadHospital() async {
    try {
      final doc = await _service
          .getHospitalForUser(FirebaseAuth.instance.currentUser!.uid);
      final data = doc.data() ?? {};
      _hospitalId = doc.id;
      _address.text = data['address']?.toString() ?? '';
      _beds.text = '${(data['beds'] as num?)?.toInt() ?? 0}';
      _services
        ..clear()
        ..addAll(List<String>.from(data['services'] as List? ?? const []));
      _specialties
        ..clear()
        ..addAll(List<String>.from(data['diagnoses'] as List? ?? const []));
      _latitude = (data['lat'] as num?)?.toDouble();
      _longitude = (data['lon'] as num?)?.toDouble();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _message('Turn on location services and try again.');
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _message('Location permission is required to set the map location.');
      return;
    }
    final position = await Geolocator.getCurrentPosition();
    if (!mounted) return;
    setState(() {
      _latitude = position.latitude;
      _longitude = position.longitude;
    });
    _message('Current phone location selected. Save to publish it.');
  }

  Future<void> _save() async {
    final beds = int.tryParse(_beds.text.trim());
    if (_hospitalId == null || beds == null || beds < 0) {
      _message('Enter a valid number of beds.');
      return;
    }
    setState(() => _saving = true);
    try {
      await _service.updateHospitalProfile(
        hospitalId: _hospitalId!,
        address: _address.text,
        beds: beds,
        services: _services.toList(),
        specialties: _specialties.toList(),
        latitude: _latitude,
        longitude: _longitude,
      );
      _message('Hospital profile updated.');
    } catch (error) {
      _message('Could not update the profile: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override
  void dispose() {
    _address.dispose();
    _beds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: AppColors.primary)));
    }
    final name = widget.profile['name']?.toString() ?? 'Hospital';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(name),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _statusCard(name),
          const SizedBox(height: 18),
          _section('Hospital details'),
          TextField(
            controller: _address,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'Address',
                prefixIcon: Icon(Icons.location_on_rounded)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _beds,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Available beds',
                prefixIcon: Icon(Icons.bed_rounded)),
          ),
          const SizedBox(height: 18),
          _section('Services provided'),
          _chips(_services, const [
            'Emergency',
            'ICU',
            'Surgery',
            'OPD',
            'Pharmacy',
            'Diagnostics',
            'Laboratory',
            'Maternity',
          ]),
          const SizedBox(height: 18),
          _section('Specialties'),
          _chips(_specialties, const [
            'General Medicine',
            'Cardiology',
            'Neurology',
            'Orthopedics',
            'Pediatrics',
            'Gynecology',
            'Oncology',
            'Dermatology',
          ]),
          const SizedBox(height: 18),
          _section('Map location'),
          OutlinedButton.icon(
            onPressed: _useCurrentLocation,
            icon: const Icon(Icons.my_location_rounded),
            label: Text(_latitude == null
                ? 'Use current phone location'
                : 'Update using current phone location'),
          ),
          if (_latitude != null)
            Text('Location selected: ${_latitude!.toStringAsFixed(5)}, '
                '${_longitude!.toStringAsFixed(5)}'),
          const SizedBox(height: 20),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              child: _saving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Save hospital profile'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(String name) => Card(
        child: ListTile(
          leading: const CircleAvatar(
              backgroundColor: AppColors.primaryLight,
              child: Icon(Icons.verified_rounded, color: AppColors.primary)),
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(widget.profile['email']?.toString() ?? ''),
          trailing: const Chip(
              label: Text('Approved'),
              side: BorderSide.none,
              backgroundColor: Color(0xFFE7F7EE)),
        ),
      );

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(title,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textDark)),
      );

  Widget _chips(Set<String> selected, List<String> options) => Wrap(
        spacing: 8,
        runSpacing: 4,
        children: options
            .map((option) => FilterChip(
                  label: Text(option),
                  selected: selected.contains(option),
                  onSelected: (value) => setState(() {
                    if (value) {
                      selected.add(option);
                    } else {
                      selected.remove(option);
                    }
                  }),
                ))
            .toList(),
      );
}
