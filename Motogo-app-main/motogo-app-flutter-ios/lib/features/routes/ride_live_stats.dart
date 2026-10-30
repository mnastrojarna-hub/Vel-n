import '../../core/i18n/i18n_provider.dart';
import 'ride_motion.dart';

/// Živé součty rozjeté cesty (km, čas v sedle) a formátování pro UI
/// a notifikaci. Server je zdroj pravdy — tady se k jeho posledním součtům
/// jen přičítá ještě NEODESLANÁ dávka, stejným pravidlem jako na serveru
/// (`rideClassifyPair`: chůze, drift, pauza ani mezera km nepřidávají).

typedef RideLiveDelta = ({double km, int movingSec});

/// Ujeto a čas jízdy v [pts] (navazují na [prev] = poslední bod, který už
/// server má; null = začátek jízdy).
RideLiveDelta rideLiveDelta(List<double>? prev, List<List<double>> pts) {
  var km = 0.0;
  var sec = 0.0;
  var p = prev;
  for (final q in pts) {
    if (p != null) {
      final c = rideClassifyPair(p, q);
      if (c.kind == RidePairKind.moving || c.kind == RidePairKind.zeroDt) km += c.km;
      if (c.kind == RidePairKind.moving) sec += c.sec;
    }
    p = q;
  }
  return (km: km, movingSec: sec.round());
}

/// „12,3" / „123" (km) — desetinné místo pod 100 km, čárka podle jazyka.
String rideLiveKm(double km, [String lang = 'cs']) {
  final s = km.toStringAsFixed(km < 100 ? 1 : 0);
  return lang == 'en' ? s : s.replaceAll('.', ',');
}

/// „1 h 20 min" / „45 min" / „2 d 3 h" (vícedenní cesta).
String rideLiveDuration(int sec) {
  final min = (sec / 60).round();
  if (min < 60) return '$min min';
  final h = min ~/ 60;
  final m = min % 60;
  if (h >= 48) {
    final d = h ~/ 24;
    final rh = h % 24;
    return rh == 0 ? '$d d' : '$d d $rh h';
  }
  return m == 0 ? '$h h' : '$h h $m min';
}

/// Čas „20:14" (místní).
String rideClock(DateTime t) {
  final l = t.toLocal();
  return '${l.hour}:${l.minute.toString().padLeft(2, '0')}';
}

/// Epoch s → místní čas.
DateTime rideEpochToLocal(double ts) =>
    DateTime.fromMillisecondsSinceEpoch((ts * 1000).round()).toLocal();

/// Datum jako jinde v „Mých jízdách" („6. 10. 2026").
String rideShortDate(DateTime d) {
  final l = d.toLocal();
  return '${l.day}. ${l.month}. ${l.year}';
}

/// Tvar množného čísla: `One` / `Few` / `Many` (cs 1 / 2–4 / jinak; pl, uk
/// podle poslední číslice, 12–14 = Many; ostatní One/Many, fr 0 a 1 = One).
String ridePluralForm(int n, String lang) {
  final a = n.abs();
  final m10 = a % 10, m100 = a % 100;
  switch (lang) {
    case 'cs':
    case 'sk':
      return a == 1 ? 'One' : (a >= 2 && a <= 4 ? 'Few' : 'Many');
    case 'pl':
      if (a == 1) return 'One';
      return m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14) ? 'Few' : 'Many';
    case 'uk':
      if (m10 == 1 && m100 != 11) return 'One';
      return m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14) ? 'Few' : 'Many';
    case 'fr':
      return a <= 1 ? 'One' : 'Many';
    default:
      return a == 1 ? 'One' : 'Many';
  }
}

/// „3 dny" — klíče `rpDaysOne/Few/Many` (`{n}`).
String rideDaysLabel(int n, AppTranslations tr) =>
    tr.trArgs('rpDays${ridePluralForm(n, tr.lang)}', {'n': n});

/// „4 jízdy" — klíče `rpRidesOne/Few/Many` (`{n}`).
String rideRidesLabel(int n, AppTranslations tr) =>
    tr.trArgs('rpRides${ridePluralForm(n, tr.lang)}', {'n': n});

/// Hranice etapy (dne) — stejně jako server (`stages`): pauza ≥ 6 h, nebo
/// ≥ 30 min přes noc (00:00–05:00 místního času). Čas v epoch s.
bool rideIsStageBoundary(double from, double to) {
  final d = to - from;
  if (d >= 21600) return true;
  if (d < 1800) return false;
  final a = rideEpochToLocal(from), b = rideEpochToLocal(to);
  var day = DateTime(a.year, a.month, a.day);
  while (!day.isAfter(b)) {
    final nightEnd = DateTime(day.year, day.month, day.day, 5);
    if (day.isBefore(b) && nightEnd.isAfter(a)) return true;
    day = DateTime(day.year, day.month, day.day + 1);
  }
  return false;
}
