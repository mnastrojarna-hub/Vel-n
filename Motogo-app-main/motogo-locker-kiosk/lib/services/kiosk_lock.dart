import 'package:flutter/services.dart';

/// Ovládání kiosk zámku (Android lock task) přes platform channel do MainActivity.
/// Fullscreen (immersive) řeší SystemChrome v UI; tohle řeší lock task — aby
/// servisní technik mohl appku po zadání servisního hesla dočasně opustit.
class KioskLock {
  KioskLock._();
  static const _ch = MethodChannel('motogo24.kiosk/lock');

  /// Zamkne (lock task / kiosk režim). Bezpečné i na neandroidu (chybu spolkne).
  static Future<void> lock() async {
    try { await _ch.invokeMethod('lockKiosk'); } catch (_) {}
  }

  /// Odemkne (stopLockTask) — onResume už znovu nezamkne, dokud se app nerestartuje.
  static Future<void> unlock() async {
    try { await _ch.invokeMethod('unlockKiosk'); } catch (_) {}
  }
}
