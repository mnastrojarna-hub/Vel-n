import '../../../core/currency.dart';
import '../../../core/date_days.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/calendar/trip_day_state.dart';
import '../catalog_provider.dart';
import '../moto_model.dart';

/// Presentation helpers of the v2 catalog (labels only — no logic of their
/// own; every rule is the one the old cards / filter already used).

/// Category label exactly as the old card (`MotoCard._categoryLabel`):
/// known slug → translated key, unknown slug → the raw value.
String catCategoryLabel(AppTranslations tr, String cat) {
  final key = MotoCategory.labelKey(cat);
  return key == 'all' ? cat : tr.tr(key);
}

/// Licence badge exactly as the old card (`_licenseBadgeLabel`): kids'
/// bikes (only 'N') → "N (bez ŘP)", else prefix + groups without 'N'.
String catLicenseLabel(AppTranslations tr, Motorcycle m) {
  final groups = m.licenseGroupsOrFallback;
  if (groups.isEmpty) return '';
  if (groups.length == 1 && groups.first == 'N') return tr.tr('catalogNoLicense');
  return '${tr.tr('motoCardLicensePrefix')}${groups.where((g) => g != 'N').join(' / ')}';
}

/// "1 motorka" / "3 motorky" / "12 motorek" (3 forms in cs, pl, uk).
String catCount(AppTranslations tr, int n) {
  final a = n.abs();
  final lang = tr.lang;
  String key;
  if (lang == 'cs') {
    key = a == 1 ? 'v2CatCountOne' : (a >= 2 && a <= 4 ? 'v2CatCountFew' : 'v2CatCountMany');
  } else if (lang == 'pl' || lang == 'uk') {
    final m10 = a % 10, m100 = a % 100;
    final few = m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14);
    key = a == 1 || (lang == 'uk' && m10 == 1 && m100 != 11)
        ? 'v2CatCountOne'
        : (few ? 'v2CatCountFew' : 'v2CatCountMany');
  } else {
    key = a == 1 ? 'v2CatCountOne' : 'v2CatCountMany';
  }
  return tr.trArgs(key, {'n': n});
}

/// "3 dny".
String catDays(AppTranslations tr, int n) => '$n ${tr.daysWord(n)}';

/// "pá 23. 10. → ne 25. 10." (one date for a single-day range).
String catRange(AppTranslations tr, DateTime s, DateTime e) =>
    tripSameDay(s, e) ? tripShortDate(tr, s) : '${tripShortDate(tr, s)} → ${tripShortDate(tr, e)}';

/// Inclusive calendar days (same helper as the old screens).
int catDayCount(DateTime s, DateTime e) => calendarDaysInclusive(s, e);

/// Amount in the app currency (existing `Money.czk`, incl. the symbol).
String catMoney(num czk) => Money.czk(czk);

/// "Tvoje cena od" per day: cheapest list day price minus the rank % —
/// display only (PLAN §2.2.1 `cardFrom`). The booking form prices exactly.
double catFromPerDay(Motorcycle m, int pct) =>
    ((m.prices?.cheapest ?? 0) * (100 - pct) / 100).roundToDouble();

/// Nearest weekend (Fri–Sun; from today when it is already the weekend)
/// and the one after — the two date presets of the v2 date sheets.
(DateTime, DateTime) catWeekend(DateTime today, {int skip = 0}) {
  // Day arithmetic through the DateTime constructor (DST-safe).
  final wd = today.weekday; // 1 = Mon … 7 = Sun
  // Sat / Sun: the rest of this weekend; otherwise the coming Friday.
  final start = DateTime(today.year, today.month, today.day + (wd <= 5 ? 5 - wd : 0));
  final sunday = DateTime(start.year, start.month, start.day + (7 - start.weekday));
  if (skip == 0) return (start, sunday);
  return (
    DateTime(sunday.year, sunday.month, sunday.day + 5),
    DateTime(sunday.year, sunday.month, sunday.day + 7),
  );
}
