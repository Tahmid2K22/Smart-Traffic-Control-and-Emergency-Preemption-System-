import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/traffic_rtdb_service.dart';

/// Four-way traffic-light control over Firebase Realtime Database.
/// No Bluetooth, no Firestore — just one status stream and one write per tap.
class SimpleTrafficPage extends StatefulWidget {
  const SimpleTrafficPage({super.key});

  @override
  State<SimpleTrafficPage> createState() => _SimpleTrafficPageState();
}

class _SimpleTrafficPageState extends State<SimpleTrafficPage> {
  static final _greenCtrl = TextEditingController(text: '30');
  static final _yellowCtrl = TextEditingController(text: '3');
  static final _redCtrl = TextEditingController(text: '2');

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
    _sub = TrafficRtdbService.instance.statusStream.listen((state) {
      if (mounted) setState(() => _state = state);
    }, onError: (Object error) {
      if (mounted) _notice('Status stream error: $error');
    });
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
  int? _duration(TextEditingController ctrl, int min, int max, String label) {
    final value = int.tryParse(ctrl.text.trim());
    if (value == null || value < min || value > max) {
      _notice('$label must be $min-$max seconds');
      return null;
    }
    return value;
  }

  Future<void> _startAuto() async {
    final green = _duration(_greenCtrl, 5, 300, 'Green time');
    final yellow = _duration(_yellowCtrl, 3, 60, 'Yellow time');
    final red = _duration(_redCtrl, 2, 60, 'Red time');
    if (green == null || yellow == null || red == null) return;
    await _send(
      () => TrafficRtdbService.instance.auto(
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
      appBar: AppBar(title: const Text('Cloud signal control')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Connection + mode header.
          Row(
            children: [
              Icon(
                online ? Icons.cloud_done : Icons.cloud_off,
                color: online ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(online ? 'Controller online' : 'Waiting for controller...'),
              const Spacer(),
              Chip(
                label: Text(_state.mode == 'unknown' ? 'mode: —' : 'mode: ${_state.mode}'),
                labelStyle: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Crossroad view: north / east+west / south.
          _Crossroad(
            lights: _state.lights,
            onGreen: _sending
                ? null
                : (direction) => _send(
                    () => TrafficRtdbService.instance.setGreen(direction),
                    'green $direction',
                  ),
          ),
          const SizedBox(height: 16),

          // Global actions.
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed:
                      _sending ? null : () => _send(TrafficRtdbService.instance.allRed, 'ALL RED'),
                  icon: const Icon(Icons.block),
                  label: const Text('ALL RED'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _sending ? null : _startAuto,
                  icon: const Icon(Icons.autorenew),
                  label: const Text('START AUTO'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

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
                          min: 5,
                          max: 300,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DurationField(
                          controller: _yellowCtrl,
                          label: 'Yellow',
                          min: 3,
                          max: 60,
                          color: Colors.amber.shade700,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DurationField(
                          controller: _redCtrl,
                          label: 'Red',
                          min: 2,
                          max: 60,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Green 5-300 s · Yellow 3-60 s · Red 2-60 s',
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
  const _Crossroad({required this.lights, required this.onGreen});

  final Map<String, String> lights;
  final void Function(String direction)? onGreen;

  static const _colorOf = {
    'red': Colors.red,
    'yellow': Colors.amber,
    'green': Colors.green,
  };

  Widget _head(String direction, {bool hero = false}) {
    final size = hero ? 34.0 : 26.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in _colorOf.entries)
          Container(
            width: size,
            height: size,
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

  Widget _arm(String direction) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(direction.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 6),
          _head(direction),
          const SizedBox(height: 6),
          TextButton(
            onPressed: onGreen == null || lights[direction] == 'green'
                ? null
                : () => onGreen!(direction),
            child: const Text('GREEN'),
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

/// Seconds input with range validation.
class _DurationField extends StatelessWidget {
  const _DurationField({
    required this.controller,
    required this.label,
    required this.min,
    required this.max,
    required this.color,
  });

  final TextEditingController controller;
  final String label;
  final int min;
  final int max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        helperText: '$min-$max s',
        labelStyle: TextStyle(color: color),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: color, width: 2),
        ),
        border: const OutlineInputBorder(),
      ),
    );
  }
}
