import 'dart:io';

import 'package:dating_app/core/services/aws_client.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Top-level background handler — required by firebase_messaging to be a
/// top-level (or static) function. We don't need to do work here for tour-ready
/// notifications (the OS displays the `notification` payload itself); it just
/// has to exist so background delivery is wired up.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Intentionally no-op: the push carries a `notification` block that the OS
  // renders without app code. Data-only handling can be added here later.
}

/// Registers the device for push notifications and keeps the backend's copy of
/// the FCM token in sync, so the server-side tour poller can notify the owner
/// when their 3D apartment tour finishes processing (~1–2h after upload, when
/// the app is usually closed).
///
/// Everything is fail-soft: a user who declines permission, an unconfigured
/// backend, or a missing APNs token never breaks app startup.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  bool _wired = false;
  String? _lastRegisteredToken;

  /// Callback invoked when a notification arrives while the app is foregrounded,
  /// so the UI can surface an in-app banner. Set by the app shell.
  void Function(RemoteMessage message)? onForegroundMessage;

  /// Callback invoked when the user taps a notification that opened the app.
  void Function(RemoteMessage message)? onNotificationTap;

  /// Wires message handlers once. Safe to call before login.
  Future<void> initialize() async {
    if (_wired) return;
    _wired = true;
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      FirebaseMessaging.onMessage.listen((message) {
        onForegroundMessage?.call(message);
      });
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        onNotificationTap?.call(message);
      });
      // App launched from a terminated state by tapping a notification.
      final initial = await _messaging.getInitialMessage();
      if (initial != null) onNotificationTap?.call(initial);

      _messaging.onTokenRefresh.listen((token) {
        _registerToken(token);
      });
    } catch (error) {
      if (kDebugMode) debugPrint('PushNotificationService.initialize: $error');
    }
  }

  /// Requests permission (if needed) and registers the current device token
  /// with the backend. Call after the user is authenticated.
  Future<void> registerForUser() async {
    if (!AwsApiClient.instance.isConfigured) return;
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }
      // On iOS the APNs token must be available before the FCM token resolves.
      // On a FRESH install it can take several seconds to provision, so poll
      // instead of giving up on the first null — the old behavior silently
      // skipped registration forever whenever APNs wasn't ready at that exact
      // instant (relying on onTokenRefresh, which never fires if getToken() is
      // never reached). This is the #1 reason a reinstalled device got no push.
      if (Platform.isIOS) {
        String? apns;
        for (var i = 0; i < 12; i++) {
          apns = await _messaging.getAPNSToken();
          if (apns != null) break;
          await Future<void>.delayed(const Duration(milliseconds: 1500));
        }
        if (apns == null) return; // gave up after ~18s; onTokenRefresh may catch it later
      }
      final token = await _messaging.getToken();
      if (token != null) await _registerToken(token);
    } catch (error) {
      if (kDebugMode) debugPrint('PushNotificationService.registerForUser: $error');
    }
  }

  Future<void> _registerToken(String token) async {
    if (token == _lastRegisteredToken) return;
    if (!AwsApiClient.instance.isConfigured) return;
    try {
      await AwsApiClient.instance.post('/notifications/register-token', {
        'token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
      });
      _lastRegisteredToken = token;
    } catch (error) {
      if (kDebugMode) debugPrint('PushNotificationService._registerToken: $error');
    }
  }
}
