import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

// ── BLE UUIDs & Passcode ──────────────────────────────────────────────────────
const String kTrafficServiceUUID = '12345678-1234-1234-1234-123456789abc';
const String kCommandCharUUID    = '12345678-1234-1234-1234-123456789001';
const String kStatusCharUUID     = '12345678-1234-1234-1234-123456789002';
const String kPolicePasscode     = 'TRAFFIC_POLICE_SECURE_PASS_2024';

// ── Models ───────────────────────────────────────────────────────────────────
class TrafficLightDevice {
  final BluetoothDevice device;
  final String name;
  final int rssi;
  TrafficLightDevice({
    required this.device,
    required this.name,
    required this.rssi,
  });
}

class TrafficLightStatus {
  final String currentLight; // 'red' | 'yellow' | 'green'
  final String mode;         // 'manual' | 'auto'
  final int    uptime;       // seconds
  final bool   authOk;

  TrafficLightStatus({
    required this.currentLight,
    required this.mode,
    required this.uptime,
    required this.authOk,
  });

  factory TrafficLightStatus.fromJson(Map<String, dynamic> j) =>
      TrafficLightStatus(
        currentLight: j['light']  as String? ?? 'red',
        mode:         j['mode']   as String? ?? 'manual',
        uptime:       (j['uptime'] as num?)?.toInt() ?? 0,
        authOk:       j['auth']   as bool?   ?? true,
      );
}

// ── BleTrafficService ─────────────────────────────────────────────────────────
class BleTrafficService {
  BleTrafficService._();
  static final BleTrafficService instance = BleTrafficService._();

  BluetoothDevice?         _device;
  BluetoothCharacteristic? _cmdChar;
  BluetoothCharacteristic? _statusChar;

  final _statusController = StreamController<TrafficLightStatus>.broadcast();
  StreamSubscription<List<ScanResult>>? _autoScanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  bool _autoConnectEnabled = false;
  bool _autoConnecting     = false;

  Stream<TrafficLightStatus> get statusStream => _statusController.stream;
  bool get isConnected        => _device?.isConnected ?? false;
  bool get isAuthenticated    => isConnected;
  bool get autoConnectEnabled => _autoConnectEnabled;

  // ── Permissions ────────────────────────────────────────────────────────────
  Future<bool> requestPermissions() async {
    if (kIsWeb) return false;
    if (Platform.isAndroid) {
      final res = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
      return res.values.every((s) => s.isGranted || s.isLimited);
    }
    if (Platform.isIOS) {
      return (await Permission.bluetooth.request()).isGranted;
    }
    return true;
  }

  // ── Role Authorization Gate ────────────────────────────────────────────────
  Future<Map<String, dynamic>> checkUserAuthorization() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return {'isAuthorized': false, 'role': 'none', 'reason': 'Please log in.'};
    }

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data() ?? {};
      final role = data['role'] as String? ?? 'user';
      if (role != 'traffic_police') {
        return {
          'isAuthorized': false,
          'role': role,
          'reason': 'Restricted: Traffic light can only be controlled by verified Traffic Police officers.',
        };
      }

      final isVerified = data['isVerified'] == true && data['verificationStatus'] == 'APPROVED';
      if (!isVerified) {
        return {
          'isAuthorized': false,
          'role': role,
          'reason': 'Pending: Traffic Police account awaiting Admin approval.',
        };
      }

      return {
        'isAuthorized': true,
        'role': role,
        'name': data['name'] ?? data['fullName'] ?? 'Officer',
        'policeId': data['policeId'] ?? '',
        'intersection': data['assignedIntersection'] ?? '',
      };
    } catch (e) {
      return {'isAuthorized': false, 'role': 'unknown', 'reason': '$e'};
    }
  }

  // ── Manual Scan ────────────────────────────────────────────────────────────
  Stream<List<TrafficLightDevice>> scan({Duration timeout = const Duration(seconds: 10)}) async* {
    final found = <String, TrafficLightDevice>{};
    await FlutterBluePlus.startScan(
      withServices: [Guid(kTrafficServiceUUID)],
      timeout: timeout,
    );
    await for (final results in FlutterBluePlus.scanResults) {
      for (final r in results) {
        found[r.device.remoteId.str] = TrafficLightDevice(
          device: r.device,
          name: r.device.platformName.isNotEmpty ? r.device.platformName : 'ESP32 Traffic Light',
          rssi: r.rssi,
        );
      }
      yield found.values.toList();
    }
  }

  Future<void> stopScan() => FlutterBluePlus.stopScan();

  // ── Auto-Connect ───────────────────────────────────────────────────────────
  Future<void> startAutoConnect({
    void Function(TrafficLightDevice dev)? onConnected,
    void Function()? onDisconnected,
    void Function(String msg)? onError,
  }) async {
    if (_autoConnectEnabled) return;

    final permOk = await requestPermissions();
    if (!permOk) {
      onError?.call('Bluetooth permissions not granted.');
      return;
    }

    final auth = await checkUserAuthorization();
    if (auth['isAuthorized'] != true) {
      onError?.call(auth['reason'] as String? ?? 'Unauthorized.');
      return;
    }

    _autoConnectEnabled = true;
    _runAutoScan(onConnected, onDisconnected, onError);
  }

  Future<void> _runAutoScan(
    void Function(TrafficLightDevice dev)? onConnected,
    void Function()? onDisconnected,
    void Function(String msg)? onError,
  ) async {
    if (!_autoConnectEnabled || isConnected || _autoConnecting) return;

    _autoScanSub?.cancel();
    await FlutterBluePlus.startScan(withServices: [Guid(kTrafficServiceUUID)]);

    _autoScanSub = FlutterBluePlus.scanResults.listen((results) async {
      if (!_autoConnectEnabled || _autoConnecting || isConnected || results.isEmpty) return;

      final best = results.reduce((a, b) => a.rssi >= b.rssi ? a : b);
      _autoConnecting = true;
      await FlutterBluePlus.stopScan();
      _autoScanSub?.cancel();

      final dev = TrafficLightDevice(
        device: best.device,
        name: best.device.platformName.isNotEmpty ? best.device.platformName : 'ESP32 Traffic Light',
        rssi: best.rssi,
      );

      try {
        await connect(best.device);
        _autoConnecting = false;

        _connSub?.cancel();
        _connSub = best.device.connectionState.listen((state) {
          if (state == BluetoothConnectionState.disconnected && _autoConnectEnabled) {
            _cmdChar = _statusChar = null;
            onDisconnected?.call();
            Future.delayed(const Duration(seconds: 3), () {
              _runAutoScan(onConnected, onDisconnected, onError);
            });
          }
        });

        onConnected?.call(dev);
      } catch (e) {
        _autoConnecting = false;
        onError?.call(e.toString());
        if (_autoConnectEnabled) {
          Future.delayed(const Duration(seconds: 4), () {
            _runAutoScan(onConnected, onDisconnected, onError);
          });
        }
      }
    });
  }

  Future<void> stopAutoConnect() async {
    _autoConnectEnabled = false;
    _autoConnecting     = false;
    _autoScanSub?.cancel();
    _connSub?.cancel();
    _autoScanSub = null;
    _connSub     = null;
    await FlutterBluePlus.stopScan();
  }

  // ── Connection ─────────────────────────────────────────────────────────────
  void _findChars(List<BluetoothService> services) {
    for (final s in services) {
      if (s.uuid == Guid(kTrafficServiceUUID)) {
        for (final c in s.characteristics) {
          if (c.uuid == Guid(kCommandCharUUID)) _cmdChar = c;
          if (c.uuid == Guid(kStatusCharUUID))  _statusChar = c;
        }
        break;
      }
    }
  }

  Future<void> connect(BluetoothDevice device) async {
    final auth = await checkUserAuthorization();
    if (auth['isAuthorized'] != true) {
      throw Exception(auth['reason'] ?? 'Unauthorized.');
    }

    _device = device;
    _cmdChar  = null;   // clear any stale chars left over from a previous session
    _statusChar = null;

    await device.connect(
      license: License.nonprofit,
      autoConnect: false,
      timeout: const Duration(seconds: 12),
    );

    var services = await device.discoverServices();
    _findChars(services);

    // Android caches the GATT table; if the ESP32 firmware was re-flashed the
    // cache is stale and the characteristics look "missing". Refresh once.
    if (!kIsWeb && Platform.isAndroid && (_cmdChar == null || _statusChar == null)) {
      try {
        await device.clearGattCache();
        services = await device.discoverServices();
        _findChars(services);
      } catch (e) {
        debugPrint('[BLE] GATT cache refresh failed: $e');
      }
    }

    if (_cmdChar == null || _statusChar == null) {
      throw Exception(
        'Traffic light BLE characteristics not found. '
        'Check that the ESP32 is running the matching firmware '
        '(service $kTrafficServiceUUID) and toggle the phone\'s Bluetooth '
        'off/on once if it previously connected to an older firmware.',
      );
    }

    await _statusChar!.setNotifyValue(true);
    _statusChar!.lastValueStream.listen((bytes) {
      if (bytes.isEmpty) return;
      try {
        final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        _statusController.add(TrafficLightStatus.fromJson(json));
      } catch (_) {}
    });
  }

  Future<void> disconnect() async {
    await _device?.disconnect();
    _device     = null;
    _cmdChar    = null;
    _statusChar = null;
  }

  // ── Commands ───────────────────────────────────────────────────────────────
  Future<void> _sendCommand(Map<String, dynamic> payload) async {
    if (!isConnected || _cmdChar == null) {
      throw Exception('Not connected to traffic light.');
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not logged in.');

    final auth = await checkUserAuthorization();
    if (auth['isAuthorized'] != true) {
      throw Exception('Unauthorized: Traffic Police role required.');
    }

    final body = {
      ...payload,
      'pass': kPolicePasscode,
      'role': auth['role'],
      'uid':  user.uid,
    };

    await _cmdChar!.write(utf8.encode(jsonEncode(body)), withoutResponse: false);
  }

  Future<void> setRed()    => _sendCommand({'cmd': 'RED'});
  Future<void> setYellow() => _sendCommand({'cmd': 'YELLOW'});
  Future<void> setGreen()  => _sendCommand({'cmd': 'GREEN'});

  Future<void> setAutoMode({
    required int greenSec,
    required int yellowSec,
    required int redSec,
  }) => _sendCommand({
    'cmd':        'AUTO',
    'green_sec':  greenSec,
    'yellow_sec': yellowSec,
    'red_sec':    redSec,
  });

  Future<void> setManualMode() => _sendCommand({'cmd': 'MANUAL'});
  Future<void> requestStatus() => _sendCommand({'cmd': 'STATUS'});

  void dispose() {
    stopAutoConnect();
    _statusController.close();
    disconnect();
  }
}
