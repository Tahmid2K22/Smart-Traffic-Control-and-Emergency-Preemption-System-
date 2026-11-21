import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Registers the signed-in officer's FCM token on their user document so the
/// `notifyEmergencyEscape` Cloud Function can push escape requests to them.
///
/// Token map shape (`users/{uid}.fcmTokens`):
///   `{ '<token>': { 'platform': 'android'|'ios', 'updatedAt': <ts> } }`
///
/// Push is Android/iOS only — on desktop/web this service is a no-op so the
/// app never touches an unsupported plugin.
class PushNotificationService {
  PushNotificationService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  /// Lazily created only on supported platforms (see [isSupported]).
  FirebaseMessaging? _messaging;
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  StreamSubscription<String>? _tokenRefreshSub;
  bool _registering = false;

  /// FCM messaging is only wired for Android and iOS. Web/desktop builds skip
  /// it entirely (the officer still receives alerts through the in-app
  /// Firestore stream).
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Requests notification permission and stores/refreshes the FCM token for
  /// the signed-in user. Safe to call from a page's initState; failures are
  /// non-fatal (the officer still sees alerts via the in-app stream).
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
      // Foreground display: system-tray notifications only appear when the
      // app is backgrounded; foreground alerts are already shown by the
      // officer page's Firestore stream. Keep a no-op logging listener.
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[push] foreground message: '
              '${message.notification?.title ?? ''} '
              '${message.notification?.body ?? ''}');
        }
      });
    } catch (error) {
      // MissingPluginException / UnimplementedError / permission errors must
      // never take down the officer page.
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
      await _firestore.collection('users').doc(uid).set({
        'fcmTokens': {
          token: {
            'platform': defaultTargetPlatform == TargetPlatform.android
                ? 'android'
                : 'ios',
            'updatedAt': FieldValue.serverTimestamp(),
          },
        },
      }, SetOptions(merge: true));
    } catch (_) {
      // Non-fatal: the Cloud Function will simply find no token yet.
    }
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
  }
}
