import 'package:intl/intl.dart';

import '../../i18n/translations.dart';

/// Display-only formatting of the v2 look (design D4): locale numbers with a
/// no-break group separator, "1,2 km", "4,7", NBSP before a currency and
/// inside "3 dny", short dates "pá 23. 10." (year only when not this year).
/// NEVER used by price / date logic — money amounts keep the existing
/// currency formatter, this only joins what is already formatted.
const _nbsp = ' ';

String _locale(String lang) => lang == 'uk' ? 'uk' : (lang.isEmpty ? 'cs' : lang);

/// "12 027" (cs), "12,027" (en), "12.027" (de) — space-like separators
/// become a no-break space.
String mgNum(num v, String lang, {int decimals = 0}) {
  String out;
  try {
    final f = NumberFormat.decimalPattern(_locale(lang))
      ..minimumFractionDigits = decimals
      ..maximumFractionDigits = decimals;
    out = f.format(v);
  } catch (_) {
    out = v.toStringAsFixed(decimals);
  }
  return out.replaceAll(RegExp('[  ]'), _nbsp);
}

/// "1,2 km" under 10 km, else "128 km".
String mgKm(num km, String lang) => '${mgNum(km, lang, decimals: km.abs() < 10 ? 1 : 0)}${_nbsp}km';

/// "850 m".
String mgMeters(num m, String lang) => '${mgNum(m.round(), lang)}${_nbsp}m';

/// "4,7" (one decimal).
String mgRating(num r, String lang) => mgNum(r, lang, decimals: 1);

final _money = RegExp(r'(\d)[  ]+(Kč|€|EUR|CZK|zł|₴|грн)');
final _groups = RegExp(r'(\d)[  ](?=\d{3}(?!\d))');
final _days = RegExp(
  r'(\d)[  ]+(den|dny|dní|dnů|day|days|Tag|Tage|Tagen|día|días|jour|jours|dag|dagen|dzień|dni|день|дні|днів)(?![\p{L}])',
  unicode: true,
);

/// NBSP before a currency, between digit groups and inside "3 dny" — the
/// pair never breaks across lines. Digits themselves are never changed.
String mgNbsp(String s) => s
    .replaceAllMapped(_groups, (m) => '${m[1]}$_nbsp')
    .replaceAllMapped(_money, (m) => '${m[1]}$_nbsp${m[2]}')
    .replaceAllMapped(_days, (m) => '${m[1]}$_nbsp${m[2]}');

String _tr(String lang, String key) => translations[lang]?[key] ?? translations['cs']?[key] ?? key;

String _fill(String tpl, Map<String, Object> args) {
  var out = tpl;
  args.forEach((k, v) => out = out.replaceAll('{$k}', '$v'));
  return out;
}

/// "pá 23. 10." in [lang]; the year is added only when it is not this year
/// ("pá 23. 10. 2027"). The day never breaks inside.
String mgDayShort(DateTime d, String lang, {DateTime? now}) {
  final wd = _tr(lang, 'v2CalWdAbbr${d.weekday}');
  final thisYear = (now ?? DateTime.now()).year == d.year;
  final date = thisYear
      ? _fill(_tr(lang, 'v2CalDateShort'), {'d': d.day, 'm': d.month})
      : _fill(_tr(lang, 'v2CalDate'), {'d': d.day, 'm': d.month, 'y': d.year});
  return '$wd $date'.replaceAll(' ', _nbsp);
}

/// "pá 23. 10. → ne 25. 10." (may wrap only around the arrow).
String mgRange(DateTime a, DateTime b, String lang, {DateTime? now}) =>
    '${mgDayShort(a, lang, now: now)} → ${mgDayShort(b, lang, now: now)}';
