import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../constants/colors.dart';
import '../../services/ble_traffic_service.dart';

class TrafficLightControlPage extends StatefulWidget {
  const TrafficLightControlPage({super.key});

  @override
  State<TrafficLightControlPage> createState() => _TrafficLightControlPageState();
}

class _TrafficLightControlPageState extends State<TrafficLightControlPage>
    with TickerProviderStateMixin {

  // ── State ──────────────────────────────────────────────────────────────────
  final _ble = BleTrafficService.instance;
  List<TrafficLightDevice> _devices = [];
  TrafficLightDevice?      _selected;
  TrafficLightStatus?      _status;

  Map<String, dynamic>?    _authStatus;
  bool _authChecking  = true;

  bool _scanning      = false;
  bool _connecting    = false;
  bool _sending       = false;

  // Auto-mode sliders
  double _greenSec  = 30;
  double _yellowSec = 5;
  double _redSec    = 30;
  bool   _autoMode  = false;

  StreamSubscription<List<TrafficLightDevice>>? _scanSub;
  StreamSubscription<TrafficLightStatus>?       _statusSub;

  // Glow animations
  late AnimationController _glowCtrl;
  late Animation<double>   _glowAnim;

  @override
  void initState() {
    super.initState();
    _checkAuthorization();

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _glowAnim = Tween(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );

    _statusSub = _ble.statusStream.listen((s) {
      if (mounted) setState(() => _status = s);
    });
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    _scanSub?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }

  // ── Authorization ──────────────────────────────────────────────────────────
  Future<void> _checkAuthorization() async {
    setState(() => _authChecking = true);
    final status = await _ble.checkUserAuthorization();
    if (mounted) {
      setState(() {
        _authStatus = status;
        _authChecking = false;
      });
    }
  }

  // ── Scanning ───────────────────────────────────────────────────────────────
  Future<void> _startScan() async {
    setState(() { _scanning = true; _devices = []; });
    _scanSub?.cancel();
    _scanSub = _ble.scan().listen(
      (list) { if (mounted) setState(() => _devices = list); },
      onDone: () { if (mounted) setState(() => _scanning = false); },
    );
  }

  Future<void> _stopScan() async {
    await _ble.stopScan();
    _scanSub?.cancel();
    setState(() => _scanning = false);
  }

  // ── Connection ─────────────────────────────────────────────────────────────
  Future<void> _connect(TrafficLightDevice dev) async {
    await _stopScan();
    setState(() { _connecting = true; _selected = dev; });
    try {
      await _ble.connect(dev.device);
      if (mounted) setState(() { _connecting = false; });
      _showSnack('✅ Connected & verified as Traffic Police!', AppColors.success);
    } catch (e) {
      if (mounted) setState(() { _connecting = false; _selected = null; });
      _showSnack('❌ ${e.toString()}', AppColors.primary);
    }
  }

  Future<void> _disconnect() async {
    await _ble.disconnect();
    if (mounted) setState(() { _selected = null; _status = null; _autoMode = false; });
  }

  // ── Commands ───────────────────────────────────────────────────────────────
  Future<void> _sendLight(Future<void> Function() cmd) async {
    setState(() => _sending = true);
    try {
      await cmd();
    } catch (e) {
      _showSnack('❌ ${e.toString()}', AppColors.primary);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _applyAutoMode() async {
    await _sendLight(() => _ble.setAutoMode(
      greenSec:  _greenSec.round(),
      yellowSec: _yellowSec.round(),
      redSec:    _redSec.round(),
    ));
    _showSnack('⚙️ Auto cycle mode active', AppColors.infoBlue);
  }

  // ── UI helpers ─────────────────────────────────────────────────────────────
  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins(color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_authChecking) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: Text(
            'Traffic Light Control',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final isAuthorized = _authStatus?['isAuthorized'] == true;
    if (!isAuthorized) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: Text(
            'Traffic Light Control',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: Colors.white),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              tooltip: 'Re-check Authorization',
              onPressed: _checkAuthorization,
            ),
          ],
        ),
        body: _buildUnauthorizedView(),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Traffic Light Control',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh Status',
            onPressed: _checkAuthorization,
          ),
          if (_ble.isConnected)
            IconButton(
              icon: const Icon(Icons.bluetooth_disabled_rounded, color: Colors.white),
              tooltip: 'Disconnect',
              onPressed: _disconnect,
            ),
        ],
      ),
      body: _ble.isConnected ? _buildControlPanel() : _buildScanPanel(),
    );
  }

  // ── Unauthorized View ──────────────────────────────────────────────────────
  Widget _buildUnauthorizedView() {
    final role = _authStatus?['role']?.toString() ?? 'user';
    final isPending = role == 'traffic_police' && _authStatus?['isVerified'] != true;
    final reason = _authStatus?['reason']?.toString() ?? 'Authorization required.';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isPending ? AppColors.warningLight : const Color(0xFFFFEBEE),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPending ? Icons.pending_actions_rounded : Icons.gavel_rounded,
                size: 64,
                color: isPending ? AppColors.warning : AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isPending ? 'Traffic Police Pending Approval' : 'Authorization Required',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              isPending
                  ? 'Your Traffic Police registration is currently under review by an administrator.\n\nOnce approved in the Admin Verification Dashboard, you will be authorized to connect and control traffic light signals.'
                  : 'Traffic light modification is restricted strictly to verified Traffic Police officers and system administrators.\n\nCurrent role: $role',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: AppColors.textGrey,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Text(
                reason,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isPending ? AppColors.warning : AppColors.primary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _checkAuthorization,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(
                  'Re-check Authorization',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isPending ? AppColors.warning : AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Scan panel ─────────────────────────────────────────────────────────────
  Widget _buildScanPanel() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Officer badge banner
          if (_authStatus != null) _OfficerBadgeBanner(authStatus: _authStatus!),
          const SizedBox(height: 14),

          // Security info banner
          _SecurityBanner(),
          const SizedBox(height: 20),

          // Scan button
          SizedBox(
            width: double.infinity,
            child: _scanning
                ? OutlinedButton.icon(
                    onPressed: _stopScan,
                    icon: const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    ),
                    label: Text('Scanning for Signal Devices… (tap to stop)',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: _startScan,
                    icon: const Icon(Icons.bluetooth_searching_rounded),
                    label: Text('Scan for ESP32 Traffic Light',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
          ),
          const SizedBox(height: 20),
          if (_devices.isNotEmpty) ...[
            Text('Nearby Signals',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textDark)),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: _devices.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _DeviceTile(
                  device: _devices[i],
                  isConnecting: _connecting && _selected?.device.remoteId == _devices[i].device.remoteId,
                  onTap: () => _connect(_devices[i]),
                ),
              ),
            ),
          ] else if (_scanning)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.bluetooth_searching_rounded, size: 64, color: AppColors.textLight),
                    const SizedBox(height: 16),
                    Text('Searching for ESP32 traffic signals nearby…',
                        style: GoogleFonts.poppins(color: AppColors.textGrey)),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.traffic_rounded, size: 72, color: AppColors.textLight),
                    const SizedBox(height: 16),
                    Text('No traffic light connected.\nTap Scan to locate your intersection signal.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(color: AppColors.textGrey, height: 1.5)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Control panel ──────────────────────────────────────────────────────────
  Widget _buildControlPanel() {
    final light = _status?.currentLight ?? 'red';
    final mode  = _status?.mode ?? 'manual';
    final uptime = _status?.uptime ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Officer badge banner
          if (_authStatus != null) _OfficerBadgeBanner(authStatus: _authStatus!),
          const SizedBox(height: 14),

          // Connection status bar
          _ConnectionStatusBar(
            deviceName: _selected?.name ?? 'ESP32 Signal',
            isAuthenticated: _ble.isAuthenticated,
            rssi: _selected?.rssi ?? 0,
            uptime: uptime,
          ),
          const SizedBox(height: 24),

          // Traffic light visual
          Center(child: _AnimatedTrafficLight(
            activeLight: light,
            glowAnim: _glowAnim,
          )),
          const SizedBox(height: 28),

          // Mode toggle
          _ModeToggleCard(
            isAuto: _autoMode,
            mode: mode,
            onToggle: (val) async {
              setState(() => _autoMode = val);
              if (!val) await _sendLight(_ble.setManualMode);
            },
          ),
          const SizedBox(height: 20),

          if (!_autoMode) ...[
            // Manual buttons
            Text('Traffic Police Manual Override',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textDark)),
            const SizedBox(height: 4),
            Text('Tap a signal state to immediately switch the physical ESP32 LED',
                style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textGrey)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _LightButton(
                  label: 'RED',
                  color: const Color(0xFFE53935),
                  icon: Icons.stop_circle_rounded,
                  active: light == 'red',
                  loading: _sending,
                  onTap: () => _sendLight(_ble.setRed),
                )),
                const SizedBox(width: 12),
                Expanded(child: _LightButton(
                  label: 'YELLOW',
                  color: const Color(0xFFFFC107),
                  icon: Icons.warning_amber_rounded,
                  active: light == 'yellow',
                  loading: _sending,
                  onTap: () => _sendLight(_ble.setYellow),
                )),
                const SizedBox(width: 12),
                Expanded(child: _LightButton(
                  label: 'GREEN',
                  color: const Color(0xFF43A047),
                  icon: Icons.play_circle_rounded,
                  active: light == 'green',
                  loading: _sending,
                  onTap: () => _sendLight(_ble.setGreen),
                )),
              ],
            ),
          ] else ...[
            // Auto mode sliders
            Text('Auto Cycle Timing Configuration',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textDark)),
            const SizedBox(height: 4),
            Text('Set phase durations then tap Apply to send to ESP32',
                style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textGrey)),
            const SizedBox(height: 16),
            _TimingSlider(label: 'Green', value: _greenSec,  color: const Color(0xFF43A047),
                onChanged: (v) => setState(() => _greenSec  = v)),
            _TimingSlider(label: 'Yellow', value: _yellowSec, color: const Color(0xFFFFC107),
                onChanged: (v) => setState(() => _yellowSec = v)),
            _TimingSlider(label: 'Red',   value: _redSec,    color: const Color(0xFFE53935),
                onChanged: (v) => setState(() => _redSec    = v)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _sending ? null : _applyAutoMode,
                icon: _sending
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle_rounded),
                label: Text('Apply Timing to ESP32',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.infoBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],

          const SizedBox(height: 28),
          // Security details
          _SecurityDetailsCard(isAuthenticated: _ble.isAuthenticated),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _OfficerBadgeBanner extends StatelessWidget {
  final Map<String, dynamic> authStatus;
  const _OfficerBadgeBanner({required this.authStatus});

  @override
  Widget build(BuildContext context) {
    final role = authStatus['role']?.toString() ?? 'traffic_police';
    final name = authStatus['name']?.toString() ?? 'Officer';
    final policeId = authStatus['policeId']?.toString() ?? '';
    final intersection = authStatus['intersection']?.toString() ?? '';

    final isTrafficPolice = role == 'traffic_police';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF43A047).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.local_police_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isTrafficPolice ? 'Traffic Police Officer' : 'Administrator',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: const Color(0xFF1B5E20),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E7D32),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'AUTHORIZED',
                        style: GoogleFonts.poppins(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  '$name ${policeId.isNotEmpty ? '• ID: $policeId' : ''} ${intersection.isNotEmpty ? '• $intersection' : ''}',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: const Color(0xFF2E7D32),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.infoBlue.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.security_rounded, color: AppColors.infoBlue, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Traffic Police Controlled Signal',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700,
                        fontSize: 13, color: AppColors.infoBlue)),
                Text('Only verified Traffic Police & Admins can issue BLE commands. HMAC-SHA256 signature + replay protection.',
                    style: GoogleFonts.poppins(fontSize: 11, color: const Color(0xFF1565C0), height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final TrafficLightDevice device;
  final bool               isConnecting;
  final VoidCallback       onTap;
  const _DeviceTile({required this.device, required this.isConnecting, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isConnecting ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFE3F2FD), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.bluetooth_rounded, color: AppColors.infoBlue, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(device.name, style: GoogleFonts.poppins(fontWeight: FontWeight.w600,
                      fontSize: 14, color: AppColors.textDark)),
                  Text('RSSI: ${device.rssi} dBm  •  ${device.device.remoteId}',
                      style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textGrey)),
                ],
              ),
            ),
            if (isConnecting)
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            else
              const Icon(Icons.chevron_right_rounded, color: AppColors.textLight),
          ],
        ),
      ),
    );
  }
}

class _ConnectionStatusBar extends StatelessWidget {
  final String deviceName;
  final bool   isAuthenticated;
  final int    rssi;
  final int    uptime;
  const _ConnectionStatusBar({
    required this.deviceName, required this.isAuthenticated,
    required this.rssi, required this.uptime,
  });

  @override
  Widget build(BuildContext context) {
    final minutes = uptime ~/ 60;
    final seconds = uptime % 60;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.bluetooth_connected_rounded, color: AppColors.infoBlue, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(deviceName, style: GoogleFonts.poppins(fontWeight: FontWeight.w600,
                    fontSize: 13, color: AppColors.textDark)),
                Text('Uptime: ${minutes}m ${seconds}s  •  RSSI: $rssi dBm',
                    style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textGrey)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isAuthenticated ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(isAuthenticated ? Icons.lock_rounded : Icons.lock_open_rounded,
                    size: 12, color: isAuthenticated ? AppColors.success : AppColors.primary),
                const SizedBox(width: 4),
                Text(isAuthenticated ? 'Officer Auth' : 'Auth…',
                    style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600,
                        color: isAuthenticated ? AppColors.success : AppColors.primary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedTrafficLight extends StatelessWidget {
  final String          activeLight;
  final Animation<double> glowAnim;
  const _AnimatedTrafficLight({required this.activeLight, required this.glowAnim});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: glowAnim,
      builder: (context, child) => Container(
        width: 90,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LightBulb(color: const Color(0xFFE53935), active: activeLight == 'red',   glow: glowAnim.value),
            const SizedBox(height: 14),
            _LightBulb(color: const Color(0xFFFFC107), active: activeLight == 'yellow', glow: glowAnim.value),
            const SizedBox(height: 14),
            _LightBulb(color: const Color(0xFF43A047), active: activeLight == 'green',  glow: glowAnim.value),
          ],
        ),
      ),
    );
  }
}

class _LightBulb extends StatelessWidget {
  final Color  color;
  final bool   active;
  final double glow;
  const _LightBulb({required this.color, required this.active, required this.glow});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52, height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? color : color.withValues(alpha: 0.2),
        boxShadow: active ? [
          BoxShadow(color: color.withValues(alpha: glow * 0.8), blurRadius: 20 * glow, spreadRadius: 4 * glow),
        ] : [],
      ),
    );
  }
}

class _ModeToggleCard extends StatelessWidget {
  final bool     isAuto;
  final String   mode;
  final ValueChanged<bool> onToggle;
  const _ModeToggleCard({required this.isAuto, required this.mode, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_rounded, color: AppColors.accentOrange, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Auto Cycle Mode', style: GoogleFonts.poppins(fontWeight: FontWeight.w600,
                    fontSize: 14, color: AppColors.textDark)),
                Text('ESP32 cycles lights automatically',
                    style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textGrey)),
              ],
            ),
          ),
          Switch.adaptive(
            value: isAuto,
            onChanged: onToggle,
            activeThumbColor: AppColors.infoBlue,
            activeTrackColor: AppColors.infoBlue.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }
}

class _LightButton extends StatelessWidget {
  final String      label;
  final Color       color;
  final IconData    icon;
  final bool        active;
  final bool        loading;
  final VoidCallback onTap;
  const _LightButton({
    required this.label, required this.color, required this.icon,
    required this.active, required this.loading, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: active ? color : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? color : color.withValues(alpha: 0.3), width: 2),
          boxShadow: active ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))] : [],
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: active ? Colors.white : color),
            const SizedBox(height: 6),
            Text(label, style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700, fontSize: 13,
              color: active ? Colors.white : color,
            )),
          ],
        ),
      ),
    );
  }
}

class _TimingSlider extends StatelessWidget {
  final String        label;
  final double        value;
  final Color         color;
  final ValueChanged<double> onChanged;
  const _TimingSlider({required this.label, required this.value, required this.color, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  Container(width: 12, height: 12,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Text('$label Phase', style: GoogleFonts.poppins(fontWeight: FontWeight.w600,
                      fontSize: 13, color: AppColors.textDark)),
                ]),
                Text('${value.round()}s', style: GoogleFonts.poppins(fontWeight: FontWeight.w700,
                    fontSize: 14, color: color)),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: color,
                thumbColor: color,
                inactiveTrackColor: color.withValues(alpha: 0.2),
                overlayColor: color.withValues(alpha: 0.1),
              ),
              child: Slider(value: value, min: 5, max: 120, divisions: 23, onChanged: onChanged),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecurityDetailsCard extends StatelessWidget {
  final bool isAuthenticated;
  const _SecurityDetailsCard({required this.isAuthenticated});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.security_rounded, size: 18, color: AppColors.infoBlue),
            const SizedBox(width: 8),
            Text('Authorization & Security Info', style: GoogleFonts.poppins(fontWeight: FontWeight.w700,
                fontSize: 13, color: AppColors.textDark)),
          ]),
          const SizedBox(height: 12),
          ...[
            ('Required Role',     'Traffic Police / Admin only', AppColors.infoBlue),
            ('Verification',      'Admin verified credentials', AppColors.infoBlue),
            ('Session Handshake', isAuthenticated ? 'HMAC-SHA256 Challenge-Response ✓' : 'Pending connection…',
                isAuthenticated ? AppColors.success : AppColors.warning),
            ('Replay Window',     'Timestamp ±30s freshness window', AppColors.infoBlue),
            ('Command Signing',   'HMAC-SHA256 per command packet', AppColors.infoBlue),
          ].map((row) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Text('${row.$1}: ', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textGrey)),
                Expanded(
                  child: Text(row.$2, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: row.$3)),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}
