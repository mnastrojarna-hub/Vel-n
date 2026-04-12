import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../supabase_client.dart';
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
];

const _langKey = 'mg_language';

/// Current locale provider.
final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>(
  (ref) => LocaleNotifier(),
);

class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(const Locale('cs')) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_langKey);
    if (code != null) state = Locale(code);
  }

  Future<void> setLocale(Locale locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_langKey, locale.languageCode);

    // Save to profile if logged in
    final user = MotoGoSupabase.currentUser;
    if (user != null) {
      try {
        await MotoGoSupabase.client.from('profiles').update({
          'language': locale.languageCode,
        }).eq('id', user.id);
      } catch (_) {}
    }
  }
}

/// Get translation string — shorthand for T.of(context).
/// Usage: t(context).login, t(context).bookingTitle, etc.
AppTranslations t(BuildContext context) {
  final locale = Localizations.localeOf(context);
  return AppTranslations.of(locale.languageCode);
}

/// All translations — simple key-value map approach.
/// Mirrors _t() function from i18n.js.
class AppTranslations {
  final String lang;

  const AppTranslations(this.lang);

  factory AppTranslations.of(String languageCode) {
    return AppTranslations(languageCode);
  }

  String _get(String key) {
    return translations[lang]?[key] ?? translations['cs']?[key] ?? key;
  }

  /// Generic translation lookup — for keys without a dedicated getter.
  /// Usage: t(context).tr('fillEmailAndPassword')
  String tr(String key) => _get(key);

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
];
