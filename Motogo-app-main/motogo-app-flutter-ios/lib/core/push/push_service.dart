import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:permission_handler/permission_handler.dart' as ph;
import '../../core/supabase_client.dart';

/// Push notification service — mirrors native-bridge.js push token registration.
/// Registers FCM token to push_tokens table, handles foreground/background.
/// Permission is granted at onboarding — initialize() skips re-request.
class PushService {
  PushService._();

  static final _messaging = FirebaseMessaging.instance;

  /// Nativní kanál (Android MainActivity / iOS AppDelegate) pro úklid lišty.
  static const _tray = MethodChannel('cz.motogo24/notifications');

  /// Smaže doručené notifikace appky z lišty / Centra oznámení a vynuluje
  /// odznak na ikoně — otevření appky = zákazník upozornění viděl (obsah zůstává
  /// ve Zprávách). Probíhající notifikace (záznam jízdy) Android nechá. Chyby
  /// (build bez kanálu, jiná platforma) tiše ignoruje.
  static Future<void> clearDelivered() async {
    try {
      await _tray.invokeMethod<void>('clearAll');
    } catch (_) {}
  }

  static bool _listening = false;
  static bool _initialChecked = false;
  static String? _registeredKey;
  static Map<String, dynamic>? _pendingTap;

  /// Initialize push notifications — call after Firebase.initializeApp().
  /// Does NOT re-request permission — already granted at onboarding.
  ///
  /// Idempotentní (2026-10-16): volá se při startu, po udělení oprávnění v
  /// úvodu / na obrazovce Oprávnění, po přihlášení a při návratu do appky.
  /// Dřív běžela jen jednou při startu — PŘED úvodní žádostí o oprávnění a před
  /// přihlášením — takže na nové instalaci se token nezaregistroval a kódy ke
  /// dveřím ani odpovědi na SOS do restartu appky nechodily.
  static Future<void> initialize() async {
    // Check if notification permission was already granted at onboarding
    final notifGranted = await ph.Permission.notification.isGranted;
    if (!notifGranted) return;

    if (!_listening) {
      _listening = true;
      // Listen for token refresh
      _messaging.onTokenRefresh.listen(_registerToken);
      // Foreground messages
      FirebaseMessaging.onMessage.listen(_handleForeground);
      // Background message tap
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);
    }

    // Check for initial message (app opened from terminated state) — jen
    // jednou; když handler ještě není nastavený, počká v [_pendingTap].
    if (!_initialChecked) {
      _initialChecked = true;
      final initial = await _messaging.getInitialMessage();
      if (initial != null) _handleMessageTap(initial);
    }

    // Get and register token (i po přihlášení — dřív bez uživatele nic)
    final token = await _messaging.getToken();
    if (token != null) await _registerToken(token);
  }

  /// Register FCM token to push_tokens table.
  static Future<void> _registerToken(String token) async {
    final user = MotoGoSupabase.currentUser;
    if (user == null) return;
    final key = '${user.id}|$token';
    if (key == _registeredKey) return; // už zapsáno (návrat do appky)

    try {
      await MotoGoSupabase.client.from('push_tokens').upsert({
        'user_id': user.id,
        'token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'active': true,
      }, onConflict: 'token');
      _registeredKey = key;
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
    // Route based on data payload; bez handleru (studený start) počkat.
    final onTap = _onNotificationTap;
    if (onTap == null) {
      _pendingTap = data;
    } else {
      onTap(data);
    }
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
    final pending = _pendingTap;
    if (pending != null && onTap != null) {
      _pendingTap = null;
      onTap(pending);
    }
  }
}
