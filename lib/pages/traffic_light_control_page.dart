import 'dart:async';

import 'package:flutter/material.dart';

import '../services/ble_traffic_service.dart';

class TrafficLightControlPage extends StatefulWidget {
  const TrafficLightControlPage({super.key, this.service});

  final BleTrafficService? service;

  @override
  State<TrafficLightControlPage> createState() =>
      _TrafficLightControlPageState();
}

class _TrafficLightControlPageState extends State<TrafficLightControlPage> {
  late final BleTrafficService _ble;
  TrafficLightStatus? _status;
  Map<String, dynamic>? _authorization;
  List<TrafficLightDevice> _devices = [];
  TrafficLightDevice? _selected;
  bool _checking = true;
  bool _scanning = false;
  bool _connecting = false;
  bool _sending = false;
  bool _refreshing = false;
  int _greenSec = 30;
  int _yellowSec = 5;
  int _allRedSec = 2;
  int _ticks = 0;
  String? _commandNotice;
  Timer? _refreshTimer;
  Timer? _scanTimer;
  StreamSubscription<List<TrafficLightDevice>>? _scanSub;
  StreamSubscription<TrafficLightStatus>? _statusSub;
  StreamSubscription<bool>? _connectionSub;

  bool get _authorized => _authorization?['isAuthorized'] == true;
  bool get _ready =>
      _authorized && _ble.isReady && _status != null && !_refreshing;

  @override
  void initState() {
    super.initState();
    _ble = widget.service ?? BleTrafficService.instance;
    _status = _ble.isConnected ? _ble.latestStatus : null;
    _statusSub = _ble.statusStream.listen(
      (status) {
        if (mounted && _ble.isConnected) setState(() => _status = status);
      },
      onError: (Object error) {
        if (mounted) setState(() => _status = null);
      },
    );
    _connectionSub = _ble.connectionStream.listen((connected) {
      if (!mounted) return;
      setState(() {
        _status = connected ? _ble.latestStatus : null;
        _commandNotice = null;
        if (!connected) _selected = null;
      });
      if (connected) unawaited(_refreshStatus(silent: true));
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      // Readiness expires even when the device stops sending notifications.
      setState(() {
        if (!_ble.isConnected) _status = null;
      });
      if (++_ticks % 5 == 0 && !_ble.isReady) {
        unawaited(_refreshStatus(silent: true));
      }
    });
    unawaited(_checkAuthorization());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scanTimer?.cancel();
    unawaited(_scanSub?.cancel());
    unawaited(_statusSub?.cancel());
    unawaited(_connectionSub?.cancel());
    // The dashboard owns auto-connect and the shared connection, not this page.
    super.dispose();
  }

  Future<void> _checkAuthorization() async {
    setState(() => _checking = true);
    try {
      final result = await _ble.checkUserAuthorization();
      if (!mounted) return;
      setState(() => _authorization = result);
      if (_authorized) unawaited(_refreshStatus(silent: true));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _authorization = {'isAuthorized': false, 'reason': '$error'};
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _startScan() async {
    if (!_authorized || _scanning || _connecting) return;
    setState(() {
      _scanning = true;
      _devices = [];
    });
    try {
      if (!await _ble.requestPermissions()) {
        throw StateError('Bluetooth permission is required to scan.');
      }
      if (!mounted) return;
      await _scanSub?.cancel();
      if (!mounted) return;
      _scanSub = _ble.scan().listen(
        (devices) {
          if (mounted) setState(() => _devices = devices);
        },
        onError: (Object error) {
          if (mounted) setState(() => _scanning = false);
          _showMessage('Scan failed: $error');
        },
        onDone: () {
          if (mounted) setState(() => _scanning = false);
        },
      );
      _scanTimer?.cancel();
      _scanTimer = Timer(const Duration(seconds: 10), _stopScan);
    } catch (error) {
      if (mounted) setState(() => _scanning = false);
      _showMessage('Scan failed: $error');
    }
  }

  Future<void> _stopScan() async {
    _scanTimer?.cancel();
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await _ble.stopScan();
    } catch (error) {
      _showMessage('Unable to stop scan: $error');
    }
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _connect(TrafficLightDevice device) async {
    if (!_authorized || _connecting) return;
    setState(() {
      _connecting = true;
      _selected = device;
      _status = null;
      _commandNotice = null;
    });
    try {
      await _stopScan();
      if (!mounted) return;
      await _ble.connect(device.device);
      if (!mounted) return;
      setState(() => _status = _ble.latestStatus);
      unawaited(_refreshStatus(silent: true));
    } catch (error) {
      _showMessage('Connection failed: $error');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _disconnect() async {
    try {
      await _ble.disconnect();
      if (mounted) {
        setState(() {
          _status = null;
          _selected = null;
          _commandNotice = null;
        });
      }
    } catch (error) {
      _showMessage('Disconnect failed: $error');
    }
  }

  Future<void> _refreshStatus({bool silent = false}) async {
    if (!_authorized || !_ble.isConnected || _refreshing || _sending) {
      return;
    }
    setState(() => _refreshing = true);
    try {
      await _ble.requestStatus();
    } catch (error) {
      if (!silent) _showMessage('Status refresh failed: $error');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _send(Future<void> Function() command) async {
    if (!_ready || _sending) return;
    setState(() {
      _sending = true;
      _commandNotice = null;
    });
    try {
      await command();
      if (!mounted) return;
      setState(() {
        _commandNotice =
            'Command accepted by controller. Waiting for reported state; '
            'acceptance does not mean the transition is complete.';
      });
    } catch (error) {
      _showMessage('Command failed: $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String get _readinessMessage {
    if (!_ble.isConnected) {
      return 'Disconnected — scan and connect to a controller.';
    }
    if (!_ble.isAuthenticated) {
      return 'Connected — waiting for controller authentication.';
    }
    if (_status == null) return 'Connected — waiting for device status.';
    if (!_status!.supportsFourWay || _status!.version < 2) {
      return 'Legacy firmware — four-way v2 firmware is required. Controls disabled.';
    }
    if (_status!.errorCode == 'unconfigured') {
      return 'Controller unconfigured — it must be bound to your intersection. Controls disabled.';
    }
    if (_status!.intersectionId != _authorization?['intersectionId']) {
      return 'Intersection mismatch — connect to your assigned controller. Controls disabled.';
    }
    if (!_status!.authOk) {
      return 'Controller has not confirmed authorization. Controls disabled.';
    }
    if (!_ble.isReady) {
      return 'Status stale or controller not ready. Controls disabled until a fresh, matching status arrives.';
    }
    return 'Ready — authenticated controller with fresh status for your intersection.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Four-way signal control'),
        actions: [
          if (_authorized && _ble.isConnected)
            IconButton(
              tooltip: 'Refresh device status',
              onPressed: _refreshing || _sending
                  ? null
                  : () => _refreshStatus(),
              icon: const Icon(Icons.refresh),
            ),
          if (_authorized && _ble.isConnected)
            IconButton(
              tooltip: 'Disconnect controller',
              onPressed: _sending || _connecting ? null : _disconnect,
              icon: const Icon(Icons.bluetooth_disabled),
            ),
        ],
      ),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : !_authorized
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock, size: 48),
                    const Text('Verified Traffic Police access required'),
                    Text(
                      _authorization?['reason']?.toString() ?? 'Only authorized officers may connect and control signals.',
                    ),
                    TextButton(
                      onPressed: _checkAuthorization,
                      child: const Text('Re-check authorization'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.badge),
                  title: Text(
                    '${_authorization?['name'] ?? 'Officer'} • '
                    '${_authorization?['policeId'] ?? ''}',
                  ),
                  subtitle: Text(
                    'Assigned: ${_authorization?['intersection'] ?? ''}\n'
                    'Intersection ID: ${_authorization?['intersectionId'] ?? 'Not assigned'}',
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: Icon(_ready ? Icons.verified : Icons.info_outline),
                    title: Text(_readinessMessage),
                    subtitle: Text(
                      _selected?.name ?? 'Shared BLE controller connection',
                    ),
                  ),
                ),
                if (!_ble.isConnected) _buildScanPanel(),
                if (_commandNotice != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(_commandNotice!),
                  ),
                const SizedBox(height: 12),
                FourWaySignalPanel(
                  status: _status,
                  enabled: _ready,
                  sending: _sending,
                  onSetDirection: (direction, light) => _send(
                    () => _ble.setDirectionLight(
                      direction: direction,
                      light: light,
                    ),
                  ),
                  onAllRed: () => _send(_ble.setAllRed),
                ),
                const SizedBox(height: 16),
                _buildModeControls(),
              ],
            ),
    );
  }

  Widget _buildScanPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Connect to your assigned intersection controller.'),
            if (_connecting) const LinearProgressIndicator(),
            FilledButton.icon(
              onPressed: _connecting
                  ? null
                  : (_scanning ? _stopScan : _startScan),
              icon: const Icon(Icons.bluetooth_searching),
              label: Text(_scanning ? 'Stop scan' : 'Scan for controllers'),
            ),
            for (final device in _devices)
              ListTile(
                title: Text(device.name),
                subtitle: Text('${device.rssi} dBm'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _connecting ? null : () => _connect(device),
              ),
            if (_scanning && _devices.isEmpty)
              const Text('Searching for nearby controllers…'),
          ],
        ),
      ),
    );
  }

  Widget _buildModeControls() {
    final enabled = _ready && !_sending && !_isTransferring(_status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Device-reported mode: ${_status?.mode ?? 'unknown'}'),
            const Text(
              'Timing values below are a draft until applied and acknowledged.',
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: enabled ? () => _send(_ble.setManualMode) : null,
              child: const Text('Apply manual mode'),
            ),
            _timingSlider(
              'Green per direction',
              _greenSec,
              5,
              300,
              enabled ? (value) => setState(() => _greenSec = value) : null,
            ),
            _timingSlider(
              'Yellow clearance',
              _yellowSec,
              3,
              60,
              enabled ? (value) => setState(() => _yellowSec = value) : null,
            ),
            _timingSlider(
              'All-red clearance',
              _allRedSec,
              2,
              60,
              enabled ? (value) => setState(() => _allRedSec = value) : null,
            ),
            FilledButton(
              onPressed: enabled
                  ? () => _send(
                      () => _ble.setAutoMode(
                        greenSec: _greenSec,
                        yellowSec: _yellowSec,
                        allRedSec: _allRedSec,
                      ),
                    )
                  : null,
              child: const Text('Apply auto mode and timings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timingSlider(
    String label,
    int value,
    int min,
    int max,
    ValueChanged<int>? onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: $value s ($min–$max s)'),
        Slider(
          label: '$value s',
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          onChanged: onChanged == null
              ? null
              : (value) => onChanged(value.round()),
        ),
      ],
    );
  }
}

bool _isTransferring(TrafficLightStatus? status) =>
    status?.phase == 'yellow' ||
    (status?.targetDirection != null && status?.phase == 'all_red');

String _controllerError(String code) => switch (code) {
  'busy' => 'busy — controller is completing a transfer; wait or use All Red.',
  'unconfigured' => 'unconfigured — controller needs an intersection binding.',
  'intersection_mismatch' =>
    'intersection_mismatch — controller does not match your assignment.',
  _ => code,
};

/// Commands never change these readouts; only device-reported status does.
class FourWaySignalPanel extends StatelessWidget {
  const FourWaySignalPanel({
    super.key,
    required this.status,
    required this.enabled,
    required this.onSetDirection,
    required this.onAllRed,
    this.sending = false,
  });

  final TrafficLightStatus? status;
  final bool enabled;
  final bool sending;
  final void Function(String direction, String light) onSetDirection;
  final VoidCallback onAllRed;

  @override
  Widget build(BuildContext context) {
    final transferring = _isTransferring(status);
    final canChangeDirection = enabled && !sending && !transferring;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Four-way device status',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(
          'Only controller-reported lights are shown. Unknown is not red. '
          'Disabled readouts may be outdated.',
        ),
        if (status != null) ...[
          Text('Mode: ${status!.mode} • Phase: ${status!.phase}'),
          Text(
            'Controller: ${status!.intersectionId} • v${status!.version} • '
            'Sequence ${status!.sequence} • Uptime ${status!.uptime} s',
          ),
          if (status!.errorCode != null)
            Text('Controller error: ${_controllerError(status!.errorCode!)}'),
        ],
        if (transferring)
          Text(
            'Transfer pending → ${status!.targetDirection?.toUpperCase() ?? 'ALL RED'}. '
            'Waiting for device-reported completion after yellow and all-red clearance.',
          ),
        if (sending) ...[
          const LinearProgressIndicator(),
          const Text('Waiting for controller acknowledgement…'),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('all-red'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red.shade800,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
          ),
          onPressed: enabled && !sending ? onAllRed : null,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('ALL RED — stop every direction'),
        ),
        const SizedBox(height: 8),
        const Text(
          'A green request selects one direction; firmware keeps the other '
          'directions red. Transfers pass through yellow clearance → all-red '
          'clearance before the selected direction turns green (at least 3 + 2 seconds). '
          'All Red remains available during a transfer after acknowledgement.',
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 600
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final direction in kTrafficDirections)
                  SizedBox(
                    width: width,
                    child: _directionCard(
                      context,
                      direction,
                      canChangeDirection,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _directionCard(
    BuildContext context,
    String direction,
    bool canChange,
  ) {
    final light = status?.lightFor(direction).toLowerCase() ?? 'unknown';
    final known = const ['red', 'yellow', 'green'].contains(light);
    final name = '${direction[0].toUpperCase()}${direction.substring(1)}';
    return Card(
      key: ValueKey('head-$direction'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(name, style: Theme.of(context).textTheme.titleMedium),
            Semantics(
              label:
                  '$name device-reported light: ${known ? light : 'unknown'}',
              child: Text(
                'Reported: ${known ? light.toUpperCase() : 'UNKNOWN'}',
                key: ValueKey('reported-$direction'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final entry in const {
                  'red': Colors.red,
                  'yellow': Colors.amber,
                  'green': Colors.green,
                }.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Container(
                      key: ValueKey('lamp-$direction-${entry.key}'),
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: light == entry.key
                            ? entry.value
                            : Colors.grey.shade300,
                        border: Border.all(color: Colors.black26),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final color in const ['red', 'yellow', 'green'])
                  OutlinedButton(
                    key: ValueKey('set-$direction-$color'),
                    onPressed:
                        canChange && (color != 'yellow' || light == 'green')
                        ? () => onSetDirection(direction, color)
                        : null,
                    child: Text(
                      '${color[0].toUpperCase()}${color.substring(1)}',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
