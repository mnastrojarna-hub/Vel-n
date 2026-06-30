import 'dart:convert';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth_guard.dart';
import '../../core/supabase_client.dart';
import '../../core/debug_logger.dart';
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

/// Grace window after sign-up during which a missing profile row is tolerated.
/// The `handle_new_user()` trigger creates the profiles row asynchronously, so a
/// brand-new account may briefly have a valid session without a profile yet.
const _newUserProfileGrace = Duration(minutes: 2);

/// `true` when [user] was created so recently that its profile row may not have
/// been written by the `handle_new_user()` trigger yet.
bool _isFreshlyRegistered(User user) {
  final created = DateTime.tryParse(user.createdAt);
  if (created == null) return true; // unknown → don't risk kicking the user out
  return DateTime.now().toUtc().difference(created.toUtc()) < _newUserProfileGrace;
}

/// Provides the current user profile from the profiles table.
///
/// Acts as the backstop for deleted accounts: if a valid auth session exists but
/// the `profiles` row is gone (account deleted in Velín — historically an
/// orphaned `auth.users` record was left behind), the login still passes against
/// `auth.users` yet the app would show empty data. We force a sign-out here so
/// the router bounces back to login and the customer must register again. New
/// sign-ups are exempt via [_isFreshlyRegistered] (trigger lag).
final profileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final session = ref.watch(authStateProvider).valueOrNull;
  if (session == null) return null;

  try {
    final res = await MotoGoSupabase.client
        .from('profiles')
        .select()
        .eq('id', session.user.id)
        .maybeSingle();

    if (res == null && !_isFreshlyRegistered(session.user)) {
      await MotoGoSupabase.client.auth.signOut();
      return null;
    }
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
        // Account deleted in Velín leaves an orphaned auth.users row (profiles
        // gone) → credentials still authenticate but the app has no data.
        // Reject the login and push the customer to re-register.
        if (!await _profileExists(res.user!.id)) {
          await _client.auth.signOut();
          return _tr('accountNoLongerExists');
        }
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

  /// Zjistí, jestli e-mail u nás už existuje (účet z webu i z appky). Vrací
  /// `true`/`false`, nebo `null` když to nelze ověřit (chyba/sítě) — volající
  /// pak nemá tvrdit „neznámý e-mail". Používá stejné RPC jako web.
  static Future<bool?> emailExists(String email) async {
    try {
      final res = await _client.rpc('check_web_booking_email',
          params: {'p_email': email.trim().toLowerCase()});
      if (res is Map) return res['exists'] == true;
      return null;
    } catch (_) {
      return null;
    }
  }

  // ===== REGISTRATION =====
  /// Guard against duplicate signUp calls (e.g. double-tap).
  static bool _signUpInProgress = false;

  /// Register new user. Returns error message or null on success.
  ///
  /// [metadata] is stored on auth.users (consumed by the handle_new_user
  /// trigger). [profile] holds the personal/address/license fields written
  /// directly to the profiles row — the trigger only copies a subset, so these
  /// would otherwise be lost.
  static Future<String?> signUp({
    required String email,
    required String password,
    required Map<String, dynamic> metadata,
    Map<String, dynamic>? profile,
  }) async {
    // Prevent duplicate registration calls
    if (_signUpInProgress) return _tr('signUpInProgress');
    _signUpInProgress = true;

    try {
      // Do `data` (raw_user_meta_data) posíláme VŠECHNA pole — aby je mohl
      // uložit handle_new_user trigger i BEZ session (když je zapnuté potvrzení
      // e-mailu, appka po signUp nemá session → žádný klientský zápis profilu
      // neprojde; jediná spolehlivá cesta je trigger, který běží server-side
      // v transakci vytvoření uživatele). license_group jde jako JSON pole.
      final signUpData = <String, dynamic>{
        ...metadata,
        if (profile != null) ...profile,
      };
      final res = await _client.auth.signUp(
        email: email,
        password: password,
        data: signUpData,
      );

      if (res.user == null) return _tr('signUpFailed');

      // Diagnostika do app_debug_logs (vidí Velín) — ground truth, jestli má
      // appka po signUp session. Bez session = potvrzení e-mailu je ZAPNUTÉ
      // a profil musí uložit trigger z metadat (ne klient).
      final hadSessionAfterSignup = _client.auth.currentSession != null;
      AppDebugLogger.instance.auth('signup_created', data: {
        'has_session_after_signup': hadSessionAfterSignup,
        'user_id': res.user!.id,
      });

      // KRITICKÉ: zajisti aktivní session PŘED zápisem do profiles.
      // `auth.signUp` nemusí vždy vrátit aktivní session (podle nastavení
      // e-mail confirmation / timingu), a UPDATE profiles je vázán RLS na
      // auth.uid()=id. Bez session běží update jako anon → 0 řádků → osobní
      // údaje (datum narození, adresa, č. ŘP, skupina, platnost) se TIŠE
      // ztratí (žádná chyba). Když session chybí, přihlas se heslem.
      if (_client.auth.currentSession == null) {
        try {
          await _client.auth.signInWithPassword(email: email, password: password);
        } catch (_) {/* když confirmation blokuje, update stejně proběhne v retry */}
      }
      AppDebugLogger.instance.auth('signup_session_before_profile', data: {
        'has_session': _client.auth.currentSession != null,
      });

      // Wait for handle_new_user() trigger to create the profile row
      // (same pattern as frontend auth.js – 500ms delay)
      await Future.delayed(const Duration(milliseconds: 500));

      // Jazyk z uloženého locale appky → uloží se do profiles.language při
      // registraci, aby maily (potvrzení, úprava, dokončení) chodily přeložené
      // i bez rezervace. detect_customer_language čte profiles.language jako
      // první v pořadí (před bookings/shop_orders). Fallback 'cs'.
      String regLang = 'cs';
      try {
        final prefs = await SharedPreferences.getInstance();
        regLang = (prefs.getString('mg_locale') ?? 'cs').split(RegExp(r'[-_]')).first;
      } catch (_) {/* ponech 'cs' */}

      // Ulož profil STEJNĚ JAKO WEB — přes jeden SECURITY DEFINER RPC
      // `app_save_full_profile`. Důvod: přímý PostgREST zápis z appky padal
      // (a) na RLS u INSERT větve upsertu a (b) na ENUM poli `license_group[]`,
      // které PostgREST z JSON pole neumí přetypovat → uložilo se jen
      // jméno/e-mail/telefon z triggeru. RPC běží server-side, obejde RLS i typy
      // a zapíše VŠECHNA pole najednou (adresa, datum narození, čísla dokladů,
      // skupina ŘP, jazyk) — přesně jako `create_web_booking` na webu.
      final pData = <String, dynamic>{
        if (profile != null) ...profile, // vč. license_group jako pole stringů
        'language': regLang,
      };

      bool savedProfile = false;
      for (int attempt = 0; attempt < 4; attempt++) {
        try {
          final res2 = await _client
              .rpc('app_save_full_profile', params: {'p_data': pData});
          if (res2 is Map && res2['success'] == true) {
            savedProfile = true;
            break;
          }
        } catch (_) {
          if (attempt == 3) break;
        }
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // Fallback (kdyby RPC ještě nebylo nasazené): zapiš aspoň ne-enum pole
      // běžným UPDATE (řádek už vytvořil trigger) a skupinu ŘP přes druhé RPC.
      if (!savedProfile) {
        final fallback = Map<String, dynamic>.from(pData)..remove('license_group');
        try {
          await _client.from('profiles').update(fallback).eq('id', res.user!.id);
        } catch (_) {/* neblokuj registraci */}
        final lic = (profile?['license_group'] as List?)
                ?.map((e) => '$e'.trim().toUpperCase())
                .where((e) => e.isNotEmpty)
                .toList() ??
            const <String>[];
        if (lic.isNotEmpty) {
          try {
            await _client
                .rpc('set_my_license_group', params: {'p_groups': lic});
          } catch (_) {}
        }
      }

      // Ověř, co se reálně uložilo (čteme zpět profil) — diagnostika do
      // app_debug_logs, ať víme, jestli registrace zapsala adresu/doklady, nebo
      // jen trigger metadata (= chybí session / RLS / RPC).
      try {
        final check = await _client
            .from('profiles')
            .select('street, city, zip, date_of_birth, id_number, license_number, license_group')
            .eq('id', res.user!.id)
            .maybeSingle();
        AppDebugLogger.instance.auth('signup_profile_result', data: {
          'saved_via_rpc': savedProfile,
          'has_street': (check?['street'] ?? '').toString().isNotEmpty,
          'has_city': (check?['city'] ?? '').toString().isNotEmpty,
          'has_dob': check?['date_of_birth'] != null,
          'has_id_number': (check?['id_number'] ?? '').toString().isNotEmpty,
          'has_license_number': (check?['license_number'] ?? '').toString().isNotEmpty,
          'has_license_group': (check?['license_group'] as List?)?.isNotEmpty ?? false,
        });
      } catch (e) {
        AppDebugLogger.instance.auth('signup_profile_check_failed',
            detail: e.toString());
      }
      AppDebugLogger.instance.flushNow();

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
  // Místo Supabase Auth resetPasswordForEmail (rate-limited 3/h, SMTP config)
  // voláme náš edge fn `send-recovery-otp` — interně dělá generateLink + Resend
  // mail z noreply@motogo24.cz. Anti-enumeration řešená v edge fn (vždy 200 success).
  // Stejný flow jako web /rezervace a /upravit-rezervaci.
  static Future<String?> resetPassword(String email) async {
    try {
      // i18n: jazyk z uloženého locale appky → OTP mail dorazí přeložený
      // (edge fn jinak fallbackuje na profiles.language, pak 'cs').
      final prefs = await SharedPreferences.getInstance();
      final lang = (prefs.getString('mg_locale') ?? 'cs').split(RegExp(r'[-_]')).first;
      final res = await _client.functions.invoke(
        'send-recovery-otp',
        body: {'email': email.trim().toLowerCase(), 'language': lang},
      );
      // Edge fn vrací success aj při neexistujícím mailu (anti-enumeration).
      // Klient pokračuje na OTP screen — pokud zákazník zadá kód, který
      // nedorazil, verifyOtp selže a zobrazí správnou hlášku.
      if (res.status >= 500) {
        return 'Server je nedostupný, zkuste to prosím za chvíli.';
      }
      return null;
    } on FunctionException catch (e) {
      return e.details?.toString() ?? 'Reset hesla se nepodařil.';
    } catch (e) {
      return e.toString();
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
    String? raw;
    try {
      raw = await _secureStorage.read(key: _bioUserKey);
    } on PlatformException catch (_) {
      // Android keystore klíč se po reinstalaci / obnově ze zálohy / update OS
      // přegeneruje → uložený blob už nelze dešifrovat (BadPaddingException:
      // BAD_DECRYPT) a appka při každém startu padala. Smaž poškozený záznam a
      // vypni biometriku — uživatel se přihlásí heslem, žádný crash.
      try {
        await _secureStorage.deleteAll();
      } catch (_) {}
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_bioEnabledKey, false);
      } catch (_) {}
      return null;
    } catch (_) {
      return null;
    }
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
    if (existing != null) {
      return _guardRestoredProfile(existing.user.id);
    }

    // 2. Try refresh token
    final refreshToken = bioUser['refresh_token'] as String?;
    if (refreshToken != null) {
      try {
        final res = await _client.auth.setSession(refreshToken);
        if (res.session != null) {
          return _guardRestoredProfile(res.session!.user.id);
        }
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
        if (res.session != null) {
          return _guardRestoredProfile(res.user!.id);
        }
      } catch (_) {}
    }

    return false;
  }

  /// After a session is restored, make sure the profile still exists. A deleted
  /// account leaves an orphaned auth.users row, so the session restores fine but
  /// there is no profile — sign out so the user lands back on login/register.
  static Future<bool> _guardRestoredProfile(String userId) async {
    if (await _profileExists(userId)) return true;
    await signOut();
    return false;
  }

  /// Returns whether a profiles row exists for [userId]. On query failure it
  /// returns `true` (fail-open) so a transient network blip never locks a valid
  /// customer out of the app.
  static Future<bool> _profileExists(String userId) async {
    try {
      final row = await _client
          .from('profiles')
          .select('id')
          .eq('id', userId)
          .maybeSingle();
      return row != null;
    } catch (_) {
      return true;
    }
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
