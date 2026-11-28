import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';

import '../../constants/colors.dart';
import '../../models/emergency_service_location.dart';
import '../../services/emergency_service_directory_service.dart';
import 'emergency_service_location_picker_page.dart';

class EmergencyServicesManagementPage extends StatefulWidget {
  const EmergencyServicesManagementPage({super.key});

  @override
  State<EmergencyServicesManagementPage> createState() =>
      _EmergencyServicesManagementPageState();
}

class _EmergencyServicesManagementPageState
    extends State<EmergencyServicesManagementPage> {
  final _directory = EmergencyServiceDirectoryService();
  final _searchController = TextEditingController();
  final _updatingIds = <String>{};
  late Stream<List<EmergencyServiceLocation>> _services;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _services = _directory.watchAll();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showFeedback(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : AppColors.success,
      ),
    );
  }

  Future<void> _editService([EmergencyServiceLocation? service]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _EmergencyServiceFormDialog(directory: _directory, service: service),
    );
    if (mounted && saved == true) {
      _showFeedback(
        service == null ? '999 service added.' : '999 service updated.',
      );
    }
  }

  Future<void> _setActive(
    EmergencyServiceLocation service,
    bool isActive,
  ) async {
    if (_updatingIds.contains(service.id)) return;
    setState(() => _updatingIds.add(service.id));
    try {
      await _directory.setActive(service.id, isActive);
      if (mounted) {
        _showFeedback(isActive ? 'Service enabled.' : 'Service disabled.');
      }
    } catch (error) {
      if (mounted) {
        _showFeedback('Could not update service: $error', isError: true);
      }
    } finally {
      if (mounted) setState(() => _updatingIds.remove(service.id));
    }
  }

  Future<void> _delete(EmergencyServiceLocation service) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete 999 service?'),
        content: Text('Delete ${service.name} from the directory?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _directory.delete(service.id);
      if (mounted) _showFeedback('999 service deleted.');
    } catch (error) {
      if (mounted) {
        _showFeedback('Could not delete service: $error', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      title: const Text('Manage 999 services'),
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _editService(),
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.add),
      label: const Text('Add service'),
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search name, type or address',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<EmergencyServiceLocation>>(
              stream: _services,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Could not load 999 services: ${snapshot.error}',
                          ),
                          TextButton.icon(
                            onPressed: () => setState(
                              () => _services = _directory.watchAll(),
                            ),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final records = snapshot.data!;
                final filtered = records.where((service) {
                  final query = _query;
                  return service.name.toLowerCase().contains(query) ||
                      service.category.label.toLowerCase().contains(query) ||
                      service.address.toLowerCase().contains(query);
                }).toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        records.isEmpty
                            ? 'No 999 services yet. Add police stations, fire services or other emergency facilities.'
                            : 'No services match your search.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final service = filtered[index];
                    final updating = _updatingIds.contains(service.id);
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              service.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(service.category.label),
                            Text(service.address),
                            if (service.phone.isNotEmpty)
                              Text('Phone: ${service.phone}'),
                            if (service.description.isNotEmpty)
                              Text(service.description),
                            Text(
                              'Location: ${service.latitude}, ${service.longitude}',
                              style: const TextStyle(
                                color: AppColors.textGrey,
                                fontSize: 12,
                              ),
                            ),
                            Row(
                              children: [
                                Switch(
                                  value: service.isActive,
                                  onChanged: updating
                                      ? null
                                      : (value) => _setActive(service, value),
                                ),
                                Expanded(
                                  child: Text(
                                    service.isActive
                                        ? 'Visible to users'
                                        : 'Hidden from users',
                                  ),
                                ),
                                if (updating)
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                IconButton(
                                  tooltip: 'Edit service',
                                  onPressed: updating
                                      ? null
                                      : () => _editService(service),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Delete service',
                                  onPressed: updating
                                      ? null
                                      : () => _delete(service),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _EmergencyServiceFormDialog extends StatefulWidget {
  const _EmergencyServiceFormDialog({
    required this.directory,
    required this.service,
  });

  final EmergencyServiceDirectoryService directory;
  final EmergencyServiceLocation? service;

  @override
  State<_EmergencyServiceFormDialog> createState() =>
      _EmergencyServiceFormDialogState();
}

class _EmergencyServiceFormDialogState
    extends State<_EmergencyServiceFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _phoneController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _latitudeController;
  late final TextEditingController _longitudeController;
  late EmergencyServiceCategory _category;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final service = widget.service;
    _category = service?.category ?? EmergencyServiceCategory.policeStation;
    _nameController = TextEditingController(text: service?.name ?? '');
    _addressController = TextEditingController(text: service?.address ?? '');
    _phoneController = TextEditingController(text: service?.phone ?? '');
    _descriptionController = TextEditingController(
      text: service?.description ?? '',
    );
    _latitudeController = TextEditingController(
      text: service?.latitude.toString() ?? '',
    );
    _longitudeController = TextEditingController(
      text: service?.longitude.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _descriptionController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  Future<(double, double)> _coordinates() async {
    final latitudeText = _latitudeController.text.trim();
    final longitudeText = _longitudeController.text.trim();
    if (latitudeText.isNotEmpty || longitudeText.isNotEmpty) {
      final latitude = double.tryParse(latitudeText);
      final longitude = double.tryParse(longitudeText);
      if (latitude == null || longitude == null) {
        throw const FormatException(
          'Enter both latitude and longitude, or leave both blank to use the address.',
        );
      }
      return (latitude, longitude);
    }

    final locations = await Geocoding().locationFromAddress(
      '${_addressController.text.trim()}, Bangladesh',
    );
    if (locations.isEmpty) {
      throw const FormatException(
        'Could not locate this address. Enter latitude and longitude manually.',
      );
    }
    return (locations.first.latitude, locations.first.longitude);
  }

  Future<void> _pickLocationOnMap() async {
    final latitude = double.tryParse(_latitudeController.text.trim());
    final longitude = double.tryParse(_longitudeController.text.trim());
    final selection = await Navigator.of(context)
        .push<EmergencyServiceMapSelection>(
          MaterialPageRoute<EmergencyServiceMapSelection>(
            builder: (_) => EmergencyServiceLocationPickerPage(
              initialLatitude: latitude,
              initialLongitude: longitude,
              initialAddress: _addressController.text.trim(),
            ),
          ),
        );
    if (!mounted || selection == null) return;
    setState(() {
      _latitudeController.text = selection.location.latitude.toString();
      _longitudeController.text = selection.location.longitude.toString();
      final address = selection.address?.trim();
      if (address != null && address.isNotEmpty) {
        _addressController.text = address;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final (latitude, longitude) = await _coordinates();
      await widget.directory.save(
        id: widget.service?.id,
        category: _category,
        name: _nameController.text,
        address: _addressController.text,
        latitude: latitude,
        longitude: longitude,
        phone: _phoneController.text,
        description: _descriptionController.text,
        isActive: widget.service?.isActive ?? true,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not save service: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.service == null ? 'Add 999 service' : 'Edit 999 service',
    ),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<EmergencyServiceCategory>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Service type'),
                items: EmergencyServiceCategory.values
                    .map(
                      (category) => DropdownMenuItem(
                        value: category,
                        child: Text(category.label),
                      ),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (category) {
                        if (category != null) {
                          setState(() => _category = category);
                        }
                      },
              ),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Station/service name',
                ),
                textCapitalization: TextCapitalization.words,
                validator: _required,
              ),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: 'Address'),
                textCapitalization: TextCapitalization.words,
                validator: _required,
              ),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Phone number'),
                keyboardType: TextInputType.phone,
              ),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Additional information',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _latitudeController,
                      decoration: const InputDecoration(labelText: 'Latitude'),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _longitudeController,
                      decoration: const InputDecoration(labelText: 'Longitude'),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _saving ? null : _pickLocationOnMap,
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Search and add from map'),
                ),
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Leave coordinates blank to find them from the address.',
                    style: TextStyle(fontSize: 12, color: AppColors.textGrey),
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Save'),
      ),
    ],
  );
}
