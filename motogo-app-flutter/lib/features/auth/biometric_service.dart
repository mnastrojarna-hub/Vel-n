import 'package:local_auth/local_auth.dart';

/// Biometric authentication service — mirrors native-biometric.js
/// and native-fingerprint.js (Capacitor + Cordova bridges).
class BiometricService {
  static final _auth = LocalAuthentication();

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
    if (types.contains(BiometricType.fingerprint)) return 'Otisk prstu';
    if (types.contains(BiometricType.iris)) return 'Iris';
    return 'Biometrika';
  }

  /// Authenticate user with biometrics.
  /// Returns true on success, false on failure/cancel.
  /// Mirrors BiometricAuth.authenticate() from Capacitor plugin.
  static Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Přihlášení do MotoGo24',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // allowDeviceCredential: true
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
