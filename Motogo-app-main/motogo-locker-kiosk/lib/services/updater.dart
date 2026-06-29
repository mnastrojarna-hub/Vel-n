import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'diag.dart';

/// OTA aktualizace — appka dostane z heartbeatu info o nejnovější verzi
/// (app_settings.kiosk_app: {version_code, apk_url}). Když je novější, stáhne APK
/// a spustí instalaci přes platform channel (systémový instalátor; tiše přes MDM/
/// device owner). Verzi spravuje Velín.
class Updater {
  Updater._();
  static final Updater instance = Updater._();
  static const _ch = MethodChannel('motogo24.kiosk/lock');

  int currentBuild = 0; // = versionCode, nastaví se při startu z package_info
  bool _busy = false;
  int _lastTried = 0;

  Future<void> maybeUpdate(dynamic update) async {
    if (update is! Map) return;
    final vc = update['version_code'];
    final url = update['apk_url'] as String?;
    if (vc is! int || url == null || url.trim().isEmpty) return;
    if (vc <= currentBuild || vc == _lastTried || _busy) return;

    _busy = true;
    _lastTried = vc;
    try {
      final res = await http.get(Uri.parse(url.trim())).timeout(const Duration(minutes: 5));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        await KioskDiag.error('ota', 'Stažení APK selhalo (HTTP ${res.statusCode})', {'url': url});
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/motogo_kiosk_$vc.apk');
      await file.writeAsBytes(res.bodyBytes, flush: true);
      await KioskDiag.info('ota', 'Stahuji aktualizaci v$vc → instalace', {'bytes': res.bodyBytes.length});
      await _ch.invokeMethod('installApk', {'path': file.path});
    } catch (e) {
      await KioskDiag.error('ota', 'Aktualizace selhala: $e', {'version_code': vc});
    } finally {
      _busy = false;
    }
  }
}
