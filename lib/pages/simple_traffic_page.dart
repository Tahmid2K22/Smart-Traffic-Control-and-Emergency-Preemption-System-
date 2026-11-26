import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/intersection_point.dart';
import '../services/intersection_service.dart';
import '../services/push_notification_service.dart';
import '../services/traffic_rtdb_service.dart';
import '../services/traffic_service.dart';

class SimpleTrafficPage extends StatefulWidget {
  const SimpleTrafficPage({super.key, this.assignedIntersection});

  final String? assignedIntersection;

  @override
  State<SimpleTrafficPage> createState() => _SimpleTrafficPageState();
}

class _SimpleTrafficPageState extends State<SimpleTrafficPage> {
  final _greenCtrl = TextEditingController(text: '30');
  final _yellowCtrl = TextEditingController(text: '3');
  final _redCtrl = TextEditingController(text: '2');

  final _intersectionService = IntersectionService();
  final _trafficService = TrafficService();
  IntersectionPoint? _selected;
  TrafficRtdbService? _service;
  StreamSubscription<TrafficRtdbState>? _sub;
  StreamSubscription<List<IntersectionPoint>>? _intersectionsSub;
  StreamSubscription<List<OfficerEscapeAlert>>? _alertsSub;
  List<IntersectionPoint> _intersections = const [];
  List<OfficerEscapeAlert> _activeAlerts = const [];
  final Set<String> _announcedAlertIds = <String>{};
  TrafficRtdbState _state = const TrafficRtdbState(
    mode: 'unknown',
    phase: 'unknown',
    lights: {},
    priority: '',
    updated: null,
  );
  bool _sending = false;
  bool _releasing = false;
  final _pushService = PushNotificationService();

  @override
  void initState() {
    super.initState();
    _selected = _resolveAssigned(null);
    if (_selected != null) {
      _service = TrafficRtdbService(intersectionId: _selected!.id);
      _subscribe();
    }
    _intersectionsSub = _intersectionService.watchIntersections().listen((list) {
      if (!mounted) return;
      setState(() => _intersections = list);
      if (_selected == null) {
        final resolved = _resolveAssigned(list);
        if (resolved != null) {
          setState(() {
            _selected = resolved;
            _service = TrafficRtdbService(intersectionId: resolved.id);
          });
          _subscribe();
        }
      }
    });
    unawaited(_pushService.registerForCurrentUser());
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isNotEmpty) {
      _alertsSub = _trafficService.activeAlertsForOfficer(uid).listen((alerts) {
        if (!mounted) return;
        OfficerEscapeAlert? newest;
        for (final alert in alerts) {
          if (_announcedAlertIds.add(alert.alertId)) {
            newest ??= alert;
          }
        }
        setState(() => _activeAlerts = alerts);
        if (newest != null) {
          unawaited(HapticFeedback.heavyImpact());
          unawaited(SystemSound.play(SystemSoundType.alert));
          _notice(
            '🚑 Escape request: ${newest.driverName} at '
            '${newest.intersectionName} (${newest.approachDirection.toUpperCase()})',
          );
        }
      }, onError: (Object _) {});
    }
  }

  IntersectionPoint? _resolveAssigned(List<IntersectionPoint>? list) {
    final name = widget.assignedIntersection?.trim().toLowerCase();
    final candidates = list ?? _intersections;
    if (name != null && name.isNotEmpty) {
      for (final point in candidates) {
        if (point.name.toLowerCase() == name || point.id == name) return point;
      }
    }
    return null;
  }

  void _subscribe() {
    unawaited(_sub?.cancel());
    _sub = _service!.statusStream.listen((state) {
      if (mounted) setState(() => _state = state);
    }, onError: (Object error) {
      if (mounted) _notice('Status stream error: $error');
    });
  }

  Future<void> _chooseIntersection(IntersectionPoint point) async {
    if (_selected != null && point.id == _selected!.id) return;
    setState(() {
      _selected = point;
      _state = const TrafficRtdbState(
        mode: 'unknown',
        phase: 'unknown',
        lights: {},
        priority: '',
        updated: null,
      );
    });
    _service = TrafficRtdbService(intersectionId: point.id);
    _subscribe();
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_intersectionsSub?.cancel());
    unawaited(_alertsSub?.cancel());
    _pushService.dispose();
    _greenCtrl.dispose();
    _yellowCtrl.dispose();
    _redCtrl.dispose();
    super.dispose();
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

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
      () => _service!.auto(
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

  Future<void> _releaseAmbulance([String? intersectionId]) async {
    final targetId = intersectionId ?? _service?.intersectionId;
    if (_releasing || targetId == null || targetId.isEmpty) return;
    setState(() => _releasing = true);
    try {
      await _trafficService.releaseEscape(
        intersectionId: targetId,
        source: EscapeReleaseSource.police,
      );
      _notice('Ambulance priority released — back to AUTO');
    } catch (error) {
      _notice('Failed to release: $error');
    } finally {
      if (mounted) setState(() => _releasing = false);
    }
  }

  Widget _buildActiveAlertsSection() {
    if (_activeAlerts.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final alert in _activeAlerts) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade700,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.notifications_active_rounded,
                        color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '🚑 Escape alert · ${alert.intersectionName}',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${alert.driverName} approaching from '
                  '${alert.approachDirection.toUpperCase()}'
                  '${alert.estimatedArrivalMinutes != null ? ' · ~${alert.estimatedArrivalMinutes} min' : ''}'
                  '${alert.distanceMeters != null ? ' (${alert.distanceMeters} m)' : ''}',
                  style: GoogleFonts.poppins(
                    color: Colors.white.withAlpha(235),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_selected?.id != alert.intersectionId) ...[
                      for (final point in _intersections)
                        if (point.id == alert.intersectionId)
                          TextButton(
                            onPressed: () => _chooseIntersection(point),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Colors.white24,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                            ),
                            child: const Text('View',
                                style: TextStyle(fontSize: 12)),
                          ),
                      const SizedBox(width: 8),
                    ],
                    TextButton(
                      onPressed: _releasing
                          ? null
                          : () => _releaseAmbulance(alert.intersectionId),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.white24,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                      ),
                      child: Text(
                        _releasing ? 'Releasing…' : 'Release',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
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
      body: _selected == null
          ? ListView(
              padding: const EdgeInsets.all(24),
              children: [
                _buildActiveAlertsSection(),
                const SizedBox(height: 48),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_off_rounded,
                        size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(
                      'No intersection assigned',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ask an admin to assign an intersection to your account. '
                      'Only server-registered intersections are shown.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(color: Colors.grey),
                    ),
                  ],
                ),
              ],
            )
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildActiveAlertsSection(),
          DropdownButtonFormField<IntersectionPoint>(
            initialValue: _selected,
            decoration: const InputDecoration(
              labelText: 'Intersection',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
            items: [
              for (final point in _intersections)
                DropdownMenuItem(
                  value: point,
                  child: Text('${point.name} · ${point.city}'),
                ),
            ],
            onChanged: (point) => point == null ? null : _chooseIntersection(point),
          ),
          const SizedBox(height: 12),

          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 200,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter:
                      LatLng(_selected!.latitude, _selected!.longitude),
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
                            LatLng(_selected!.latitude, _selected!.longitude),
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

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('AUTO mode'),
            subtitle: Text(
              online
                  ? (_state.priority == 'ambulance'
                      ? 'Locked — ambulance priority active'
                      : _state.mode == 'auto'
                          ? 'Cycling N-E-S-W automatically'
                          : 'MANUAL — lights change only on button clicks')
                  : 'Offline — turn on the controller',
            ),
            value: online && _state.mode == 'auto',
            onChanged: online && !_sending && _state.priority != 'ambulance'
                ? (auto) => _send(() => _service!.setMode(auto),
                    auto ? 'AUTO' : 'MANUAL')
                : null,
          ),
          const SizedBox(height: 8),

          if (_state.priority == 'ambulance') ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.blue.shade700,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.emergency, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '🚑 Ambulance priority — controls locked until it passes',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _releasing ? null : _releaseAmbulance,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white24,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _releasing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Release', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          _Crossroad(
            lights: _state.lights,
            manual:
                _state.mode == 'manual' && _state.priority != 'ambulance',
            onSet: _sending || !online || _state.priority == 'ambulance'
                ? null
                : (direction, color) => _send(
                    () => _service!.setColor(direction, color),
                    '$color $direction',
                  ),
          ),
          const SizedBox(height: 16),

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
                    'Any positive seconds · applying starts AUTO: all lights '
                    'to red, then the N-E-S-W cycle',
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

class _Crossroad extends StatelessWidget {
  const _Crossroad({
    required this.lights,
    required this.manual,
    required this.onSet,
  });

  final Map<String, String> lights;
  final bool manual;
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
          if (manual)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _colorButton(direction, 'green', Colors.green),
                _colorButton(direction, 'yellow', Colors.amber.shade700),
                _colorButton(direction, 'red', Colors.red),
              ],
            )
          else
            const SizedBox(height: 26),
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
