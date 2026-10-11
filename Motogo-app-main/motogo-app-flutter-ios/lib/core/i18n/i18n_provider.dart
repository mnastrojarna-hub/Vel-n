import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../debug_logger.dart';
import '../supabase_client.dart';
import 'app_lang.dart';
import 'translations.dart';

/// Supported languages — mirrors lang-select.js overlay.
const supportedLocales = [
  Locale('cs'), // Čeština (default)
  Locale('en'), // English
  Locale('de'), // Deutsch
  Locale('es'), // Español
  Locale('fr'), // Français
  Locale('nl'), // Nederlands
  Locale('pl'), // Polski
  Locale('uk'), // Українська
];

/// Zdroj pravdy jazyka appky. Uvítací výběr jazyka (LanguageOverlay) i
/// Nastavení ukládají sem; `mg_locale` je jen příznak „úvodní výběr proběhl"
/// (a jazyk starších instalací, kde overlay zapisoval jen tento klíč).
const _langKey = 'mg_language';
const _legacyLangKey = 'mg_locale';

/// Posledni znamy jazyk appky (zdroj pravdy = localeProvider). Slouzi jako
/// fallback pro `t()`, kdyz `Localizations.localeOf` jeste neni pripravene
/// (delegaty se nacitaji asynchronne; behem prepnuti jazyka je locale chvili
/// null → `Localizations.localeOf` hodi „Null check operator used on a null
/// value"). Drzime ho synchronne, aby preklad nikdy nespadl.
String _lastKnownLang = 'cs';

/// Poslední známý jazyk appky — pro místa bez BuildContextu (chybová
/// obrazovka, služby).
String get lastKnownAppLang => _lastKnownLang;

/// Current locale provider.
final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>(
  (ref) => LocaleNotifier(),
);

class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(const Locale('cs')) {
    _loaded = _load();
    _listenAuth();
  }

  late final Future<void> _loaded;
  StreamSubscription<AuthState>? _authSub;

  /// true = zákazník si jazyk v appce zvolil (uvítací overlay / Nastavení).
  bool _hasLocalChoice = false;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    var code = prefs.getString(_langKey);
    // Starší instalace: uvítací overlay ukládal jen `mg_locale` a jazyk se
    // nikdy nepoužil → převezmi ho a ulož jako `mg_language`.
    if (code == null) {
      final legacy = prefs.getString(_legacyLangKey);
      if (legacy != null && legacy.isNotEmpty) {
        code = normalizeAppLang(legacy);
        await prefs.setString(_langKey, code);
      }
    }
    if (code != null) {
      _hasLocalChoice = true;
      code = normalizeAppLang(code);
      if (mounted) state = Locale(code);
      _lastKnownLang = code;
    }
  }

  /// Po přihlášení srovná jazyk profilu s appkou: když si zákazník jazyk v
  /// appce nevybral (nová instalace bez výběru), převezme jazyk z profilu;
  /// jinak zapíše volbu appky do `profiles.language` (detect_customer_language
  /// pak posílá e-maily/SMS ve stejném jazyce).
  void _listenAuth() {
    try {
      _authSub = MotoGoSupabase.client.auth.onAuthStateChange.listen((data) {
        if (data.event == AuthChangeEvent.signedIn) unawaited(_syncWithProfile());
      });
    } catch (_) {/* Supabase ještě není inicializovaný (testy) */}
  }

  Future<void> _syncWithProfile() async {
    await _loaded;
    final user = MotoGoSupabase.currentUser;
    if (user == null) return;
    try {
      final row = await MotoGoSupabase.client
          .from('profiles')
          .select('language')
          .eq('id', user.id)
          .maybeSingle();
      final profileLang = row?['language'] as String?;
      if (!_hasLocalChoice) {
        if (profileLang != null && appLanguageCodes.contains(profileLang)) {
          await setLocale(Locale(profileLang), syncProfile: false);
        }
        return;
      }
      if (profileLang != state.languageCode) {
        await _saveProfileLang(state.languageCode);
      }
    } catch (e) {
      AppDebugLogger.instance.log(LogCategory.api, 'profile_lang_sync_failed', detail: e.toString());
    }
  }

  Future<void> _saveProfileLang(String code) async {
    final user = MotoGoSupabase.currentUser;
    if (user == null) return;
    try {
      await MotoGoSupabase.client
          .from('profiles')
          .update({'language': code}).eq('id', user.id);
    } catch (e) {
      // Živá DB před migrací 20261011 nezná 'uk' (CHECK) — profil pak nese
      // nejbližší podporovaný jazyk, ať e-maily nechodí česky.
      if (isLanguageCheckViolation(e) && code != 'en') {
        await _saveProfileLang('en');
        return;
      }
      AppDebugLogger.instance.log(LogCategory.api, 'profile_lang_save_failed',
          detail: e.toString(), data: {'language': code});
    }
  }

  Future<void> setLocale(Locale locale, {bool syncProfile = true}) async {
    final code = normalizeAppLang(locale.languageCode);
    state = Locale(code);
    _lastKnownLang = code;
    _hasLocalChoice = syncProfile || _hasLocalChoice;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_langKey, code);
    // Save to profile if logged in
    if (syncProfile) await _saveProfileLang(code);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}

/// Get translation string — shorthand for T.of(context).
/// Usage: t(context).login, t(context).bookingTitle, etc.
AppTranslations t(BuildContext context) {
  // `Localizations.localeOf` hodi null-check, kdyz delegaty jeste nejsou
  // nactene (prvni frame / behem prepnuti jazyka). Odchytime a spadneme na
  // posledni znamy jazyk — preklad tak nikdy neshodi appku (drive padalo na
  // language pickeru i promo dialogu).
  try {
    final locale = Localizations.localeOf(context);
    _lastKnownLang = locale.languageCode;
    return AppTranslations.of(locale.languageCode);
  } catch (_) {
    return AppTranslations.of(_lastKnownLang);
  }
}

/// All translations — simple key-value map approach.
/// Mirrors _t() function from i18n.js.
class AppTranslations {
  final String lang;

  const AppTranslations(this.lang);

  factory AppTranslations.of(String languageCode) {
    return AppTranslations(languageCode);
  }

  /// Chybějící klíč: cizí jazyk → angličtina (srozumitelnější než čeština),
  /// pak čeština, nakonec samotný klíč.
  String _get(String key) {
    final fallback = lang != 'cs' ? translations['en'] : null;
    return translations[lang]?[key] ??
        fallback?[key] ??
        translations['cs']?[key] ??
        key;
  }

  /// Generic translation lookup — for keys without a dedicated getter.
  /// Usage: t(context).tr('fillEmailAndPassword')
  String tr(String key) => _get(key);

  /// Překlad s dosazením `{placeholder}` hodnot.
  String trArgs(String key, Map<String, Object?> args) {
    var s = _get(key);
    args.forEach((k, v) => s = s.replaceAll('{$k}', '${v ?? ''}'));
    return s;
  }

  /// Slovo „den/dny/dní" ve správném tvaru pro jazyk (cs/pl/uk mají tři
  /// tvary, ostatní jazyky dva).
  String daysWord(int n) {
    final a = n.abs();
    if (lang == 'cs') {
      return a == 1 ? _get('day1') : (a >= 2 && a <= 4 ? _get('days24') : _get('days5'));
    }
    if (lang == 'pl' || lang == 'uk') {
      if (a == 1) return _get('day1');
      final m10 = a % 10, m100 = a % 100;
      final few = m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14);
      if (lang == 'uk' && m10 == 1 && m100 != 11) return _get('day1');
      return few ? _get('days24') : _get('days5');
    }
    return a == 1 ? _get('day1') : _get('days5');
  }

  // Auth
  String get login => _get('login');
  String get register => _get('register');
  String get email => _get('email');
  String get password => _get('password');
  String get forgotPassword => _get('forgotPassword');
  String get loginBtn => _get('loginBtn');
  String get registerBtn => _get('registerBtn');
  String get noAccount => _get('noAccount');
  String get welcome => _get('welcome');
  String get logout => _get('logout');

  // Navigation
  String get home => _get('home');
  String get search => _get('search');
  String get reservations => _get('reservations');
  String get shop => _get('shop');
  String get profile => _get('profile');

  // Booking
  String get bookingTitle => _get('bookingTitle');
  String get motorcycle => _get('motorcycle');
  String get date => _get('date');
  String get pickupTime => _get('pickupTime');
  String get extras => _get('extras');
  String get pickup => _get('pickup');
  String get returnLabel => _get('returnLabel');
  String get priceSummary => _get('priceSummary');
  String get proceedPayment => _get('proceedPayment');
  String get totalFinal => _get('totalFinal');

  // Reservations
  String get active => _get('active');
  String get upcoming => _get('upcoming');
  String get completed => _get('completed');
  String get cancelled => _get('cancelled');
  String get detail => _get('detail');
  String get edit => _get('edit');

  // SOS
  String get sosTitle => _get('sosTitle');
  String get accident => _get('accident');
  String get breakdown => _get('breakdown');
  String get theft => _get('theft');
  String get shareLocation => _get('shareLocation');

  // Common
  String get save => _get('save');
  String get cancel => _get('cancel');
  String get back => _get('back');
  String get next => _get('next');
  String get loading => _get('loading');
  String get error => _get('error');
  String get success => _get('success');
  String get confirm => _get('confirm');
  String get free => _get('free');
}

/// Language display info for selector.
class LangInfo {
  final String code;
  final String flag;
  final String name;
  const LangInfo(this.code, this.flag, this.name);
}

const availableLanguages = [
  LangInfo('cs', '🇨🇿', 'Čeština'),
  LangInfo('en', '🇬🇧', 'English'),
  LangInfo('de', '🇩🇪', 'Deutsch'),
  LangInfo('es', '🇪🇸', 'Español'),
  LangInfo('fr', '🇫🇷', 'Français'),
  LangInfo('nl', '🇳🇱', 'Nederlands'),
  LangInfo('pl', '🇵🇱', 'Polski'),
  LangInfo('uk', '🇺🇦', 'Українська'),
];
