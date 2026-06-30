import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_client.dart';

/// Installation analytics — přesné počítání instalací / aktivních zařízení /
/// uživatelů appky, NEZÁVISLE na souhlasu s push notifikacemi.
///
/// Klíčová myšlenka: stabilní, APPKOU vygenerované náhodné UUID (NE hardwarový
/// identifikátor — Google Play safe) uložené v secure storage identifikuje
/// JEDNU instalaci. Lehký „heartbeat" upsertne jeden řádek do
/// `app_installations` s aktuálním uživatelem, platformou, verzí appky, stavem
/// pushů a `last_seen_at`. Z toho Velín počítá DAU/WAU/MAU i počet instalací.
///
/// Nikdy neblokuje UI, nikdy nevyhazuje výjimku — analytika nesmí shodit appku.
/// Stejný defenzivní vzor jako [CrashReportService].
class InstallationService {
  InstallationService._();

  static const _storage = FlutterSecureStorage();
  static const _deviceIdKey = 'mg_device_id';

  static String? _deviceId;
  static DateTime? _lastBeat;

  /// Throttle: nejvýše jeden heartbeat za toto okno (proti spamu při resume).
  static const _throttle = Duration(hours: 12);

  /// Get-or-create stabilního per-install device id (náhodné UUID v4).
  ///
  /// Zdroj pravdy je běžné [SharedPreferences] — to PŘEŽIJE aktualizaci buildu
  /// (přes Google Play i ručně) a maže se až při odinstalaci. Install id NENÍ
  /// tajemství (jen anonymní analytický identifikátor), takže secure storage
  /// nepotřebujeme — a vyhneme se tím tomu, že Android Keystore po aktualizaci
  /// občas hodnotu nepřečte a appka by vygenerovala nové UUID → falešné „nové
  /// aktivní zařízení" ve Velíně. Staré instalace migrujeme ze secure storage.
  static Future<String> _getDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1) Durable id (běžné updaty appky čtou odtud → stejné zařízení).
      final fromPrefs = prefs.getString(_deviceIdKey);
      if (fromPrefs != null && fromPrefs.isNotEmpty) {
        _deviceId = fromPrefs;
        return fromPrefs;
      }

      // 2) Migrace z původní secure storage (instalace z prvních buildů).
      String? id;
      try {
        id = await _storage.read(key: _deviceIdKey);
      } catch (_) {/* po updatu může selhat — ignoruj a vygeneruj níž */}
      if (id == null || id.isEmpty) id = _randomUuidV4();

      // Ulož durably; best-effort zrcadlo i do secure storage (zpětná kompat.).
      await prefs.setString(_deviceIdKey, id);
      try {
        await _storage.write(key: _deviceIdKey, value: id);
      } catch (_) {/* ignore */}

      _deviceId = id;
      return id;
    } catch (_) {
      // I prefs selhalo → efemérní id (aspoň session se započítá).
      _deviceId ??= _randomUuidV4();
      return _deviceId!;
    }
  }

  /// Zaznamená/obnoví tuto instalaci. Bezpečné volat často (throttle 12 h).
  /// No-op když není přihlášený uživatel (instalace se váže k účtu).
  static Future<void> beat() async {
    try {
      final user = MotoGoSupabase.currentUser;
      if (user == null) return;

      final now = DateTime.now();
      if (_lastBeat != null && now.difference(_lastBeat!) < _throttle) return;
      _lastBeat = now;

      final deviceId = await _getDeviceId();

      var appVersion = 'unknown';
      try {
        final info = await PackageInfo.fromPlatform();
        appVersion = '${info.version}+${info.buildNumber}';
      } catch (_) {/* ignore */}

      var pushEnabled = false;
      try {
        pushEnabled = await ph.Permission.notification.isGranted;
      } catch (_) {/* ignore */}

      await MotoGoSupabase.client.from('app_installations').upsert({
        'device_id': deviceId,
        'user_id': user.id,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'app_version': appVersion,
        'push_enabled': pushEnabled,
        'last_seen_at': now.toUtc().toIso8601String(),
      }, onConflict: 'device_id');
    } catch (_) {
      // Analytika nikdy nesmí shodit appku.
      _lastBeat = null; // ať příští pokus není zablokovaný throttle po chybě
    }
  }

  /// RFC 4122 v4 UUID bez externí závislosti (Random.secure).
  static String _randomUuidV4() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // verze 4
    b[8] = (b[8] & 0x3f) | 0x80; // varianta 10xx
    final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
