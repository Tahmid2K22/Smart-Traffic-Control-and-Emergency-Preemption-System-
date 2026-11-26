import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'user_service.dart';

/// Registers the signed-in officer's FCM token for escape-request pushes.
/// Token map: Supabase `users.fcm_tokens` = `{token: {platform, updatedAt}}`.
class PushNotificationService {
  PushNotificationService({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  /// Lazily created on supported platforms.
  FirebaseMessaging? _messaging;
  final FirebaseAuth _auth;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  bool _registering = false;

  /// FCM only on Android/iOS; web/desktop skip (alerts via in-app stream).
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Requests permission and stores/refreshes the FCM token. Safe from initState; failures non-fatal.
  Future<void> registerForCurrentUser() async {
    if (!isSupported) return;
    if (_registering) return;
    _registering = true;
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      final messaging = _messaging ??= FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final token = await messaging.getToken();
      if (token != null) await _saveToken(user.uid, token);
      _tokenRefreshSub?.cancel();
      _tokenRefreshSub = messaging.onTokenRefresh.listen(
        (token) => _saveToken(user.uid, token),
        onError: (Object _) {}, // token stays stale; next launch re-registers
      );
      _foregroundSub?.cancel();
      // Foreground: tray only when backgrounded; officer page shows alerts. No-op log listener.
      _foregroundSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[push] foreground message: '
              '${message.notification?.title ?? ''} '
              '${message.notification?.body ?? ''}');
        }
      });
    } catch (error) {
      // Plugin/permission errors must not take down the officer page.
      if (kDebugMode) {
        // ignore: avoid_print
        print('[push] registration failed: $error');
      }
    } finally {
      _registering = false;
    }
  }

  Future<void> _saveToken(String uid, String token) async {
    try {
      final platform = defaultTargetPlatform == TargetPlatform.android
          ? 'android'
          : 'ios';
      await UserService.instance.addFcmToken(uid, token, platform: platform);
    } catch (_) {
      // Non-fatal: the Cloud Function will simply find no token yet.
    }
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    _foregroundSub?.cancel();
    _foregroundSub = null;
  }
}
