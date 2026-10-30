import 'dart:math' as math;

/// Čistý Dart pro rozpoznání jízdy / stání / chůze (žádné I/O, žádný
/// Riverpod, žádný geolocator) — testuje se syntetickými stopami.
/// Stavový automat pauz je v `ride_pause_engine.dart`, převod fixu
/// z geolocatoru v `ride_location.dart` (`rideFixFromPosition`).
///
/// Bod stopy = `[lat, lng, ts, kmh, alt?]` (beze změny tvaru). `kmh < 0`
/// (posíláme přesně −1) = ZNAČKA PAUZY: úsek od předchozího bodu je pauza
/// (server ho nepočítá do km ani do času na cestě).

/// Jeden GPS fix, jak ho vidí detektor. [ts] = epoch s (opravený o posun
/// hodin, 0,1 s), [acc] = přesnost v m (null = neznámá), [kmh] = PLATNÁ
/// Dopplerova rychlost (null = neznámá — neznámá rychlost NENÍ nula),
/// [alt] = výška (jen věrohodná).
class RideFix {
  const RideFix({
    required this.ts,
    required this.lat,
    required this.lng,
    this.acc,
    this.kmh,
    this.alt,
  });

  final double ts;
  final double lat;
  final double lng;
  final double? acc;
  final double? kmh;
  final double? alt;

  /// Přesný fix (silnice venku).
  bool get good => acc != null && acc! <= RideMotionConfig.goodAccM;

  /// Použitelný fix (bez přesnosti bereme jako použitelný).
  bool get usable => acc == null || acc! <= RideMotionConfig.usableAccM;
}

/// Prahy detekce (SPEC §6.1). ★ = přepisovatelné z flagu `ride_autopause`
/// (`conditions`: stop_min, walk_min, resume_kmh, home_h, long_h, idle_h).
class RideMotionConfig {
  const RideMotionConfig({
    this.stopPauseS = 300,
    this.walkPauseS = 180,
    this.resumeKmh = 20,
    this.homeAfterS = 3 * 3600,
    this.longPauseOwnS = 48 * 3600,
    this.idleDecisionS = 20 * 3600,
  });

  static const double goodAccM = 25;
  static const double usableAccM = 50;
  static const double dopMaxSpeedAccMs = 2.5;
  static const double walkMinKmh = 2;
  static const double walkMaxKmh = 8;
  static const double slowKmh = 12;
  static const double pairGapS = 15;
  static const int walkMinFixes = 3;
  static const double walkMinPathM = 50;
  static const double slowRideAfterS = 120;
  static const double slowRidePathM = 300;
  static const double slowRideMedianKmh = 8;
  static const double slowRideAvgKmh = 9;
  static const double pendingMaxS = 600;
  static const double silenceS = 180;
  static const double signalLostKmh = 30;
  static const double rideThroughKmh = 15;
  static const double silenceStillM = 150;
  static const double resumeAnchorM = 100;
  static const double resumeNoDopM = 300;
  static const double resumeNoDopWindowS = 60;
  static const double slowResumeKmh = 12;
  static const double slowResumeWindowS = 60;
  static const int slowResumeMinFixes = 4;
  static const double slowResumeAnchorM = 300;
  static const double prerollStartKmh = 8;
  static const double prerollMaxS = 180;
  static const int prerollMaxFixes = 60;
  static const double flagMinPauseS = 60;
  static const double restoreNearM = 100;
  static const double restoreMinPathM = 150;
  /// Pomalý úsek se vrací, když vede pryč od kotvy (posun ≥ 60 % dráhy).
  static const double restoreOneWay = 0.6;
  static const int pausePathMax = 1200;
  static const double killGapM = 1000;
  static const double homeRadiusM = 500;
  static const double homeMinKm = 10;
  /// Fix z cache = starší než připojení streamu o víc než tohle. 30 s
  /// + 120 s pásmo, ve kterém se posun hodin telefonu neopravuje (fix
  /// s časem GPS u telefonu, který jde o ≤ 2 min napřed, není z cache).
  static const double cachedFixSlackS = 150;
  /// Pojistka GPS mlčí 2 min po připojení streamu / otevření appky /
  /// Pokračovat a když poslední fixy ukazují pohyb (rozhodne obnova jízdy).
  static const double guardQuietS = 120;
  static const double guardMoveM = 100;
  /// Otázka po dlouhém stání padne až po tolika s poslechu GPS (rozjezd
  /// právě při otevření appky má přednost).
  static const double idleProbeS = 60;
  /// Bez Doppleru obnova jen přes 3 fixy A→B→C (každý krok ≥ tohle, C dál
  /// od kotvy než B) — přeskok polohy z Wi-Fi tam a zpět jízdu nespustí.
  static const double resumeNoDopStepKmh = 15;
  /// Kolik fixů s Dopplerem ≥ 12 km/h musí relace mít, aby se obnova
  /// bez Doppleru (pravidlo b) úplně vypnula — telefon rychlost měří.
  static const int dopplerSeenFixes = 3;
  /// Úsek s odvozenou rychlostí nad tohle je skok GPS (do dráhy se nepočítá).
  static const double jumpKmh = 150;

  /// ★ stání → pauza (s)
  final double stopPauseS;
  /// ★ chůze → pauza (s)
  final double walkPauseS;
  /// ★ obnova: 2× Doppler ≥ tohle (km/h)
  final double resumeKmh;
  /// ★ „doma": pauza u startu vlastní cesty déle než tohle → upozornění
  /// (GPS zůstává zapnuté, po rozjezdu se nahrává samo)
  final double homeAfterS;
  /// ★ dlouhá pauza vlastní cesty bez otevření appky → GPS vypnout
  /// (0 = vypnuto). Výchozí 48 h: noc ani den volna cestu neutne.
  final double longPauseOwnS;
  /// ★ vlastní cesta stojí déle než tohle (od zastavení / Pokračovat) →
  /// při otevření appky jen připomenout „cesta stojí od …" (GPS běží dál,
  /// rozjezd se nahraje sám; GPS vypne až [longPauseOwnS]); 0 = vypnuto.
  /// Výchozí 20 h: noc v hotelu nic.
  final double idleDecisionS;

  /// Výchozí prahy upravené flagem (neplatné hodnoty se ignorují).
  RideMotionConfig withFlag(
      {num? stopMin, num? walkMin, num? resumeKmh, num? homeH, num? longH, num? idleH}) {
    double? ok(num? v, double min, double max) =>
        v != null && v.isFinite && v >= min && v <= max ? v.toDouble() : null;
    return RideMotionConfig(
      stopPauseS: (ok(stopMin, 1, 120) ?? stopPauseS / 60) * 60,
      walkPauseS: (ok(walkMin, 1, 120) ?? walkPauseS / 60) * 60,
      resumeKmh: ok(resumeKmh, 8, 80) ?? this.resumeKmh,
      homeAfterS: (ok(homeH, 0.5, 72) ?? homeAfterS / 3600) * 3600,
      longPauseOwnS: (ok(longH, 0, 240) ?? longPauseOwnS / 3600) * 3600,
      idleDecisionS: (ok(idleH, 0, 240) ?? idleDecisionS / 3600) * 3600,
    );
  }
}

/// Vzdálenost v metrech (haversine, R = 6371 km — stejně jako server).
double rideDistM(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final h = math.pow(math.sin(rad(lat2 - lat1) / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(rad(lng2 - lng1) / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}

/// Vzdálenost dvou bodů stopy (m).
double ridePtDistM(List<double> a, List<double> b) => rideDistM(a[0], a[1], b[0], b[1]);

/// Vzdálenost fixu od bodu stopy (m).
double rideFixPtDistM(RideFix f, List<double> p) => rideDistM(f.lat, f.lng, p[0], p[1]);

/// Medián (prázdný seznam → null).
double? rideMedian(Iterable<double> xs) {
  final l = xs.toList()..sort();
  if (l.isEmpty) return null;
  final m = l.length ~/ 2;
  return l.length.isOdd ? l[m] : (l[m - 1] + l[m]) / 2;
}

/// Délka lomené čáry bodů (m); úseky „rychlejší" než skok GPS se vynechají.
double ridePathLenM(List<List<double>> pts) {
  var s = 0.0;
  for (var i = 1; i < pts.length; i++) {
    final d = ridePtDistM(pts[i - 1], pts[i]);
    final dt = pts[i][2] - pts[i - 1][2];
    if (dt > 0 && d / dt * 3.6 > RideMotionConfig.jumpKmh) continue;
    s += d;
  }
  return s;
}

double _r(double v, int dec) => double.parse(v.toStringAsFixed(dec));

/// Fix → bod stopy `[lat, lng, ts, kmh, alt?]`, nebo null, když do stopy
/// nepatří: přesnost v km vždy; horší než 50 m při stání (drift v budově);
/// čas jdoucí zpět; posun pod 20 m od [last] (vlastní filtr vzdálenosti —
/// stream může být sdílený s navigací s hustším filtrem).
List<double>? ridePointFromRideFix(RideFix f, List<double>? last) {
  final kmh = f.kmh ?? 0;
  final acc = f.acc;
  if (acc != null && (acc > 500 || (acc > RideMotionConfig.usableAccM && kmh < 3))) return null;
  final lat = _r(f.lat, 5);
  final lng = _r(f.lng, 5);
  if (last != null && last.length > 2) {
    if (f.ts < last[2]) return null;
    if (rideDistM(last[0], last[1], lat, lng) < 20) return null;
  }
  return <double>[
    lat,
    lng,
    f.ts,
    kmh > 300 ? 0 : _r(kmh, 1),
    if (f.alt != null) _r(f.alt!, 1),
  ];
}

/// Druh dvojice bodů — ZRCADLO serverového `_ride_stats_v2` (SPEC §3.2),
/// aby živé km v appce seděly s tím, co pak spočítá server.
enum RidePairKind { noTime, badTime, pause, gap, inferredPause, stop, jump, zeroDt, moving, nonMoving }

/// Výsledek klasifikace: [km] = co se přičte k ujetým km, [sec] = čas
/// (jízdy / mezery / pauzy podle druhu).
typedef RidePair = ({RidePairKind kind, double km, double sec});

double _dop(List<double> p) => p.length > 3 && p[3] > 0 && p[3] < 250 ? p[3] : 0;

RidePair rideClassifyPair(List<double> p, List<double> q) {
  final d = rideDistM(p[0], p[1], q[0], q[1]) / 1000;
  if (p.length < 3 || q.length < 3) return (kind: RidePairKind.noTime, km: d, sec: 0);
  final dt = q[2] - p[2];
  if (dt < 0 || dt >= 2592000) return (kind: RidePairKind.badTime, km: 0, sec: 0);
  if (q.length > 3 && q[3] < 0) return (kind: RidePairKind.pause, km: 0, sec: dt);
  final v = dt > 0 ? d / dt * 3600 : null;
  if (dt > 180) {
    if (v! >= 15 && d > 0.3) return (kind: RidePairKind.gap, km: 0, sec: dt);
    if (dt >= 300) return (kind: RidePairKind.inferredPause, km: 0, sec: dt);
    return (kind: RidePairKind.stop, km: 0, sec: 0);
  }
  if ((v != null && v >= 250) || (dt == 0 && d >= 0.5)) {
    return (kind: RidePairKind.jump, km: 0, sec: 0);
  }
  final dp = _dop(p), dq = _dop(q);
  final dop = math.max(dp, dq);
  if (dt == 0) {
    return dop >= 7
        ? (kind: RidePairKind.zeroDt, km: d, sec: 0)
        : (kind: RidePairKind.nonMoving, km: 0, sec: 0);
  }
  if (v! >= 3 && (dop >= 7 || (dp == 0 && dq == 0 && dt >= 3 && v >= 15))) {
    return (kind: RidePairKind.moving, km: d, sec: dt);
  }
  return (kind: RidePairKind.nonMoving, km: 0, sec: 0);
}

/// Je dvojice JÍZDA (pravidlo 7 serveru)? Chůze a drift km nepřidávají.
bool rideIsMovingPair(List<double> p, List<double> q) =>
    rideClassifyPair(p, q).kind == RidePairKind.moving;

typedef _K = RideMotionConfig;

/// Verdikt pomalého úseku (stav `pending` automatu).
enum RidePendingVerdict { none, stop, walk, release }

/// Rozhodovací pravidla detektoru (SPEC §6.3) — čisté funkce nad fixy
/// a body, stav drží `RidePauseEngine`.
class RideMotionDetector {
  const RideMotionDetector(this.cfg);
  final RideMotionConfig cfg;

  static double? _v(RideFix a, RideFix b) {
    final dt = b.ts - a.ts;
    return dt > 0 ? rideDistM(a.lat, a.lng, b.lat, b.lng) / dt * 3.6 : null;
  }

  /// Pomalý fix: Doppler ≤ 12 km/h, nebo bez Doppleru malý posun.
  bool isSlow(RideFix f, RideFix? prev) {
    if (f.kmh != null) return f.kmh! <= RideMotionConfig.slowKmh;
    if (prev == null || !f.usable || !prev.usable || f.ts - prev.ts < 5) return false;
    final v = _v(prev, f);
    return v != null && v <= RideMotionConfig.slowKmh;
  }

  /// Uvolnění zadržených bodů: dva po sobě jdoucí rychlé fixy.
  bool released(RideFix f, RideFix? prev, RideFix? prev2) {
    const s = RideMotionConfig.slowKmh;
    if (prev == null) return false;
    if (f.kmh != null) {
      return f.kmh! > s && prev.kmh != null && prev.kmh! > s && f.ts - prev.ts <= RideMotionConfig.pairGapS;
    }
    if (prev2 == null || !f.usable || !prev.usable) return false;
    bool fast(RideFix a, RideFix b) {
      final dt = b.ts - a.ts;
      final v = _v(a, b);
      return dt >= 3 && dt <= 30 && v != null && v > s && v < 250;
    }
    return fast(prev, f) && fast(prev2, prev);
  }

  /// Poloměr „stojí na místě": 1,5 × medián přesnosti, 40–100 m.
  double stillRadius(List<double> accHist) {
    final m = rideMedian(accHist);
    return m == null ? 40 : (1.5 * m).clamp(40.0, 100.0);
  }

  /// Rozhodnutí v pomalém úseku (při fixu i časovačem).
  RidePendingVerdict evalPending({
    required double now,
    required double slowSince,
    required List<double>? anchor,
    required List<RideFix> fixes,
    required List<List<double>> pathPts,
    required double rStill,
    required RideFix? lastFix,
  }) {
    final dur = now - slowSince;
    if (dur <= 0) return RidePendingVerdict.none;
    final good = fixes.where((f) => f.good).toList();
    final out = anchor == null
        ? 0
        : good.where((f) => rideFixPtDistM(f, anchor) > rStill).length;
    // Jeden ojedinělý skok GPS (nebo ~10 %) stání nezkazí.
    final allowed = math.max(1, good.length ~/ 10);
    if (dur >= cfg.stopPauseS && out <= allowed) return RidePendingVerdict.stop;
    final dops = [for (final f in fixes) if (f.kmh != null) f.kmh!];
    final path = ridePathLenM(pathPts);
    final avg = path / dur * 3.6;
    final med = rideMedian(dops);
    // Doppler rozhoduje až od 3 vzorků — jediný vzorek z brzdění (8,6 km/h)
    // před chůzí bez rychlosti by jinak z procházky udělal „pomalou jízdu".
    final byDop = dops.length >= _K.walkMinFixes;
    if (dur >= cfg.walkPauseS &&
        dops.every((k) => k <= _K.slowKmh) &&
        path >= _K.walkMinPathM &&
        (byDop ? med! >= _K.walkMinKmh && med <= _K.walkMaxKmh : avg <= _K.walkMaxKmh)) {
      return RidePendingVerdict.walk;
    }
    if (dur >= _K.slowRideAfterS &&
        path >= _K.slowRidePathM &&
        // Doppler má přednost (skok GPS by průměr z dráhy nafoukl).
        (byDop ? med! > _K.slowRideMedianKmh : avg > _K.slowRideAvgKmh)) {
      return RidePendingVerdict.release;
    }
    if (dur >= _K.pendingMaxS) {
      final near = anchor == null || lastFix == null ||
          rideFixPtDistM(lastFix, anchor) <= _K.silenceStillM;
      return near ? RidePendingVerdict.stop : RidePendingVerdict.walk;
    }
    return RidePendingVerdict.none;
  }

  bool _far(RideFix f, List<double>? anchor, double m) =>
      anchor == null || rideFixPtDistM(f, anchor) >= m;

  /// Pravidla obnovy jízdy během auto-pauzy. Vrací index PRVNÍHO fixu
  /// spouštěče v [ring], jinak null.
  ///  (a) 2 po sobě jdoucí Doppler ≥ resumeKmh, ≤ 15 s od sebe, ≥ 100 m od kotvy
  ///  (b) bez Doppleru: přesné fixy A→B→C do 60 s, A–C ≥ 300 m, každý krok
  ///      ≥ 15 km/h, C dál od kotvy než B, C ≥ 300 m od kotvy. Jen když
  ///      telefon v relaci rychlost neměří ([dopplerSeen] = false) — polohy
  ///      z Wi-Fi rychlost nemají a v noci „skáčou" stovky metrů.
  ///  (c) pomalý rozjezd: za 60 s ≥ 4 Doppler s mediánem ≥ 12, ≥ 300 m od kotvy
  int? resumeTrigger(List<RideFix> ring, List<double>? anchor, {bool dopplerSeen = false}) {
    final n = ring.length;
    if (n == 0) return null;
    final y = ring.last;
    if (n >= 2) {
      final x = ring[n - 2];
      if ((x.kmh ?? 0) >= cfg.resumeKmh &&
          (y.kmh ?? 0) >= cfg.resumeKmh &&
          y.ts - x.ts <= _K.pairGapS &&
          _far(y, anchor, _K.resumeAnchorM)) {
        return n - 2;
      }
    }
    bool still(RideFix f) => f.kmh != null && f.kmh! < _K.slowKmh;
    if (!dopplerSeen && y.good && !still(y) && _far(y, anchor, _K.resumeNoDopM)) {
      bool step(RideFix a, RideFix b) {
        final v = _v(a, b);
        return v != null && v >= _K.resumeNoDopStepKmh && v < 250;
      }
      for (var i = 0; i < n - 2; i++) {
        final x = ring[i];
        final dt = y.ts - x.ts;
        if (!x.good || still(x) || dt <= 0 || dt > _K.resumeNoDopWindowS) continue;
        if (rideDistM(x.lat, x.lng, y.lat, y.lng) < _K.resumeNoDopM || !step(x, y)) continue;
        double from(RideFix f) => anchor != null
            ? rideFixPtDistM(f, anchor)
            : rideDistM(x.lat, x.lng, f.lat, f.lng);
        for (var j = i + 1; j < n - 1; j++) {
          final b = ring[j];
          if (b.good && !still(b) && step(x, b) && step(b, y) && from(y) > from(b)) return i;
        }
      }
    }
    var first = -1;
    final dops = <double>[];
    for (var i = 0; i < n; i++) {
      final f = ring[i];
      if (f.ts < y.ts - _K.slowResumeWindowS || f.kmh == null) continue;
      if (first < 0) first = i;
      dops.add(f.kmh!);
    }
    if (dops.length >= _K.slowResumeMinFixes &&
        rideMedian(dops)! >= _K.slowResumeKmh &&
        _far(y, anchor, _K.slowResumeAnchorM)) {
      return first;
    }
    return null;
  }

  /// Začátek předjezdu: nejstarší fix souvislého běhu (končícího
  /// posledním fixem) s Dopplerem ≥ 8 km/h, jinak první fix spouštěče.
  int preRollStart(List<RideFix> ring, int trigger) {
    var j = ring.length - 1;
    while (j >= 0 && ring[j].kmh != null && ring[j].kmh! >= _K.prerollStartKmh) {
      j--;
    }
    return j + 1 <= ring.length - 1 ? j + 1 : trigger;
  }
}
