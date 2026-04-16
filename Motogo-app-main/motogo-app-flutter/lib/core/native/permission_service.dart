import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Centralized permission service — requests ALL permissions at once
/// during onboarding so the user is never asked again at point-of-use.
/// Revocation is available from the profile settings screen.
class PermissionService {
  PermissionService._();

  static const _grantedKey = 'mg_perms_granted';

  /// All runtime permissions the app needs.
  static const _allPermissions = [
    Permission.location,
    Permission.camera,
    Permission.microphone,
    Permission.notification,
    Permission.photos, // gallery on iOS / READ_MEDIA_IMAGES on Android 13+
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
      PermissionInfo(
        key: 'location',
        icon: '📍',
        title: 'Poloha (GPS)',
        desc: 'Navigace, sdílení pozice při poruše',
        granted: await Permission.location.isGranted,
      ),
      PermissionInfo(
        key: 'camera',
        icon: '📷',
        title: 'Fotoaparát',
        desc: 'Skenování dokladů, dokumentace škod',
        granted: await Permission.camera.isGranted,
      ),
      PermissionInfo(
        key: 'microphone',
        icon: '🎤',
        title: 'Mikrofon',
        desc: 'Hlasové dotazy pro AI asistenta',
        granted: await Permission.microphone.isGranted,
      ),
      PermissionInfo(
        key: 'notifications',
        icon: '🔔',
        title: 'Oznámení',
        desc: 'SOS aktualizace, zprávy, stav rezervací',
        granted: await Permission.notification.isGranted,
      ),
      PermissionInfo(
        key: 'photos',
        icon: '🖼️',
        title: 'Galerie / Fotky',
        desc: 'Nahrávání fotek faktur a dokladů',
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
