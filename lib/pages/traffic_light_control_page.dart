import 'dart:async';

import 'package:flutter/material.dart';

import '../services/ble_traffic_service.dart';
import '../services/firebase_traffic_service.dart';

class TrafficLightControlPage extends StatefulWidget {
  const TrafficLightControlPage({super.key, this.service, this.remoteService});

  final BleTrafficService? service;
  final RemoteTrafficService? remoteService;

  @override
  State<TrafficLightControlPage> createState() =>
      _TrafficLightControlPageState();
}

class _TrafficLightControlPageState extends State<TrafficLightControlPage> {
  late final BleTrafficService _ble;
  TrafficLightStatus? _bleStatus;
  TrafficLightStatus? _remoteAck;
  Timer? _remoteAckTimer;
  int _remoteBoot = 0;
  RemoteTrafficTelemetry? _telemetry;
  RemoteTrafficService? _remote;
  StreamSubscription<RemoteTrafficTelemetry?>? _remoteSub;
  StreamSubscription<String?>? _userSub;
  int _authorizationGeneration = 0;

  bool get _connectionInProgress => _connecting || _ble.isConnecting;
  bool get _bluetoothPriority => _ble.isConnected || _connectionInProgress;
  TrafficLightStatus? get _status =>
      _bluetoothPriority ? _bleStatus : (_remoteAck ?? _telemetry?.status);
  TrafficControlRoute get _route => selectTrafficRoute(
    bleConnected: _ble.isConnected,
    bleConnecting: _connectionInProgress,
    bleReady:
        _ble.isReady &&
        _bleStatus?.intersectionId == _authorization?['intersectionId'] &&
        _bleStatus?.supportsFourWay == true &&
        _bleStatus?.authOk == true,
    remoteReady:
        _remote?.currentUid == _authorization?['uid'] &&
        _telemetry?.isReadyFor(
              _authorization?['intersectionId'] as String? ?? '',
              DateTime.now(),
            ) ==
            true,
  );
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
      _authorized &&
      _route != TrafficControlRoute.unavailable &&
      !_refreshing &&
      !_connectionInProgress;

  @override
  void initState() {
    super.initState();
    _ble = widget.service ?? BleTrafficService.instance;
    _bleStatus = _ble.isConnected ? _ble.latestStatus : null;
    // Existing BLE-only injection must never instantiate Firebase in tests.
    _remote =
        widget.remoteService ??
        (widget.service == null
            ? FirebaseTrafficService(
                checkAuthorization: _ble.checkUserAuthorization,
              )
            : null);
    _remoteSub = _remote?.telemetryStream.listen((telemetry) {
      if (!mounted) return;
      setState(() {
        final previous = _telemetry;
        final ack = _remoteAck;
        // Compare ordered controller publications, not the independent ACK stream.
        final rebooted =
            telemetry != null &&
            previous != null &&
            (telemetry.status.uptime < previous.status.uptime ||
                ((telemetry.status.sequence - previous.status.sequence) &
                        0xffffffff) >
                    0x7fffffff);
        if (rebooted) ++_remoteBoot;
        _telemetry = telemetry;
        if (telemetry == null ||
            rebooted ||
            (ack != null &&
                ((telemetry.status.sequence - ack.sequence) & 0xffffffff) <
                    0x80000000)) {
          _remoteAck = null;
          _remoteAckTimer?.cancel();
        }
      });
    });
    _userSub = _remote?.userChanges.listen((uid) {
      if (!mounted) return;
      ++_authorizationGeneration;
      setState(() {
        _authorization = null;
        _telemetry = null;
        _remoteAck = null;
        _bleStatus = null;
        _commandNotice = null;
      });
      unawaited(_checkAuthorization());
    });
    _statusSub = _ble.statusStream.listen(
      (status) {
        if (mounted && _ble.isConnected) setState(() => _bleStatus = status);
      },
      onError: (Object error) {
        if (mounted) setState(() => _bleStatus = null);
      },
    );
    _connectionSub = _ble.connectionStream.listen((connected) {
      if (!mounted) return;
      setState(() {
        _bleStatus = connected ? _ble.latestStatus : null;
        if (!connected) _selected = null;
      });
      if (connected) unawaited(_refreshStatus(silent: true));
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      // Readiness expires even when the device stops sending notifications.
      setState(() {
        if (!_ble.isConnected) _bleStatus = null;
      });
      if (++_ticks % 5 == 0 && !_connectionInProgress && !_ble.isReady) {
        unawaited(_refreshStatus(silent: true));
      }
    });
    unawaited(_checkAuthorization());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scanTimer?.cancel();
    _remoteAckTimer?.cancel();
    unawaited(_scanSub?.cancel());
    unawaited(_statusSub?.cancel());
    unawaited(_connectionSub?.cancel());
    unawaited(_remoteSub?.cancel());
    unawaited(_userSub?.cancel());
    ++_authorizationGeneration;
    if (widget.remoteService == null) {
      unawaited(_remote?.dispose());
    } else {
      unawaited(_remote?.stop());
    }
    // The dashboard owns auto-connect and the shared connection, not this page.
    super.dispose();
  }

  Future<void> _checkAuthorization() async {
    final generation = ++_authorizationGeneration;
    setState(() => _checking = true);
    try {
      await _remote?.stop();
      final result = await _ble.checkUserAuthorization();
      if (!mounted || generation != _authorizationGeneration) return;
      if (_remote != null &&
          (result['uid'] == null || result['uid'] != _remote!.currentUid)) {
        throw StateError('User session changed. Please log in again.');
      }
      setState(() => _authorization = result);
      if (_authorized) {
        if (_remote != null) {
          await _remote!.watch(
            intersection: result['intersectionId'] as String,
            uid: result['uid'] as String,
          );
        }
        if (!mounted || generation != _authorizationGeneration) return;
        unawaited(_refreshStatus(silent: true));
      }
    } catch (error) {
      if (!mounted || generation != _authorizationGeneration) return;
      setState(() {
        _authorization = {'isAuthorized': false, 'reason': '$error'};
      });
      unawaited(_remote?.stop());
    } finally {
      if (mounted && generation == _authorizationGeneration) {
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _startScan() async {
    if (!_authorized || _scanning || _connectionInProgress || _sending) return;
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
      if (_connectionInProgress) {
        setState(() => _scanning = false);
        return;
      }
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
    if (!_authorized || _connectionInProgress || _sending) return;
    setState(() {
      _connecting = true;
      _selected = device;
      _bleStatus = null;
      _commandNotice = null;
    });
    try {
      await _stopScan();
      if (!mounted || _ble.isConnecting) return;
      await _ble.connect(device.device);
      if (!mounted) return;
      setState(() => _bleStatus = _ble.latestStatus);
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
          _bleStatus = null;
          _selected = null;
          _commandNotice = null;
        });
      }
    } catch (error) {
      _showMessage('Disconnect failed: $error');
    }
  }

  Future<void> _refreshStatus({bool silent = false}) async {
    if (!_authorized ||
        !_ble.isConnected ||
        _connectionInProgress ||
        _refreshing ||
        _sending) {
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

  Future<void> _send(
    Future<void> Function() bluetoothCommand,
    Map<String, dynamic> remoteCommand,
  ) async {
    if (!_ready ||
        _sending ||
        (_isTransferring(_status) && remoteCommand['cmd'] != 'ALL_RED')) {
      return;
    }
    final route = _route;
    final generation = _authorizationGeneration;
    final remoteBoot = _remoteBoot;
    setState(() {
      _sending = true;
      _commandNotice = null;
    });
    try {
      if (route == TrafficControlRoute.bluetooth) {
        await bluetoothCommand();
      } else if (route == TrafficControlRoute.internet) {
        final ack = await _remote!.send(
          remoteCommand,
          canDispatch: () =>
              mounted &&
              generation == _authorizationGeneration &&
              _authorized &&
              !_bluetoothPriority,
        );
        if (!mounted || generation != _authorizationGeneration) return;
        final reported = _telemetry?.status;
        if (remoteBoot == _remoteBoot &&
            (reported == null ||
                ((ack.sequence - reported.sequence) & 0xffffffff) <
                    0x80000000)) {
          _remoteAck = ack;
          _remoteAckTimer?.cancel();
          // An ACK may bridge telemetry lag, but cannot replace telemetry forever.
          _remoteAckTimer = Timer(const Duration(seconds: 6), () {
            if (mounted) setState(() => _remoteAck = null);
          });
        }
      }
      if (!mounted || generation != _authorizationGeneration) return;
      setState(() {
        _commandNotice =
            'Command accepted by controller. Waiting for reported state; '
            'acceptance does not mean the transition is complete.';
      });
    } catch (error) {
      if (!mounted || generation != _authorizationGeneration) return;
      setState(
        () => _commandNotice =
            '$error. No automatic retry or transport fallback.',
      );
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
    if (!_bluetoothPriority) {
      if (_telemetry?.blePriority == true) {
        return 'Controller reserves Bluetooth priority (possibly another officer). Internet controls disabled.';
      }
      if (_route == TrafficControlRoute.internet) {
        return 'Ready — fresh server-reported controller status for your intersection.';
      }
      return 'Internet controller unavailable — waiting for fresh, matching server telemetry. '
          'Controls disabled. Check your connection and phone automatic date/time; '
          'clock skew can invalidate freshness checks.';
    }
    if (!_ble.isConnected) {
      return 'Bluetooth connection reserved or connecting. Internet controls disabled.';
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
              onPressed: _refreshing || _sending || _connectionInProgress
                  ? null
                  : () => _refreshStatus(),
              icon: const Icon(Icons.refresh),
            ),
          if (_authorized && _ble.isConnected)
            IconButton(
              tooltip: 'Disconnect controller',
              onPressed: _sending || _connectionInProgress ? null : _disconnect,
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
                      '${_bluetoothPriority ? 'Route: Bluetooth priority' : 'Route: Internet'}\n'
                      '${_bluetoothPriority ? (_selected?.name ?? 'Shared BLE controller connection') : 'Controller transport: ${_telemetry?.transport ?? 'unknown'}'}',
                      key: const ValueKey('traffic-control-route'),
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
                    TrafficLightCommand.set(direction, light),
                  ),
                  onAllRed: () => _send(_ble.setAllRed, {'cmd': 'ALL_RED'}),
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
            if (_connectionInProgress) const LinearProgressIndicator(),
            FilledButton.icon(
              onPressed: _connectionInProgress || _sending
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
                onTap: _connectionInProgress || _sending
                    ? null
                    : () => _connect(device),
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
              onPressed: enabled
                  ? () => _send(_ble.setManualMode, {'cmd': 'MANUAL'})
                  : null,
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
                      TrafficLightCommand.automatic(
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
