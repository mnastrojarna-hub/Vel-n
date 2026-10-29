part of 'ride_pause_engine.dart';

/// Pojistky pauzy vlastní cesty a pomocná pravidla obnovy (SPEC §6.3) —
/// část `RidePauseEngine`, čistý Dart bez I/O.
extension _RidePauseGuards on RidePauseEngine {
  /// Obnovit do stopy jen úsek, kudy JELA motorka: kolona / hledání
  /// parkování (průměr úseku nebo medián jeho Doppleru > 8 km/h), nebo
  /// plazení, které vede jedním směrem pryč od kotvy. Procházka tam
  /// a zpátky (chůzí) se nevrací nikdy.
  bool _restoreOk(List<List<double>> seg, List<double>? base, double len) {
    final from = base ?? seg.first;
    final dt = seg.last[2] - from[2];
    if (dt > 0 && len / dt * 3.6 > _C.walkMaxKmh) return true;
    final dops = [for (final p in seg) if (p.length > 3 && p[3] > 0) p[3]];
    if (dops.length >= _C.walkMinFixes && rideMedian(dops)! > _C.walkMaxKmh) return true;
    return ridePtDistM(from, seg.last) >= _C.restoreOneWay * len;
  }

  /// Poslední fixy (≤ 2 min) ukazují pohyb → pojistky počkají, o rozjezdu
  /// rozhodne obnova jízdy.
  bool _recentMotion(double now) {
    final a = _anchor;
    for (var i = _ring.length - 1; i >= 0; i--) {
      final f = _ring[i];
      if (now - f.ts > _C.guardQuietS) break;
      if ((f.kmh ?? 0) >= _C.slowKmh) return true;
      if (a != null && f.usable && rideFixPtDistM(f, a) >= _C.guardMoveM) return true;
    }
    return false;
  }

  /// Vlastní cesta: „doma" = jen upozornění (GPS běží, rozjezd se nahraje
  /// sám), „dlouhá pauza" bez kontaktu s jezdcem (výchozí 48 h) = GPS
  /// vypnout. Ne hned po připojení / otevření appky / Pokračovat a ne,
  /// když se zrovna hýbe. Vícedenní cesta (≥ 2 etapy) „doma" nehlásí.
  void _guards(RideEngineStep s, double now, double liveKm, int stages) {
    final since = _pausedSince;
    if (!own || since == null) return;
    final gf = _guardFrom;
    if (gf != null && now - gf < _C.guardQuietS) return;
    if (_recentMotion(now)) return;
    final from = gf != null && gf > since ? gf : since;
    final r = _reason;
    final ts = _tripStart, a = _anchor;
    final away = r == RidePauseReason.stop || r == RidePauseReason.walk || r == RidePauseReason.silence;
    if (!_homeNoticed && away && stages < 2 && ts != null && a != null &&
        ridePtDistM(a, ts) <= _C.homeRadiusM &&
        now - from >= _cfg.homeAfterS &&
        liveKm >= _C.homeMinKm) {
      _homeNoticed = true;
      s.homeNotice = true;
      s.logs.add(RideEngineLog('home_notice', data: {'since': since, 'h': ((now - since) / 360).round() / 10}));
    }
    if (_cfg.longPauseOwnS > 0 && now - from >= _cfg.longPauseOwnS) {
      _guard(s, RidePauseReason.long, now - since);
    }
  }

  void _guard(RideEngineStep s, RidePauseReason r, double dur) {
    _ring.clear();
    _pausePath.clear();
    _manual = true;
    _reason = r;
    s.detach = true;
    s.phaseChanged = true;
    s.logs.add(RideEngineLog(r == RidePauseReason.home ? 'home_pause' : 'long_pause',
        data: {'since': _pausedSince, 'h': (dur / 360).round() / 10}));
  }
}
