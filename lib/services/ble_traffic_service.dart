import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ── BLE UUIDs (must match ESP32 firmware exactly) ────────────────────────────
// Service UUID for Traffic Light Controller
const String kTrafficServiceUUID  = '12345678-1234-1234-1234-123456789abc';
// Characteristic: app writes commands here
const String kCommandCharUUID     = '12345678-1234-1234-1234-123456789001';
// Characteristic: ESP32 notifies status updates here
const String kStatusCharUUID      = '12345678-1234-1234-1234-123456789002';
// Characteristic: auth challenge/response
const String kAuthCharUUID        = '12345678-1234-1234-1234-123456789003';

// ── Command protocol ─────────────────────────────────────────────────────────
// JSON-based signed command format:
// { "cmd": "RED|YELLOW|GREEN|AUTO", "uid": "<firebaseUID>",
//   "ts": <unixMs>, "sig": "<hmac-sha256-hex>", [...extra fields] }
//
// The ESP32 validates:
//  1. HMAC-SHA256 of (cmd+uid+ts) using the shared secret
//  2. Timestamp within ±30 seconds (replay-attack protection)
//  3. Role byte in auth handshake (only admin/driver allowed)

const String kSharedSecret = 'CHANGE_ME_USE_ENV_SECRET_32BYTES!';

/// Result of a BLE scan
class TrafficLightDevice {
  final BluetoothDevice device;
  final String name;
  final int rssi;
  TrafficLightDevice({required this.device, required this.name, required this.rssi});
}

/// Live status received from ESP32
class TrafficLightStatus {
  final String currentLight; // 'red' | 'yellow' | 'green'
  final String mode;         // 'manual' | 'auto'
  final int    uptime;       // seconds since boot
  final bool   authOk;       // whether session is authenticated
  TrafficLightStatus({
    required this.currentLight,
    required this.mode,
    required this.uptime,
    required this.authOk,
  });

  factory TrafficLightStatus.fromJson(Map<String, dynamic> j) => TrafficLightStatus(
    currentLight: j['light'] as String? ?? 'red',
    mode:         j['mode']  as String? ?? 'manual',
    uptime:       (j['uptime'] as num?)?.toInt() ?? 0,
    authOk:       j['auth']  as bool?   ?? false,
  );
}

class BleTrafficService {
  BleTrafficService._();
  static final BleTrafficService instance = BleTrafficService._();

  BluetoothDevice?          _device;
  BluetoothCharacteristic?  _cmdChar;
  BluetoothCharacteristic?  _statusChar;
  BluetoothCharacteristic?  _authChar;

  bool _authenticated = false;
  final _statusController = StreamController<TrafficLightStatus>.broadcast();

  Stream<TrafficLightStatus> get statusStream => _statusController.stream;
  bool get isConnected      => _device?.isConnected ?? false;
  bool get isAuthenticated  => _authenticated;

  //  Scanning 
  /// Scans for ESP32 traffic-light devices (advertise service UUID).
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
          name: r.device.platformName.isNotEmpty
              ? r.device.platformName
              : 'ESP32 Traffic Light',
          rssi: r.rssi,
        );
      }
      yield found.values.toList();
    }
  }

  Future<void> stopScan() => FlutterBluePlus.stopScan();

  // ── Connection ─────────────────────────────────────────────────────────────
  Future<void> connect(BluetoothDevice device) async {
    _device = device;
    await device.connect(autoConnect: false, timeout: const Duration(seconds: 15));
    await _discoverServices();
    await _subscribeStatus();
    await _authenticate();
  }

  Future<void> disconnect() async {
    _authenticated = false;
    await _device?.disconnect();
    _device    = null;
    _cmdChar   = null;
    _statusChar = null;
    _authChar  = null;
  }

  Future<void> _discoverServices() async {
    final services = await _device!.discoverServices();
    for (final s in services) {
      if (s.uuid == Guid(kTrafficServiceUUID)) {
        for (final c in s.characteristics) {
          if (c.uuid == Guid(kCommandCharUUID))  _cmdChar    = c;
          if (c.uuid == Guid(kStatusCharUUID))   _statusChar = c;
          if (c.uuid == Guid(kAuthCharUUID))      _authChar   = c;
        }
        break;
      }
    }
    if (_cmdChar == null || _statusChar == null || _authChar == null) {
      throw Exception('Required BLE characteristics not found. Wrong device?');
    }
  }

  Future<void> _subscribeStatus() async {
    await _statusChar!.setNotifyValue(true);
    _statusChar!.lastValueStream.listen((bytes) {
      if (bytes.isEmpty) return;
      try {
        final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        _statusController.add(TrafficLightStatus.fromJson(json));
      } catch (_) {}
    });
  }

  /// Verifies if the current logged-in user is authorized to control traffic lights.
  /// Only verified `traffic_police` officers and `admin` users are authorized.
  Future<Map<String, dynamic>> checkUserAuthorization() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return {
        'isAuthorized': false,
        'role': 'unauthenticated',
        'isVerified': false,
        'reason': 'Please log in to control traffic lights.',
      };
    }

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data() ?? {};
      final role = data['role'] as String? ?? 'user';
      final isVerified = (data['isVerified'] == true && data['verificationStatus'] == 'APPROVED') || role == 'admin';

      if (role != 'traffic_police' && role != 'admin') {
        return {
          'isAuthorized': false,
          'role': role,
          'isVerified': false,
          'reason': 'Access Restricted: Only Traffic Police or Admin can modify traffic lights.',
        };
      }

      if (role == 'traffic_police' && !isVerified) {
        return {
          'isAuthorized': false,
          'role': role,
          'isVerified': false,
          'verificationStatus': data['verificationStatus'] ?? 'PENDING',
          'reason': 'Verification Required: Your Traffic Police account is pending Admin approval.',
        };
      }

      return {
        'isAuthorized': true,
        'role': role,
        'isVerified': true,
        'name': data['name'] ?? data['fullName'] ?? 'Traffic Officer',
        'policeId': data['policeId'] ?? '',
        'intersection': data['assignedIntersection'] ?? '',
      };
    } catch (e) {
      return {
        'isAuthorized': false,
        'role': 'unknown',
        'isVerified': false,
        'reason': 'Error checking authorization: $e',
      };
    }
  }

  // ── Authentication (HMAC challenge-response) ───────────────────────────────
  /// 3-step handshake:
  /// 1. App writes its Firebase UID + verified role to authChar
  /// 2. ESP32 notifies a random 16-byte challenge
  /// 3. App writes HMAC-SHA256(challenge, sharedSecret) back
  Future<void> _authenticate() async {
    _authenticated = false;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not logged in');

    // Strict role check: only verified traffic_police or admin allowed
    final authStatus = await checkUserAuthorization();
    if (authStatus['isAuthorized'] != true) {
      throw Exception(authStatus['reason'] ?? 'Access denied: Traffic Police authorization required.');
    }

    final role = authStatus['role'] as String;

    // Step 1 — send identity with verified role
    final identity = jsonEncode({'uid': user.uid, 'role': role});
    await _authChar!.write(utf8.encode(identity), withoutResponse: false);

    // Step 2 — read challenge (ESP32 replies via notify; we poll once for simplicity)
    await Future.delayed(const Duration(milliseconds: 500));
    final challenge = await _authChar!.read();

    if (challenge.isEmpty) throw Exception('No challenge received from ESP32');

    // Step 3 — send HMAC response
    final key    = utf8.encode(kSharedSecret);
    final hmac   = Hmac(sha256, key);
    final digest = hmac.convert(challenge);
    final resp   = jsonEncode({'hmac': digest.toString(), 'uid': user.uid});
    await _authChar!.write(utf8.encode(resp), withoutResponse: false);

    // Wait for auth-ok status
    await Future.delayed(const Duration(milliseconds: 600));
    final statusBytes = await _statusChar!.read();
    if (statusBytes.isNotEmpty) {
      try {
        final j = jsonDecode(utf8.decode(statusBytes)) as Map<String, dynamic>;
        _authenticated = j['auth'] as bool? ?? false;
      } catch (_) {}
    }

    if (!_authenticated) throw Exception('Authentication rejected by ESP32 (Role or signature invalid)');
  }

  // ── Command sending ────────────────────────────────────────────────────────
  Future<void> _sendCommand(Map<String, dynamic> payload) async {
    if (!isConnected)     throw Exception('Not connected');
    if (!_authenticated)  throw Exception('Not authenticated');

    final user = FirebaseAuth.instance.currentUser;
    if (user == null)     throw Exception('Not logged in');

    // Re-verify authorization before sending command
    final authStatus = await checkUserAuthorization();
    if (authStatus['isAuthorized'] != true) {
      throw Exception('Unauthorized: Only Traffic Police or Admin can send traffic light commands.');
    }

    // Build signed command
    final ts    = DateTime.now().millisecondsSinceEpoch;
    final cmd   = payload['cmd'] as String;
    final msg   = '$cmd${user.uid}$ts';
    final key   = utf8.encode(kSharedSecret);
    final hmac  = Hmac(sha256, key);
    final sig   = hmac.convert(utf8.encode(msg)).toString();

    final full  = {
      ...payload,
      'uid': user.uid,
      'ts': ts,
      'sig': sig,
    };

    final bytes = utf8.encode(jsonEncode(full));
    // BLE write with response for reliability
    await _cmdChar!.write(bytes, withoutResponse: false);
  }

  // ── Public commands ────────────────────────────────────────────────────────
  Future<void> setRed()    => _sendCommand({'cmd': 'RED'});
  Future<void> setYellow() => _sendCommand({'cmd': 'YELLOW'});
  Future<void> setGreen()  => _sendCommand({'cmd': 'GREEN'});

  Future<void> setAutoMode({
    required int greenSec,
    required int yellowSec,
    required int redSec,
  }) => _sendCommand({
    'cmd':       'AUTO',
    'green_sec': greenSec,
    'yellow_sec': yellowSec,
    'red_sec':   redSec,
  });

  Future<void> setManualMode() => _sendCommand({'cmd': 'MANUAL'});

  Future<void> requestStatus() => _sendCommand({'cmd': 'STATUS'});

  void dispose() {
    _statusController.close();
    disconnect();
  }
}
