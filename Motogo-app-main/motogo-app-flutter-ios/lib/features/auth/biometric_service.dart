import 'package:flutter/services.dart' show PlatformException;
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';

import '../../core/i18n/translations.dart';

/// Biometric authentication service — mirrors native-biometric.js
/// and native-fingerprint.js (Capacitor + Cordova bridges).
class BiometricService {
  static final _auth = LocalAuthentication();

  /// Get translated string for a given language (no context needed).
  static String _tr(String key, [String lang = 'cs']) {
    return translations[lang]?[key] ?? translations['cs']?[key] ?? key;
  }

  /// Check if device supports biometric authentication.
  static Future<bool> isAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck || isSupported;
    } catch (_) {
      return false;
    }
  }

  /// Get available biometric types (fingerprint, face, iris).
  static Future<List<BiometricType>> getAvailableTypes() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  /// Get human-readable label for the primary biometric type.
  static Future<String> getBiometricLabel() async {
    final types = await getAvailableTypes();
    if (types.contains(BiometricType.face)) return 'Face ID';
    if (types.contains(BiometricType.fingerprint)) return _tr('bioFingerprint');
    if (types.contains(BiometricType.iris)) return _tr('bioIris');
    return _tr('biometricTitle');
  }

  /// Authenticate user with biometrics.
  /// Returns true on success, false on failure/cancel.
  /// Mirrors BiometricAuth.authenticate() from Capacitor plugin.
  static Future<bool> authenticate() async =>
      await authenticateResult() == BioAuthResult.ok;

  /// Jako [authenticate], ale řekne PROČ ověření neprošlo — zablokovaná
  /// biometrie / bez nastaveného otisku se nesmí tvářit jako „Ověření zrušeno".
  static Future<BioAuthResult> authenticateResult() async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: _tr('bioLoginReason'),
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // allowDeviceCredential: true
          useErrorDialogs: true,
        ),
      );
      return ok ? BioAuthResult.ok : BioAuthResult.cancelled;
    } on PlatformException catch (e) {
      switch (e.code) {
        case auth_error.lockedOut:
        case auth_error.permanentlyLockedOut:
          return BioAuthResult.lockedOut;
        case auth_error.notEnrolled:
        case auth_error.passcodeNotSet:
          return BioAuthResult.notEnrolled;
        case auth_error.notAvailable:
          return BioAuthResult.unavailable;
      }
      return BioAuthResult.cancelled;
    } catch (_) {
      return BioAuthResult.cancelled;
    }
  }
}

/// Výsledek biometrického ověření.
enum BioAuthResult { ok, cancelled, lockedOut, notEnrolled, unavailable }
