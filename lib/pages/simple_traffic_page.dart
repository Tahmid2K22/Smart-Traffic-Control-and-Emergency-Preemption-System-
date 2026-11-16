import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/intersection_point.dart';
import '../services/traffic_rtdb_service.dart';

/// Traffic-light control over Firebase Realtime Database.
///
/// The officer picks the intersection to control (their assigned one is the
/// default), sees it on an OpenStreetMap tile and can preempt any direction's
/// colour. The board is ALWAYS in AUTO mode (boots straight into the cycle);
/// one small write per tap, no polling.
class SimpleTrafficPage extends StatefulWidget {
  const SimpleTrafficPage({super.key, this.assignedIntersection});

  /// The officer's assigned intersection (name or id), used as the default.
  final String? assignedIntersection;

  @override
  State<SimpleTrafficPage> createState() => _SimpleTrafficPageState();
}

class _SimpleTrafficPageState extends State<SimpleTrafficPage> {
  static final _greenCtrl = TextEditingController(text: '30');
  static final _yellowCtrl = TextEditingController(text: '3');
  static final _redCtrl = TextEditingController(text: '2');

  late IntersectionPoint _selected;
  late TrafficRtdbService _service;
  StreamSubscription<TrafficRtdbState>? _sub;
  TrafficRtdbState _state = const TrafficRtdbState(
    mode: 'unknown',
    phase: 'unknown',
    lights: {},
    updated: null,
  );
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _selected = _resolveAssigned();
    _service = TrafficRtdbService(intersectionId: _selected.id);
    _subscribe();
  }

  IntersectionPoint _resolveAssigned() {
    final name = widget.assignedIntersection?.trim().toLowerCase();
    if (name != null && name.isNotEmpty) {
      for (final point in IntersectionPoint.khulnaIntersections) {
        if (point.name.toLowerCase() == name || point.id == name) return point;
      }
    }
    // Default: the intersection with the live controller.
    return IntersectionPoint.royal;
  }

  void _subscribe() {
    unawaited(_sub?.cancel());
    _sub = _service.statusStream.listen((state) {
      if (mounted) setState(() => _state = state);
    }, onError: (Object error) {
      if (mounted) _notice('Status stream error: $error');
    });
  }

  Future<void> _chooseIntersection(IntersectionPoint point) async {
    if (point.id == _selected.id) return;
    setState(() {
      _selected = point;
      _state = const TrafficRtdbState(
        mode: 'unknown',
        phase: 'unknown',
        lights: {},
        updated: null,
      );
    });
    _service = TrafficRtdbService(intersectionId: point.id);
    _subscribe();
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Parses a duration field; returns null (and shows an error) if invalid.
  int? _duration(TextEditingController ctrl, String label) {
    final value = int.tryParse(ctrl.text.trim());
    if (value == null || value < 1) {
      _notice('$label must be a positive number of seconds');
      return null;
    }
    return value;
  }

  Future<void> _startAuto() async {
    final green = _duration(_greenCtrl, 'Green time');
    final yellow = _duration(_yellowCtrl, 'Yellow time');
    final red = _duration(_redCtrl, 'Red time');
    if (green == null || yellow == null || red == null) return;
    await _send(
      () => _service.auto(
        greenSec: green,
        yellowSec: yellow,
        allRedSec: red,
      ),
      'AUTO (green ${green}s / yellow ${yellow}s / red ${red}s)',
    );
  }

  Future<void> _send(Future<void> Function() action, String label) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await action();
      _notice('$label sent');
    } catch (error) {
      _notice('Failed to send $label: $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = _state.isFresh;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Signal control'),
        actions: [
          IconButton(
            tooltip: 'Log Out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Intersection picker (assigned intersection is the default).
          DropdownButtonFormField<IntersectionPoint>(
            initialValue: _selected,
            decoration: const InputDecoration(
              labelText: 'Intersection',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
            items: [
              for (final point in IntersectionPoint.khulnaIntersections)
                DropdownMenuItem(
                  value: point,
                  child: Text('${point.name} · ${point.city}'),
                ),
            ],
            onChanged: (point) => point == null ? null : _chooseIntersection(point),
          ),
          const SizedBox(height: 12),

          // OpenStreetMap view of the controlled intersection.
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 200,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter:
                      LatLng(_selected.latitude, _selected.longitude),
                  initialZoom: 16,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.e_ambulance',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point:
                            LatLng(_selected.latitude, _selected.longitude),
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.traffic_rounded,
                            color: Colors.red, size: 36),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Connection header.
          Row(
            children: [
              Icon(
                online ? Icons.cloud_done : Icons.cloud_off,
                color: online ? Colors.green : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  online
                      ? 'Controller online'
                      : 'Waiting for controller...',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),

          // Crossroad view: north / east+west / south.
          _Crossroad(
            lights: _state.lights,
            onSet: _sending || !online
                ? null
                : (direction, color) => _send(
                    () => _service.setColor(direction, color),
                    '$color $direction',
                  ),
          ),
          const SizedBox(height: 16),

          // Phase duration inputs for AUTO mode.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AUTO cycle durations (seconds)',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _DurationField(
                          controller: _greenCtrl,
                          label: 'Green',
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DurationField(
                          controller: _yellowCtrl,
                          label: 'Yellow',
                          color: Colors.amber.shade700,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DurationField(
                          controller: _redCtrl,
                          label: 'Red',
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: (_sending || !online) ? null : _startAuto,
                      icon: const Icon(Icons.autorenew),
                      label: const Text('APPLY & START AUTO'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Any positive seconds · AUTO always starts from all-red',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The four signal heads laid out like a crossroad.
class _Crossroad extends StatelessWidget {
  const _Crossroad({required this.lights, required this.onSet});

  final Map<String, String> lights;
  final void Function(String direction, String color)? onSet;

  static const _colorOf = {
    'red': Colors.red,
    'yellow': Colors.amber,
    'green': Colors.green,
  };

  Widget _head(String direction) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in _colorOf.entries)
          Container(
            width: 26,
            height: 26,
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: lights[direction] == entry.key
                  ? entry.value
                  : entry.value.withAlpha(50),
              boxShadow: lights[direction] == entry.key
                  ? [BoxShadow(color: entry.value.withAlpha(120), blurRadius: 10)]
                  : null,
            ),
          ),
      ],
    );
  }

  /// Small colour button; disabled while the head already shows that colour.
  Widget _colorButton(String direction, String color, Color fill) {
    final isActive = lights[direction] == color;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap:
            onSet == null || isActive ? null : () => onSet!(direction, color),
        child: Container(
          width: 34,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? fill : fill.withAlpha(60),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            color == 'yellow' ? 'YEL' : color.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isActive ? Colors.white : fill,
            ),
          ),
        ),
      ),
    );
  }

  Widget _arm(String direction) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(direction.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 6),
          _head(direction),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _colorButton(direction, 'green', Colors.green),
              _colorButton(direction, 'yellow', Colors.amber.shade700),
              _colorButton(direction, 'red', Colors.red),
            ],
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _arm('north'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _arm('west'),
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black12,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.add_road, size: 32),
                ),
                _arm('east'),
              ],
            ),
            _arm('south'),
          ],
        ),
      ),
    );
  }
}

/// Seconds input; any positive value is accepted (no upper limit).
class _DurationField extends StatelessWidget {
  const _DurationField({
    required this.controller,
    required this.label,
    required this.color,
  });

  final TextEditingController controller;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        helperText: 'seconds',
        labelStyle: TextStyle(color: color),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: color, width: 2),
        ),
        border: const OutlineInputBorder(),
      ),
    );
  }
}
