import 'package:flutter/material.dart';

import '../../constants/colors.dart';
import '../../models/intersection_point.dart';
import '../../services/intersection_service.dart';

class IntersectionsManagementPage extends StatefulWidget {
  const IntersectionsManagementPage({super.key});

  @override
  State<IntersectionsManagementPage> createState() =>
      _IntersectionsManagementPageState();
}

class _IntersectionsManagementPageState
    extends State<IntersectionsManagementPage> {
  final _service = IntersectionService();
  final _searchController = TextEditingController();
  final _updatingIds = <String>{};
  late Stream<List<IntersectionPoint>> _intersections;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _intersections = _service.watchIntersections();
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

  Future<void> _editIntersection([IntersectionPoint? intersection]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _IntersectionFormDialog(
        service: _service,
        intersection: intersection,
      ),
    );
    if (mounted && saved == true) {
      _showFeedback(
        intersection == null ? 'Intersection added.' : 'Intersection updated.',
      );
    }
  }

  Future<void> _setActive(IntersectionPoint intersection, bool active) async {
    if (_updatingIds.contains(intersection.id)) return;
    setState(() => _updatingIds.add(intersection.id));
    try {
      await _service.setActive(intersection.id, active);
      if (mounted) {
        _showFeedback(
          active ? 'Intersection enabled.' : 'Intersection disabled.',
        );
      }
    } catch (error) {
      if (mounted) {
        _showFeedback('Could not update intersection: $error', isError: true);
      }
    } finally {
      if (mounted) setState(() => _updatingIds.remove(intersection.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Manage intersections'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editIntersection(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add intersection'),
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
                  hintText: 'Search name, city or plus code',
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
              child: StreamBuilder<List<IntersectionPoint>>(
                stream: _intersections,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Could not load intersections: ${snapshot.error}',
                            ),
                            TextButton.icon(
                              onPressed: () => setState(() {
                                _intersections = _service.watchIntersections();
                              }),
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
                  final filtered = records.where((point) {
                    return point.name.toLowerCase().contains(_query) ||
                        point.city.toLowerCase().contains(_query) ||
                        point.plusCode.toLowerCase().contains(_query);
                  }).toList();
                  if (filtered.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          records.isEmpty
                              ? 'No intersections yet. Add an intersection to get started.'
                              : 'No intersections match your search.',
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
                      final point = filtered[index];
                      final updating = _updatingIds.contains(point.id);
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                point.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(point.city),
                              if (point.plusCode.isNotEmpty)
                                Text('Plus code: ${point.plusCode}'),
                              Text(
                                'Latitude: ${point.latitude}\n'
                                'Longitude: ${point.longitude}',
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${point.wayCount}-way / '
                                '${point.trafficLightCount} traffic lights',
                              ),
                              _IntersectionDiagram(intersection: point),
                              const Text(
                                'Directory configuration only; no live signal data.',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Semantics(
                                    label: 'Enable ${point.name}',
                                    child: Switch(
                                      value: point.isActive,
                                      onChanged: updating
                                          ? null
                                          : (value) => _setActive(point, value),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      point.isActive ? 'Enabled' : 'Disabled',
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
                                    tooltip: 'Edit intersection',
                                    onPressed: updating
                                        ? null
                                        : () => _editIntersection(point),
                                    icon: const Icon(Icons.edit_outlined),
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
}

class _IntersectionDiagram extends StatelessWidget {
  const _IntersectionDiagram({required this.intersection});

  final IntersectionPoint intersection;

  @override
  Widget build(BuildContext context) {
    final lights = intersection.lights;
    final directions = {
      for (final direction in IntersectionPoint.directions)
        direction: Tooltip(
          message: 'Light ID: ${lights[direction]!.id}',
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${direction[0].toUpperCase()}${direction.substring(1)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Icon(Icons.traffic, color: Colors.grey, size: 22),
                const Text(
                  'UNKNOWN',
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
    };

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              children: [
                const SizedBox.shrink(),
                directions['north']!,
                const SizedBox.shrink(),
              ],
            ),
            TableRow(
              children: [
                directions['west']!,
                const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_road, color: Colors.grey, size: 32),
                    Text(
                      'Intersection',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11),
                    ),
                  ],
                ),
                directions['east']!,
              ],
            ),
            TableRow(
              children: [
                const SizedBox.shrink(),
                directions['south']!,
                const SizedBox.shrink(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IntersectionFormDialog extends StatefulWidget {
  const _IntersectionFormDialog({required this.service, this.intersection});

  final IntersectionService service;
  final IntersectionPoint? intersection;

  @override
  State<_IntersectionFormDialog> createState() =>
      _IntersectionFormDialogState();
}

class _IntersectionFormDialogState extends State<_IntersectionFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _city;
  late final TextEditingController _plusCode;
  late final TextEditingController _latitude;
  late final TextEditingController _longitude;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final point = widget.intersection;
    _name = TextEditingController(text: point?.name ?? '');
    _city = TextEditingController(text: point?.city ?? '');
    _plusCode = TextEditingController(text: point?.plusCode ?? '');
    _latitude = TextEditingController(text: point?.latitude.toString() ?? '');
    _longitude = TextEditingController(text: point?.longitude.toString() ?? '');
  }

  @override
  void dispose() {
    for (final controller in [_name, _city, _plusCode, _latitude, _longitude]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _requiredText(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  String? _coordinate(String? value, double limit) {
    final number = double.tryParse(value?.trim() ?? '');
    if (number == null || !number.isFinite) return 'Enter a valid number';
    if (number < -limit || number > limit) {
      return 'Must be between -${limit.toInt()} and ${limit.toInt()}';
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.saveIntersection(
        id: widget.intersection?.id,
        name: _name.text.trim(),
        city: _city.text.trim(),
        latitude: double.parse(_latitude.text.trim()),
        longitude: double.parse(_longitude.text.trim()),
        plusCode: _plusCode.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save intersection: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(
          widget.intersection == null
              ? 'Add intersection'
              : 'Edit intersection',
        ),
        scrollable: true,
        content: SizedBox(
          width: 420,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'New intersections default to 4 ways and 4 traffic lights '
                  '(North, East, South and West). Controller mappings are '
                  'unconfigured; live signal states are unavailable.',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  enabled: !_saving,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: _requiredText,
                ),
                TextFormField(
                  controller: _city,
                  enabled: !_saving,
                  decoration: const InputDecoration(labelText: 'City'),
                  validator: _requiredText,
                ),
                TextFormField(
                  controller: _plusCode,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Plus code (optional)',
                  ),
                ),
                TextFormField(
                  controller: _latitude,
                  enabled: !_saving,
                  decoration: const InputDecoration(labelText: 'Latitude'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  validator: (value) => _coordinate(value, 90),
                ),
                TextFormField(
                  controller: _longitude,
                  enabled: !_saving,
                  decoration: const InputDecoration(labelText: 'Longitude'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  validator: (value) => _coordinate(value, 180),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
