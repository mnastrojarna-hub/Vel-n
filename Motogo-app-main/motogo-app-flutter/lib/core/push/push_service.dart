import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import '../../core/supabase_client.dart';

/// Push notification service — mirrors native-bridge.js push token registration.
/// Registers FCM token to push_tokens table, handles foreground/background.
/// Permission is granted at onboarding — initialize() skips re-request.
class PushService {
  PushService._();

  static final _messaging = FirebaseMessaging.instance;

  /// Initialize push notifications — call after Firebase.initializeApp().
  /// Does NOT re-request permission — already granted at onboarding.
  static Future<void> initialize() async {
    // Check if notification permission was already granted at onboarding
    final notifGranted = await ph.Permission.notification.isGranted;
    if (!notifGranted) return;

    // Get and register token
    final token = await _messaging.getToken();
    if (token != null) await _registerToken(token);

    // Listen for token refresh
    _messaging.onTokenRefresh.listen(_registerToken);

    // Foreground messages
    FirebaseMessaging.onMessage.listen(_handleForeground);

    // Background message tap
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

    // Check for initial message (app opened from terminated state)
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _handleMessageTap(initial);
  }

  /// Register FCM token to push_tokens table.
  static Future<void> _registerToken(String token) async {
    final user = MotoGoSupabase.currentUser;
    if (user == null) return;

    try {
      await MotoGoSupabase.client.from('push_tokens').upsert({
        'user_id': user.id,
        'token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'active': true,
      }, onConflict: 'token');
    } catch (_) {}
  }

  /// Handle foreground notification — show in-app toast/banner.
  static void _handleForeground(RemoteMessage message) {
    final title = message.notification?.title ?? 'MotoGo24';
    final body = message.notification?.body ?? '';
    // The app will handle display via notification_handler.dart
    _onNotificationReceived?.call(title, body, message.data);
  }

  /// Handle notification tap (app was in background/terminated).
  static void _handleMessageTap(RemoteMessage message) {
    final data = message.data;
    // Route based on data payload
    _onNotificationTap?.call(data);
  }

  /// Callbacks for notification handling (set by notification_handler.dart).
  static void Function(String title, String body, Map<String, dynamic> data)? _onNotificationReceived;
  static void Function(Map<String, dynamic> data)? _onNotificationTap;

  static void setHandlers({
    void Function(String, String, Map<String, dynamic>)? onReceived,
    void Function(Map<String, dynamic>)? onTap,
  }) {
    _onNotificationReceived = onReceived;
    _onNotificationTap = onTap;
  }
}
