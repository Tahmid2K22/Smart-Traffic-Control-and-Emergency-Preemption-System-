import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/intersection_point.dart';
import '../models/traffic_light_status.dart';
export '../models/traffic_light_status.dart';

const String kTrafficServiceUUID = '12345678-1234-1234-1234-123456789abc';
const String kCommandCharUUID = '12345678-1234-1234-1234-123456789001';
const String kStatusCharUUID = '12345678-1234-1234-1234-123456789002';
// Prototype shared credential only; this is not a Firebase identity proof.
const String kPolicePasscode = 'TRAFFIC_POLICE_SECURE_PASS_2024';

class TrafficLightDevice {
  TrafficLightDevice({
    required this.device,
    required this.name,
    required this.rssi,
  });
  final BluetoothDevice device;
  final String name;
  final int rssi;
}

class BleTrafficService {
  BleTrafficService._() : _authorizationCheck = null;

  @visibleForTesting
  BleTrafficService.forTesting({
    required Future<Map<String, dynamic>> Function() checkAuthorization,
  }) : _authorizationCheck = checkAuthorization;

  static final BleTrafficService instance = BleTrafficService._();
  static const _platformChannel = MethodChannel('e_ambulance/platform');
  final Future<Map<String, dynamic>> Function()? _authorizationCheck;
  Future<int>? _androidSdkInt;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _cmdChar;
  BluetoothCharacteristic? _statusChar;
  StreamSubscription<List<int>>? _statusSub;
  StreamSubscription<BluetoothConnectionState>? _deviceSub;
  StreamSubscription<List<ScanResult>>? _autoScanSub;
  Timer? _autoRetry;
  TrafficLightStatus? _latestStatus;
  DateTime? _receivedAt;
  String? _boundIntersectionId;
  final _statusController = StreamController<TrafficLightStatus>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _pending = <String, Completer<TrafficLightStatus>>{};
  final _rejectedDevices = <String>{};
  final _knownDevices = <String, String>{};
  String? _autoIntersectionId;
  int _requestCounter = 0;
  int _session = 0;
  bool _sending = false;
  bool _autoConnectEnabled = false;
  bool _autoConnecting = false;
  int _connectionAttempts = 0;
  bool _disposed = false;
  void Function(TrafficLightDevice)? _onConnected;
  void Function()? _onDisconnected;
  void Function(String)? _onError;

  Stream<TrafficLightStatus> get statusStream => _statusController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  TrafficLightStatus? get latestStatus => _latestStatus;
  bool get isConnected => _device?.isConnected ?? false;
  bool get isAuthenticated =>
      isConnected &&
      _latestStatus?.authOk == true &&
      _latestStatus?.intersectionId == _boundIntersectionId;
  bool get isReady =>
      isAuthenticated &&
      _latestStatus?.supportsFourWay == true &&
      _boundIntersectionId != 'UNCONFIGURED' &&
      _receivedAt != null &&
      DateTime.now().difference(_receivedAt!) <= const Duration(seconds: 6);
  bool get autoConnectEnabled => _autoConnectEnabled;
  bool get isConnecting => _autoConnecting || _connectionAttempts > 0;

  Future<int> _getAndroidSdkInt() => _androidSdkInt ??= _platformChannel
      .invokeMethod<int>('getAndroidSdkInt')
      .then((sdk) {
        if (sdk == null || sdk < 1) {
          throw StateError(
            'Could not determine the Android version for Bluetooth.',
          );
        }
        return sdk;
      });

  Future<bool> _scanRequiresLocationServices() async =>
      !kIsWeb && Platform.isAndroid ? (await _getAndroidSdkInt()) <= 30 : true;

  void _log(String message) {
    if (kDebugMode) debugPrint('[BLE] $message');
  }

  Future<bool> requestPermissions() async {
    if (kIsWeb) return false;
    if (Platform.isAndroid) {
      final sdk = await _getAndroidSdkInt();
      final permissions = sdk >= 31
          ? [Permission.bluetoothScan, Permission.bluetoothConnect]
          : [Permission.bluetooth, Permission.locationWhenInUse];
      final result = await permissions.request();
      return result.values.every(
        (status) => status.isGranted || status.isLimited,
      );
    }
    if (Platform.isIOS) return (await Permission.bluetooth.request()).isGranted;
    return true;
  }

  Future<Map<String, dynamic>> checkUserAuthorization() async {
    final check = _authorizationCheck;
    if (check != null) return check();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return {'isAuthorized': false, 'reason': 'Please log in.'};
    }
    try {
      final firestore = FirebaseFirestore.instance;
      final profile =
          (await firestore
                  .collection('users')
                  .doc(user.uid)
                  .get(const GetOptions(source: Source.server))
                  .timeout(const Duration(seconds: 8)))
              .data() ??
          {};
      if (profile['role'] != 'traffic_police' ||
          profile['isVerified'] != true ||
          profile['verificationStatus'] != 'APPROVED') {
        return {
          'isAuthorized': false,
          'reason':
              'Only approved, verified traffic police can control signals.',
        };
      }
      IntersectionPoint? assigned;
      final explicitId = profile['assignedIntersectionId'] as String?;
      if (explicitId != null && explicitId.isNotEmpty) {
        final doc = await firestore
            .collection('intersections')
            .doc(explicitId)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 8));
        if (doc.exists) {
          assigned = IntersectionPoint.fromMap(doc.id, doc.data()!);
        }
      } else {
        final documents = await firestore
            .collection('intersections')
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 8));
        final location = profile['intersectionLocation'];
        final matches = documents.docs
            .map((doc) => IntersectionPoint.fromMap(doc.id, doc.data()))
            .where(
              (point) =>
                  point.isActive &&
                  point.matchesOfficer(
                    assignedIntersection:
                        profile['assignedIntersection'] as String?,
                    latitude: location is GeoPoint
                        ? location.latitude
                        : (profile['intersectionLatitude'] as num?)?.toDouble(),
                    longitude: location is GeoPoint
                        ? location.longitude
                        : (profile['intersectionLongitude'] as num?)
                              ?.toDouble(),
                  ),
            )
            .toList();
        // Ambiguous legacy assignments must be resolved explicitly by an admin.
        if (matches.length == 1) assigned = matches.single;
      }
      if (assigned == null || !assigned.isActive) {
        return {
          'isAuthorized': false,
          'reason': 'Ask an admin to assign one active saved intersection to your account.',
        };
      }
      return {
        'isAuthorized': true,
        'role': 'traffic_police',
        'uid': user.uid,
        'name': profile['name'] ?? profile['fullName'] ?? 'Officer',
        'policeId': profile['policeId'] ?? '',
        'intersection': assigned.name,
        'intersectionId': assigned.id,
      };
    } catch (_) {
      return {
        'isAuthorized': false,
        'reason': 'Could not verify your current permission and intersection. Check your connection and retry.',
      };
    }
  }

  TrafficLightDevice _scanDevice(ScanResult result) => TrafficLightDevice(
    device: result.device,
    name: result.device.platformName.isEmpty
        ? 'ESP32 Traffic Light'
        : result.device.platformName,
    rssi: result.rssi,
  );

  Stream<List<TrafficLightDevice>> scan({
    Duration timeout = const Duration(seconds: 10),
  }) async* {
    final found = <String, TrafficLightDevice>{};
    await FlutterBluePlus.startScan(
      withServices: [Guid(kTrafficServiceUUID)],
      timeout: timeout,
      androidCheckLocationServices: await _scanRequiresLocationServices(),
    );
    await for (final results in FlutterBluePlus.scanResults) {
      for (final result in results) {
        found[result.device.remoteId.str] = _scanDevice(result);
      }
      yield found.values.toList();
    }
  }

  Future<void> stopScan() => FlutterBluePlus.stopScan();

  Future<void> startAutoConnect({
    void Function(TrafficLightDevice)? onConnected,
    void Function()? onDisconnected,
    void Function(String)? onError,
  }) async {
    _onConnected = onConnected;
    _onDisconnected = onDisconnected;
    _onError = onError;
    if (_autoConnectEnabled) return;
    if (!await requestPermissions()) {
      onError?.call('Bluetooth permissions not granted.');
      return;
    }
    final authorization = await checkUserAuthorization();
    if (authorization['isAuthorized'] != true) {
      onError?.call(authorization['reason'] as String);
      return;
    }
    _autoIntersectionId = authorization['intersectionId'] as String;
    _rejectedDevices.clear();
    if (!_knownDevices.containsKey(_autoIntersectionId)) {
      onError?.call(
        'Select and connect to your assigned controller in Four-way control first. Auto-reconnect only uses a previously verified device.',
      );
      return;
    }
    _autoConnectEnabled = true;
    if (isReady) {
      onConnected?.call(
        TrafficLightDevice(
          device: _device!,
          name: _device!.platformName,
          rssi: 0,
        ),
      );
    } else {
      await _runAutoScan();
    }
  }

  Future<void> _runAutoScan() async {
    if (!_autoConnectEnabled || isConnected || isConnecting || _disposed) {
      return;
    }
    try {
      await _autoScanSub?.cancel();
      await FlutterBluePlus.startScan(
        withServices: [Guid(kTrafficServiceUUID)],
        androidCheckLocationServices: await _scanRequiresLocationServices(),
      );
      _autoScanSub = FlutterBluePlus.scanResults.listen((results) async {
        if (!_autoConnectEnabled || isConnecting || isConnected) return;
        final candidates = results
            .where(
              (result) =>
                  !_rejectedDevices.contains(result.device.remoteId.str) &&
                  result.device.remoteId.str ==
                      _knownDevices[_autoIntersectionId],
            )
            .toList();
        if (candidates.isEmpty) return;
        candidates.sort((a, b) => b.rssi.compareTo(a.rssi));
        final best = candidates.first;
        _autoConnecting = true;
        try {
          await FlutterBluePlus.stopScan();
          await connect(best.device);
          _onConnected?.call(_scanDevice(best));
        } catch (error) {
          // Retry transient link/network failures, but never repeatedly attach
          // to a device whose firmware or intersection no longer matches.
          final message = '$error';
          if (message.contains('intersection mismatch') ||
              message.contains('Legacy or invalid firmware')) {
            _rejectedDevices.add(best.device.remoteId.str);
            _autoConnectEnabled = false;
          }
          _onError?.call(message);
        } finally {
          _autoConnecting = false;
          if (!isConnected) _scheduleAutoScan();
        }
      }, onError: (Object error) => _onError?.call('$error'));
    } catch (error) {
      _onError?.call('$error');
    }
  }

  void _scheduleAutoScan() {
    _autoRetry?.cancel();
    if (_autoConnectEnabled && !_disposed) {
      _autoRetry = Timer(
        const Duration(seconds: 3),
        () => unawaited(_runAutoScan()),
      );
    }
  }

  Future<void> stopAutoConnect() async {
    _autoConnectEnabled = false;
    _autoRetry?.cancel();
    await _autoScanSub?.cancel();
    _autoScanSub = null;
    await FlutterBluePlus.stopScan();
  }

  void _findChars(List<BluetoothService> services) {
    for (final service in services) {
      if (service.uuid != Guid(kTrafficServiceUUID)) continue;
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid == Guid(kCommandCharUUID)) {
          _cmdChar = characteristic;
        }
        if (characteristic.uuid == Guid(kStatusCharUUID)) {
          _statusChar = characteristic;
        }
      }
    }
  }

  void _acceptStatus(List<int> bytes, int session) {
    if (session != _session || bytes.isEmpty || _disposed) return;
    try {
      final status = TrafficLightStatus.fromJson(
        jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
      );
      if (_latestStatus != null &&
          ((status.sequence - _latestStatus!.sequence) & 0xffffffff) >
              0x7fffffff) {
        return;
      }
      _latestStatus = status;
      _receivedAt = DateTime.now();
      _statusController.add(status);
      final pending = _pending[status.ackId];
      if (pending != null &&
          !pending.isCompleted &&
          status.intersectionId == _boundIntersectionId &&
          status.supportsFourWay) {
        pending.complete(status);
      }
    } catch (_) {
      // A malformed/truncated packet cannot refresh readiness or acknowledge a command.
      debugPrint(
        '[BLE] Invalid four-way status packet; controls remain gated by last valid telemetry.',
      );
    }
  }

  Future<void> connect(BluetoothDevice device) async {
    if (_connectionAttempts > 0) {
      throw StateError(
        'A Bluetooth connection attempt is already in progress.',
      );
    }
    ++_connectionAttempts;
    try {
      await _connect(device);
    } finally {
      --_connectionAttempts;
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    var stage = 'authorization';
    var ownsConnection = false;
    try {
      _log('Checking current authorization.');
      final authorization = await checkUserAuthorization();
      if (authorization['isAuthorized'] != true) {
        throw StateError(authorization['reason'] as String);
      }
      _log('Authorization accepted.');
      stage = 'previous connection cleanup';
      await disconnect();
      final session = ++_session;
      _device = device;
      _boundIntersectionId = authorization['intersectionId'] as String;
      ownsConnection = true;
      stage = 'attach';
      _log('Attaching to selected controller.');
      await device.connect(
        license: License.nonprofit,
        autoConnect: false,
        mtu: null, // Negotiate once below, not the plugin's default 512 first.
        timeout: const Duration(seconds: 12),
      );
      stage = 'MTU negotiation';
      final mtu = !kIsWeb && Platform.isAndroid
          ? await device.requestMtu(517)
          : device.mtuNow;
      _log('MTU result: $mtu.');
      if (mtu < 515) {
        throw StateError(
          'Four-way telemetry requires BLE MTU 515 or greater (received $mtu).',
        );
      }
      _deviceSub = device.connectionState.listen((state) {
        if (session != _session ||
            state != BluetoothConnectionState.disconnected) {
          return;
        }
        _clearState();
        _onDisconnected?.call();
        _scheduleAutoScan();
      });
      stage = 'service discovery';
      _log('Discovering traffic-light service and characteristics.');
      _findChars(await device.discoverServices());
      if (!kIsWeb &&
          Platform.isAndroid &&
          (_cmdChar == null || _statusChar == null)) {
        _log('Characteristics missing; clearing GATT cache and rediscovering.');
        await device.clearGattCache();
        _findChars(await device.discoverServices());
      }
      if (_cmdChar == null || _statusChar == null) {
        throw StateError(
          'Matching traffic-light BLE characteristics were not found. Flash the v2 firmware.',
        );
      }
      _log('Traffic-light characteristics found.');
      stage = 'status subscription';
      _statusSub = _statusChar!.onValueReceived.listen(
        (bytes) => _acceptStatus(bytes, session),
      );
      await _statusChar!.setNotifyValue(true);
      stage = 'initial status';
      _log('Reading initial controller status.');
      _acceptStatus(await _statusChar!.read(), session);
      final status = _latestStatus;
      if (status == null || !status.supportsFourWay) {
        throw StateError(
          'Legacy or invalid firmware: install four-way protocol v2 before controlling signals.',
        );
      }
      stage = 'intersection validation';
      _log(
        'Intersection: expected=$_boundIntersectionId; controller=${status.intersectionId}.',
      );
      if (status.intersectionId != _boundIntersectionId ||
          status.intersectionId == 'UNCONFIGURED') {
        throw StateError(
          'Controller intersection mismatch. Configure the ESP32 with your assigned Firestore intersection ID.',
        );
      }
      stage = 'STATUS handshake';
      _log('Authenticating with controller via STATUS.');
      await _sendCommand({'cmd': 'STATUS'});
      if (!isReady) {
        throw StateError('Controller authentication/status handshake failed.');
      }
      _log('Controller handshake accepted.');
      _knownDevices[_boundIntersectionId!] = device.remoteId.str;
      _connectionController.add(true);
    } catch (error) {
      _log('Connection failed during $stage: $error');
      if (ownsConnection) {
        try {
          await disconnect();
        } catch (cleanupError) {
          _log('Failed connection cleanup: $cleanupError');
        }
      }
      throw StateError('Bluetooth connection failed during $stage: $error');
    }
  }

  void _clearState() {
    ++_session;
    _latestStatus = null;
    _receivedAt = null;
    _boundIntersectionId = null;
    _cmdChar = null;
    _statusChar = null;
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.completeError(
          StateError('Controller disconnected before acknowledgement.'),
        );
      }
    }
    _pending.clear();
    if (!_disposed) _connectionController.add(false);
  }

  Future<void> disconnect() async {
    final device = _device;
    await _statusSub?.cancel();
    await _deviceSub?.cancel();
    _statusSub = null;
    _deviceSub = null;
    _clearState();
    _device = null;
    await device?.disconnect();
  }

  Future<void> _sendCommand(Map<String, dynamic> payload) async {
    if (_sending) {
      throw StateError('Wait for the pending controller acknowledgement.');
    }
    if (!isConnected || _cmdChar == null) {
      throw StateError('Not connected to a four-way controller.');
    }
    _sending = true;
    final session = _session;
    String? requestId;
    try {
      final authorization = await checkUserAuthorization();
      if (authorization['isAuthorized'] != true) {
        throw StateError(authorization['reason'] as String);
      }
      final user = FirebaseAuth.instance.currentUser;
      if (user == null ||
          user.uid != authorization['uid'] ||
          session != _session ||
          !isConnected ||
          _cmdChar == null) {
        throw StateError('Session changed before the command could be sent.');
      }
      if (authorization['intersectionId'] != _boundIntersectionId ||
          _latestStatus?.intersectionId != _boundIntersectionId) {
        throw StateError(
          'Your assigned intersection does not match this controller.',
        );
      }
      if (payload['cmd'] != 'STATUS' && !isReady) {
        throw StateError(
          'Controller status is stale or incompatible. Refresh status before controlling signals.',
        );
      }
      requestId =
          '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}_${++_requestCounter}';
      final body = utf8.encode(
        jsonEncode({
          ...payload,
          'v': 2,
          'request_id': requestId,
          'intersection': _boundIntersectionId,
          'pass': kPolicePasscode,
          'role': authorization['role'],
          'uid': user.uid,
        }),
      );
      if (body.length >= 512 || body.length > _device!.mtuNow - 3) {
        throw StateError('BLE payload exceeds the negotiated packet size.');
      }
      final completion = Completer<TrafficLightStatus>();
      _pending[requestId] = completion;
      final reply = completion.future
          .timeout(const Duration(seconds: 10))
          .then<void>((status) {
            if (status.errorCode != null) {
              throw StateError(
                'Controller rejected command: ${status.errorCode}',
              );
            }
            if (!status.authOk) {
              throw StateError('Controller did not authenticate the command.');
            }
          });
      await Future.wait<void>([
        _cmdChar!
            .write(body, withoutResponse: false)
            .timeout(const Duration(seconds: 10)),
        reply,
      ], eagerError: true);
    } on TimeoutException {
      // No retry: a command may have executed even if its reply was lost.
      _receivedAt = null;
      throw StateError(
        'Controller acknowledgement timed out. Refresh status; the command outcome is unknown.',
      );
    } finally {
      if (requestId != null) _pending.remove(requestId);
      _sending = false;
    }
  }

  Future<void> setDirectionLight({
    required String direction,
    required String light,
  }) => _sendCommand(TrafficLightCommand.set(direction, light));
  Future<void> setAllRed() => _sendCommand({'cmd': 'ALL_RED'});
  Future<void> setAutoMode({
    required int greenSec,
    required int yellowSec,
    required int allRedSec,
  }) => _sendCommand(
    TrafficLightCommand.automatic(
      greenSec: greenSec,
      yellowSec: yellowSec,
      allRedSec: allRedSec,
    ),
  );
  Future<void> setManualMode() => _sendCommand({'cmd': 'MANUAL'});
  Future<void> requestStatus() => _sendCommand({'cmd': 'STATUS'});

  void dispose() {
    if (_disposed) return;
    unawaited(stopAutoConnect());
    unawaited(disconnect());
    _disposed = true;
    unawaited(_statusController.close());
    unawaited(_connectionController.close());
  }
}
