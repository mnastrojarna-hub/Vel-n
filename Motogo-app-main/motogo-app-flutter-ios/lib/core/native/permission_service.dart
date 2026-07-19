import 'dart:io' show Platform;

import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../supabase_client.dart';

/// Centralized permission service — requests ALL permissions at once
/// during onboarding so the user is never asked again at point-of-use.
/// Revocation is available from the profile settings screen.
class PermissionService {
  PermissionService._();

  static const _grantedKey = 'mg_perms_granted';

  /// All runtime permissions the app needs.
  /// Android NEŽÁDÁ Permission.photos — READ_MEDIA_IMAGES je z manifestu
  /// odstraněno (Google Play policy: občasný výběr fotek = systémový Photo
  /// Picker bez oprávnění; image_picker ho na Androidu 13+ používá sám).
  /// Request na nedeklarované oprávnění by se jen tiše zamítl a v nastavení
  /// by viselo věčně "neuděleno". iOS galerii (Permission.photos) potřebuje.
  static List<Permission> get _allPermissions => [
        Permission.location,
        Permission.camera,
        Permission.notification,
        if (Platform.isIOS) Permission.photos,
      ];

  /// Request ALL permissions at once. Called from onboarding overlay.
  /// Sets the permissions in system settings so point-of-use never re-asks.
  static Future<void> requestAll() async {
    // Request all permissions via permission_handler (shows system dialogs)
    await _allPermissions.request();

    // Firebase messaging needs its own request for iOS token registration
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        announcement: true,
        provisional: false,
      );
    } catch (_) {}

    // Mark as granted in preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_grantedKey, true);

    // Mirror the resulting grants to the customer's profile (best-effort).
    await reportToProfile();
  }

  /// Report current OS permission grants to the customer's profile so the Velín
  /// customer detail can mirror them. Device-level, informational, best-effort.
  /// No-op when not logged in.
  static Future<void> reportToProfile() async {
    final user = MotoGoSupabase.currentUser;
    if (user == null) return;
    try {
      await MotoGoSupabase.client.from('profiles').update({
        'app_permissions': {
          'location': await Permission.location.isGranted,
          'camera': await Permission.camera.isGranted,
          'notification': await Permission.notification.isGranted,
          'photos': await Permission.photos.isGranted,
          'platform': Platform.isIOS ? 'ios' : 'android',
          'reported_at': DateTime.now().toUtc().toIso8601String(),
        },
      }).eq('id', user.id);
    } catch (_) {/* informativní — selhání neblokuje appku */}
  }

  /// Check if all permissions were already granted at startup.
  static Future<bool> allGranted() async {
    for (final perm in _allPermissions) {
      if (!await perm.isGranted) return false;
    }
    return true;
  }

  /// Get status of each permission for the settings screen.
  static Future<List<PermissionInfo>> getStatuses() async {
    return [
      // title/desc hold i18n keys (resolved via t(context).tr at display sites).
      PermissionInfo(
        key: 'location',
        icon: '📍',
        title: 'permLocationTitle',
        desc: 'permLocationDesc',
        granted: await Permission.location.isGranted,
      ),
      PermissionInfo(
        key: 'camera',
        icon: '📷',
        title: 'permCameraTitle',
        desc: 'permCameraDesc',
        granted: await Permission.camera.isGranted,
      ),
      PermissionInfo(
        key: 'notifications',
        icon: '🔔',
        title: 'permNotifTitle',
        desc: 'permNotifDesc',
        granted: await Permission.notification.isGranted,
      ),
      // Android: fotky jdou přes systémový Photo Picker (bez oprávnění),
      // řádek by ukazoval věčné "neuděleno" — zobrazujeme jen na iOS.
      if (Platform.isIOS)
        PermissionInfo(
          key: 'photos',
          icon: '🖼️',
          title: 'permPhotosTitle',
          desc: 'permPhotosDesc',
          granted: await Permission.photos.isGranted,
        ),
    ];
  }

  /// Open system app settings so user can revoke/grant permissions.
  static Future<void> openSettings() async {
    await openAppSettings();
  }

  /// Revoke consent flag (user wants to re-manage permissions).
  /// Actual OS permissions must be revoked in system settings.
  static Future<void> revokeConsent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_grantedKey, false);
  }

  /// Check if user already went through the permission flow.
  static Future<bool> wasShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_grantedKey) == true;
  }
}

/// Permission status info for UI display.
class PermissionInfo {
  final String key;
  final String icon;
  final String title;
  final String desc;
  final bool granted;

  const PermissionInfo({
    required this.key,
    required this.icon,
    required this.title,
    required this.desc,
    required this.granted,
  });
}
