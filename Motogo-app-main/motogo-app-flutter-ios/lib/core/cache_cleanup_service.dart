import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Automatic cache & temp cleanup.
///
/// Two entry points:
///  * [run] — light safety-net cleanup called on every startup / background
///    (image cache + temp files + transient prefs).
///  * [purgeIfUpdated] — detects an app **update** (version+build changed since
///    the last run) and, on change, wipes *every* on-disk cache so no stale UI
///    or data from the previous build can survive. This is what guarantees
///    that after a Google Play update the app never shows the previous version.
///
/// Both preserve the login session (Supabase), biometric credentials
/// (FlutterSecureStorage) and essential user preferences — the user stays
/// logged in across updates.
class CacheCleanupService {
  /// SharedPreferences key storing the last app `version+build` we ran with.
  /// Used to detect updates. MUST survive cleanup (see [_preserveKeys]).
  static const _versionKey = 'mg_app_version';

  /// SharedPreferences keys that MUST survive any cleanup.
  static const _preserveKeys = <String>{
    'mg_bio_enabled', // biometric login toggle
    'mg_saved_email', // login email pre-fill
    'mg_locale', // selected language (overlay)
    'mg_language', // selected language (i18n)
    'mg_perms_shown', // permission overlay shown
    'mg_active_ride', // rozjetá navigace trasy (ruší se jen křížkem)
    'mg_ride_history', // historie jízd (Moje zážitky → Historie)
    _versionKey, // app version marker (update detection)
  };

  /// SharedPreferences key prefixes that MUST survive — the login session is
  /// persisted by supabase_flutter under these keys, so wiping them would log
  /// the user out on every cleanup / update.
  static const _preservePrefixes = <String>['supabase', 'sb-'];

  /// True if [key] must be kept during cleanup.
  static bool _keep(String key) {
    if (_preserveKeys.contains(key)) return true;
    for (final prefix in _preservePrefixes) {
      if (key.startsWith(prefix)) return true;
    }
    return false;
  }

  /// Light cleanup — safe to call from lifecycle or startup.
  static Future<void> run() async {
    await Future.wait([
      _clearImageCache(),
      _clearTempFiles(),
      _clearTransientPrefs(),
    ]);
  }

  /// Detect an app update and, if the running `version+build` differs from the
  /// last recorded one, perform a FULL purge of every on-disk cache.
  ///
  /// Call this once at startup **before** Supabase.initialize so the cleaned
  /// state is in place before any image / network data is loaded.
  /// Returns `true` when a purge actually ran.
  static Future<bool> purgeIfUpdated() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final current = '${info.version}+${info.buildNumber}';

      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString(_versionKey);

      // Same build → nothing to do.
      if (last == current) return false;

      // Fresh install (last == null) or an update → wipe everything stale.
      await _fullPurge();

      // Re-stamp the current build (the purge cleared transient prefs).
      final prefs2 = await SharedPreferences.getInstance();
      await prefs2.setString(_versionKey, current);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Wipe every on-disk cache the app can produce. Login session, biometrics
  /// and language preferences are preserved (see [_keep]).
  static Future<void> _fullPurge() async {
    await _clearImageCache();
    await _clearCacheManager();
    await _clearCacheDirs();
    await _clearTempFiles();
    await _clearTransientPrefs();
  }

  /// Clear Flutter's in-memory image cache + painting bindings.
  static Future<void> _clearImageCache() async {
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}
  }

  /// Empty the `cached_network_image` disk cache (flutter_cache_manager).
  /// This is the cache most likely to keep showing "the previous version"
  /// (old logos, banners, moto photos) after an update.
  static Future<void> _clearCacheManager() async {
    try {
      await DefaultCacheManager().emptyCache();
    } catch (_) {}
  }

  /// Recursively wipe the platform temp + application cache directories.
  /// On Android this also covers the WebView HTTP cache (lives under cacheDir).
  static Future<void> _clearCacheDirs() async {
    final dirs = <Directory>[];
    try {
      dirs.add(await getTemporaryDirectory());
    } catch (_) {}
    try {
      dirs.add(await getApplicationCacheDirectory());
    } catch (_) {}
    for (final dir in dirs) {
      await _wipeDirContents(dir);
    }
  }

  /// Delete every entry inside [dir] (but keep the directory itself).
  static Future<void> _wipeDirContents(Directory dir) async {
    try {
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {
          // Skip entries locked by the OS / other processes.
        }
      }
    } catch (_) {}
  }

  /// Delete temp directory contents (cached images, HTTP cache, etc.).
  static Future<void> _clearTempFiles() async {
    try {
      final tempDir = Directory.systemTemp;
      if (!await tempDir.exists()) return;

      await for (final entity in tempDir.list()) {
        try {
          if (entity is File) {
            await entity.delete();
          } else if (entity is Directory) {
            await entity.delete(recursive: true);
          }
        } catch (_) {
          // Skip files locked by OS / other processes
        }
      }
    } catch (_) {}
  }

  /// Remove transient SharedPreferences while keeping essential keys + the
  /// login session. FlutterSecureStorage (biometric credentials) is NOT
  /// touched.
  static Future<void> _clearTransientPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();

      for (final key in allKeys) {
        if (!_keep(key)) {
          await prefs.remove(key);
        }
      }
    } catch (_) {}
  }
}
