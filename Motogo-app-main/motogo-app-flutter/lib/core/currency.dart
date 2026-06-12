import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Měnová vrstva — zrcadlí webové `i18n_currency.php` (Varianta A):
/// - Backend ukládá VŠECHNY ceny v CZK; zvolená měna je JEN zobrazovací.
/// - Stripe účtuje vždy CZK (žádné FX riziko) — karta zákazníka přepočítá.
/// - Kurzy: ČNB https://api.cnb.cz/cnbapi/exrates/daily, cache 15 min
///   v SharedPreferences, fallback chain: fresh → stale cache → bundled.
class AppCurrency {
  final String code;
  final String symbol;
  final String flag;
  final String name;
  final int decimals;
  const AppCurrency(this.code, this.symbol, this.flag, this.name, this.decimals);
}

const supportedCurrencies = [
  AppCurrency('CZK', 'Kč', '🇨🇿', 'Česká koruna', 0),
  AppCurrency('EUR', '€', '🇪🇺', 'Euro', 2),
  AppCurrency('PLN', 'zł', '🇵🇱', 'Polský zlotý', 2),
];

/// Default měna podle jazyka — shodně s webem.
String defaultCurrencyForLang(String lang) => switch (lang) {
      'cs' => 'CZK',
      'pl' => 'PLN',
      _ => 'EUR',
    };

/// Globální formátovač cen. Statický, aby šel volat z libovolného widgetu
/// (`Money.czk(1500)`); obrazovky, které mají zůstat živé i bez navigace,
/// si rebuild zajistí přes `ref.watch(currencyProvider)`.
class Money {
  Money._();

  static const _prefCode = 'mg_currency';
  static const _prefRates = 'mg_fx_rates';
  static const _prefRatesTs = 'mg_fx_rates_ts';
  static const _ttl = Duration(minutes: 15);

  // Záchytné kurzy (CZK za 1 jednotku) — lehce konzervativní, viz web.
  static const _fallbackRates = {'EUR': 25.50, 'PLN': 5.85};

  static String code = 'CZK';
  static Map<String, double> rates = Map.of(_fallbackRates);

  static AppCurrency get meta =>
      supportedCurrencies.firstWhere((c) => c.code == code,
          orElse: () => supportedCurrencies.first);

  /// Naformátuje částku v CZK do aktuálně zvolené měny.
  /// CZK: „1 234 Kč", EUR: „48,50 €", PLN: „199,90 zł".
  static String czk(num czkAmount) {
    final m = meta;
    double v = czkAmount.toDouble();
    if (m.code != 'CZK') {
      final rate = rates[m.code] ?? _fallbackRates[m.code] ?? 1;
      v = v / rate;
    }
    return '${_fmtNumber(v, m.decimals)} ${m.symbol}';
  }

  static String _fmtNumber(double v, int decimals) {
    final neg = v < 0;
    final fixed = v.abs().toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final sb = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) sb.write(' ');
      sb.write(intPart[i]);
    }
    final dec = decimals > 0 ? ',${parts[1]}' : '';
    return '${neg ? '−' : ''}$sb$dec';
  }

  /// Načte uloženou volbu + kurzy z cache (volat při startu, před runApp).
  static Future<void> init({String? defaultLang}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      code = prefs.getString(_prefCode) ??
          defaultCurrencyForLang(defaultLang ?? 'cs');
      final cached = prefs.getString(_prefRates);
      if (cached != null) {
        final m = (jsonDecode(cached) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, (v as num).toDouble()));
        if (m.isNotEmpty) rates = m;
      }
    } catch (_) {/* fallback defaults */}
  }

  static Future<void> _persistCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefCode, code);
    } catch (_) {}
  }

  /// Stáhne denní kurzy ČNB (cache 15 min). Tichý fail = stale/fallback.
  static Future<void> refreshRates({bool force = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getInt(_prefRatesTs) ?? 0;
      final age = DateTime.now().millisecondsSinceEpoch - ts;
      if (!force && age < _ttl.inMilliseconds) return;

      final res = await http
          .get(Uri.parse('https://api.cnb.cz/cnbapi/exrates/daily?lang=EN'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = data['rates'] as List<dynamic>? ?? [];
      final out = <String, double>{};
      for (final r in list) {
        final m = r as Map<String, dynamic>;
        final c = m['currencyCode'] as String? ?? '';
        if (c == 'EUR' || c == 'PLN') {
          final rate = (m['rate'] as num?)?.toDouble();
          final amount = (m['amount'] as num?)?.toDouble() ?? 1;
          if (rate != null && rate > 0 && amount > 0) out[c] = rate / amount;
        }
      }
      if (out.length == 2) {
        rates = out;
        await prefs.setString(_prefRates, jsonEncode(out));
        await prefs.setInt(
            _prefRatesTs, DateTime.now().millisecondsSinceEpoch);
      }
    } catch (e) {
      debugPrint('[Currency] CNB fetch failed: $e');
    }
  }
}

/// Aktuálně zvolený kód měny. Obrazovky s cenami, které žijí pod tab
/// navigací (nepřestavují se navigací), ho watchují kvůli rebuilds.
final currencyProvider =
    StateNotifierProvider<CurrencyNotifier, String>((ref) => CurrencyNotifier());

class CurrencyNotifier extends StateNotifier<String> {
  CurrencyNotifier() : super(Money.code);

  Future<void> setCurrency(String newCode) async {
    if (!supportedCurrencies.any((c) => c.code == newCode)) return;
    Money.code = newCode;
    state = newCode;
    await Money._persistCode();
    // Při přepnutí rovnou zkus čerstvé kurzy (ať EUR/PLN nesedí na fallbacku).
    await Money.refreshRates();
    if (mounted) state = newCode; // kurz se mohl změnit → další rebuild ne(š)kodí
  }
}
