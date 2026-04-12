import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Automatic cache & temp cleanup on app close / start.
///
/// Clears image cache, temp files, and transient SharedPreferences
/// while **preserving** biometric credentials (FlutterSecureStorage)
/// and essential user preferences.
class CacheCleanupService {
  /// SharedPreferences keys that MUST survive cleanup.
  static const _preserveKeys = <String>{
    'mg_bio_enabled', // biometric login toggle
    'mg_saved_email', // login email pre-fill
    'mg_locale', // selected language (overlay)
    'mg_language', // selected language (i18n)
    'mg_perms_shown', // permission overlay shown
  };

  /// Run full cleanup — safe to call from lifecycle or startup.
  static Future<void> run() async {
    await Future.wait([
      _clearImageCache(),
      _clearTempFiles(),
      _clearTransientPrefs(),
    ]);
  }

  /// Clear Flutter's in-memory image cache + painting bindings.
  static Future<void> _clearImageCache() async {
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
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

  /// Remove transient SharedPreferences while keeping essential keys.
  /// FlutterSecureStorage (biometric credentials) is NOT touched.
  static Future<void> _clearTransientPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();

      for (final key in allKeys) {
        if (!_preserveKeys.contains(key)) {
          await prefs.remove(key);
        }
      }
    } catch (_) {}
  }
}
