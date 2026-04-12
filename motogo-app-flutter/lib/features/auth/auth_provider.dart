import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth_guard.dart';
import '../../core/supabase_client.dart';
import '../../core/i18n/translations.dart';

/// Watches Supabase auth state changes (login/logout/token refresh).
/// When token refresh fails, forces sign-out so the router redirects to login.
final authStateProvider = StreamProvider<Session?>((ref) {
  return MotoGoSupabase.client.auth.onAuthStateChange.map((event) {
    // Token refresh failed → force sign out (session becomes null → router
    // redirects to login automatically).
    if (event.event == AuthChangeEvent.tokenRefreshed &&
        event.session == null) {
      MotoGoSupabase.client.auth.signOut();
      return null;
    }
    return event.session;
  });
});

/// Provides the current user profile from the profiles table.
final profileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final session = ref.watch(authStateProvider).valueOrNull;
  if (session == null) return null;

  try {
    final res = await MotoGoSupabase.client
        .from('profiles')
        .select()
        .eq('id', session.user.id)
        .maybeSingle();
    return res;
  } catch (e) {
    if (await handleAuthError(e)) return null;
    rethrow;
  }
});

/// Auth service — mirrors auth-ui.js, auth-register.js, auth-session.js.
class AuthService {
  static const _secureStorage = FlutterSecureStorage();
  static const _bioUserKey = 'mg_bio_user';
  static const _bioEnabledKey = 'mg_bio_enabled';
  static const _savedEmailKey = 'mg_saved_email';

  static SupabaseClient get _client => MotoGoSupabase.client;

  /// Translation helper (no BuildContext available).
  static String _tr(String key) {
    return translations['cs']?[key] ?? key;
  }

  // ===== LOGIN =====
  /// Sign in with email + password. Returns error message or null on success.
  static Future<String?> signIn(String email, String password) async {
    try {
      final res = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (res.session != null && res.user != null) {
        await _storeBioUser(
          userId: res.user!.id,
          email: email,
          refreshToken: res.session!.refreshToken,
          password: password,
        );
        await _saveEmail(email);
        return null; // success
      }
      return _tr('loginFailed');
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return '${_tr('loginError')}: $e';
    }
  }

  // ===== REGISTRATION =====
  /// Guard against duplicate signUp calls (e.g. double-tap).
  static bool _signUpInProgress = false;

  /// Register new user. Returns error message or null on success.
  static Future<String?> signUp({
    required String email,
    required String password,
    required Map<String, dynamic> metadata,
  }) async {
    // Prevent duplicate registration calls
    if (_signUpInProgress) return _tr('signUpInProgress');
    _signUpInProgress = true;

    try {
      final res = await _client.auth.signUp(
        email: email,
        password: password,
        data: metadata,
      );

      if (res.user == null) return _tr('signUpFailed');

      // Wait for handle_new_user() trigger to create the profile row
      // (same pattern as frontend auth.js – 500ms delay)
      await Future.delayed(const Duration(milliseconds: 500));

      // Save consents + registration_source to profiles table.
      // Retry up to 2× if the trigger hasn't created the row yet.
      final updateData = {
        'marketing_consent': true,
        'consent_gdpr': true,
        'consent_vop': true,
        'consent_data_processing': true,
        'consent_email': true,
        'consent_sms': true,
        'consent_push': true,
        'consent_whatsapp': true,
        'consent_photo': true,
        'consent_contract': true,
        'registration_source': 'app',
      };

      for (int attempt = 0; attempt < 3; attempt++) {
        final rows = await _client
            .from('profiles')
            .update(updateData)
            .eq('id', res.user!.id)
            .select('id');
        if ((rows as List).isNotEmpty) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }

      await _storeBioUser(
        userId: res.user!.id,
        email: email,
        refreshToken: res.session?.refreshToken,
        password: password,
      );
      await _saveEmail(email);
      return null; // success
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return '${_tr('registerError')}: $e';
    } finally {
      _signUpInProgress = false;
    }
  }

  // ===== LOGOUT =====
  static Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {}
  }

  // ===== FORGOT PASSWORD =====
  static Future<String?> resetPassword(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
      return null;
    } on AuthException catch (e) {
      return e.message;
    }
  }

  static Future<String?> verifyOtp(String email, String token) async {
    try {
      await _client.auth.verifyOTP(
        email: email,
        token: token,
        type: OtpType.recovery,
      );
      return null;
    } on AuthException catch (e) {
      return e.message;
    }
  }

  static Future<String?> updatePassword(String newPassword) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
      return null;
    } on AuthException catch (e) {
      return e.message;
    }
  }

  // ===== BIOMETRIC HELPERS =====
  /// Store bio user data for fingerprint/face login.
  /// Mirrors _storeBioUser from auth-ui.js.
  static Future<void> _storeBioUser({
    required String userId,
    required String email,
    String? refreshToken,
    String? password,
  }) async {
    final data = <String, String>{
      'user_id': userId,
      'email': email,
    };
    if (refreshToken != null) data['refresh_token'] = refreshToken;
    if (password != null) data['pwd'] = base64Encode(utf8.encode(password));

    await _secureStorage.write(
      key: _bioUserKey,
      value: jsonEncode(data),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_bioEnabledKey, true);
  }

  /// Read stored bio user data.
  static Future<Map<String, dynamic>?> getBioUser() async {
    final raw = await _secureStorage.read(key: _bioUserKey);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Check if biometric login is enabled.
  static Future<bool> isBioEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_bioEnabledKey) ?? false;
  }

  /// Restore Supabase session from stored bio credentials.
  /// Mirrors _bioRestoreSession from auth-ui.js.
  static Future<bool> bioRestoreSession() async {
    final bioUser = await getBioUser();
    if (bioUser == null) return false;

    // 1. Check existing session
    final existing = _client.auth.currentSession;
    if (existing != null) return true;

    // 2. Try refresh token
    final refreshToken = bioUser['refresh_token'] as String?;
    if (refreshToken != null) {
      try {
        final res = await _client.auth.setSession(refreshToken);
        if (res.session != null) return true;
      } catch (_) {}
    }

    // 3. Fallback: sign in with stored credentials
    final email = bioUser['email'] as String?;
    final pwdB64 = bioUser['pwd'] as String?;
    if (email != null && pwdB64 != null) {
      try {
        final pwd = utf8.decode(base64Decode(pwdB64));
        final res = await _client.auth.signInWithPassword(
          email: email,
          password: pwd,
        );
        return res.session != null;
      } catch (_) {}
    }

    return false;
  }

  /// Clear bio data when session can't be restored.
  static Future<void> clearBioData() async {
    // Keep saved email for pre-fill
    final bioUser = await getBioUser();
    if (bioUser != null && bioUser['email'] != null) {
      await _saveEmail(bioUser['email'] as String);
    }
    await _secureStorage.delete(key: _bioUserKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_bioEnabledKey);
  }

  /// Get saved email for login pre-fill.
  static Future<String?> getSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_savedEmailKey);
  }

  static Future<void> _saveEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedEmailKey, email);
  }
}
