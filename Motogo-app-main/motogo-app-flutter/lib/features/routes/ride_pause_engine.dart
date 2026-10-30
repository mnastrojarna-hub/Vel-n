import 'dart:math' as math;

import 'ride_motion.dart';
import 'ride_session.dart';

part 'ride_pause_guards.dart';

/// Stavový automat pauz záznamu jízdy (SPEC §6) — čistý Dart, bez I/O.
/// Dostává fixy (`onFix`), tiky časovače (`onTick`) a ruční povely; vrací
/// [RideEngineStep]: body k odeslání, změnu fáze, odpojení GPS, logy.
///
///   riding  → body jdou rovnou do dávky
///   pending → zpomalil (≤ 12 km/h): body se DRŽÍ, dokud se nerozhodne,
///             jestli stojí / jde pěšky (→ pauza), nebo jede pomalu (→ odeslat)
///   paused  → auto-pauza (GPS běží, nic se neposílá; čeká na rozjezd)
///             nebo ruční pauza / pojistka (GPS odpojené)
/// První bod po pauze ≥ 60 s nese značku `kmh = −1` → server mezi ním
/// a předchozím bodem počítá pauzu (žádné km, žádný čas na cestě).

class RideEngineLog {
  const RideEngineLog(this.action, {this.detail, this.data = const {}});
  final String action;
  final String? detail;
  final Map<String, dynamic> data;
}

class RideEngineStep {
  final List<List<double>> emit = [];
  final List<RideEngineLog> logs = [];
  bool phaseChanged = false;
  /// Odpojit GPS stream (ruční pauza, pojistka „dlouhá pauza").
  bool detach = false;
  /// Vlastní cesta stojí u svého startu (doma?) — jen upozornit jezdce;
  /// GPS běží dál a po rozjezdu se nahrává samo.
  bool homeNotice = false;
  /// Rozhodnutí při otevření appky: vlastní cesta stojí ≥ 20 h → GPS vypnout
  /// a zeptat se „Pokračovat v cestě / Ukončit a uložit" (jezdec appku
  /// právě vidí → bez notifikace, jen hláška).
  bool idle = false;
  /// Nejvyšší SKUTEČNÁ Dopplerova rychlost vyslaných bodů (před značkou).
  double maxKmh = 0;
  bool get isEmpty => emit.isEmpty && logs.isEmpty && !phaseChanged && !detach && !homeNotice && !idle;
}

enum _Mode { riding, pending, paused }

typedef _C = RideMotionConfig;

class RidePauseEngine {
  RidePauseEngine({RideMotionConfig cfg = const RideMotionConfig(), required this.own, this.autoPauseOn = true})
      : _cfg = cfg,
        _det = RideMotionDetector(cfg);

  RideMotionConfig _cfg;
  RideMotionDetector _det;
  /// Vlastní cesta (bez výpůjčky) — jen ta má upozornění „doma" a pojistku
  /// „dlouhá pauza".
  bool own;
  /// Flag `ride_autopause` (kill-switch): false = nahrává se vše jako dřív.
  bool autoPauseOn;

  _Mode _mode = _Mode.riding;
  bool _manual = false;
  RidePauseReason? _reason;
  double? _pausedSince;
  List<double>? _anchor;
  bool _anchorHeld = false;
  List<double>? _lastEmitted;
  List<double>? _tripStart;
  final List<List<double>> _held = [];
  final List<RideFix> _pend = [];
  double? _slowSince;
  final List<List<double>> _pausePath = [];
  final List<RideFix> _ring = [];
  RideFix? _lastFix;
  RideFix? _prevFix;
  double? _lastDopKmh;
  final List<double> _accHist = [];
  bool _restored = false;
  bool _awaitP0 = false;
  double? _attachedAt;
  bool _freshAttach = false;
  double? _flagFrom;
  /// Jezdec výslovně pokračuje (Pokračovat / připojení streamu klepnutím) —
  /// pojistka „dlouhá pauza" i rozhodnutí při otevření počítají od
  /// pozdějšího z tohohle a začátku pauzy. Pouhé otevření appky ani
  /// automatické připojení streamu je NEPRODLUŽUJE (zapomenutý Stop).
  double? _guardFrom;
  /// Poslední kontakt (připojení streamu, otevření appky, Pokračovat):
  /// 2 min potom pojistky mlčí.
  double? _quietFrom;
  bool _homeNoticed = false;
  /// Fixy s Dopplerem ≥ 12 km/h v relaci (telefon rychlost měří).
  int _dopMoving = 0;

  RidePhase get phase => _mode != _Mode.paused
      ? RidePhase.riding
      : (_manual ? RidePhase.manualPaused : RidePhase.autoPaused);
  RidePauseReason? get reason => _mode == _Mode.paused ? _reason : null;
  double? get pausedSince => _mode == _Mode.paused ? _pausedSince : null;
  List<double>? get anchor => _anchor;
  List<double>? get lastEmitted => _lastEmitted;
  List<double>? get tripStart => _tripStart;
  bool get isPending => _mode == _Mode.pending;
  bool get isArmed => phase == RidePhase.autoPaused && _reason == RidePauseReason.start;
  RideMotionConfig get config => _cfg;

  // ───────────────────────── životní cyklus ─────────────────────────

  /// Nový záznam: „připraveno" — první použitelný fix se vyšle hned jako P0
  /// (Velín vidí polohu), nahrávat se začne až po rozjezdu.
  void startArmed() {
    _clearBuffers();
    _manual = false;
    _restored = false;
    _homeNoticed = false;
    _lastEmitted = null;
    _tripStart = null;
    _anchor = null;
    _flagFrom = null;
    if (autoPauseOn) {
      _mode = _Mode.paused;
      _reason = RidePauseReason.start;
      _pausedSince = null;
      _awaitP0 = true;
    } else {
      _mode = _Mode.riding;
      _reason = null;
      _awaitP0 = false;
    }
  }

  /// Obnova po restartu / zabití appky (SPEC §7.2).
  void restore({
    required RidePhase phase,
    RidePauseReason? reason,
    double? since,
    List<double>? anchor,
    List<double>? last,
    List<double>? start,
    bool restored = true,
  }) {
    _clearBuffers();
    _lastEmitted = last;
    _tripStart = start;
    _anchor = anchor ?? last;
    _flagFrom = null;
    if (phase == RidePhase.manualPaused) {
      _mode = _Mode.paused;
      _manual = true;
      _reason = reason ?? RidePauseReason.manual;
      _pausedSince = since ?? _anchor?[2];
      return;
    }
    _manual = false;
    if (!autoPauseOn) {
      _mode = _Mode.riding;
      _reason = null;
      return;
    }
    _mode = _Mode.paused;
    _reason = RidePauseReason.start;
    _pausedSince = since ?? _anchor?[2];
    _restored = restored;
    _awaitP0 = _anchor == null;
  }

  /// Stream se (znovu) připojil — první fix starší než tohle je z cache.
  /// [byTap] = připojení klepnutím (ruční start / Pokračovat) → pojistka
  /// počítá znovu; obnova / návrat do appky jen 2 min ticha.
  void onAttach(double now, {bool byTap = false}) {
    _attachedAt = now;
    _freshAttach = true;
    noteForeground(now);
    if (byTap) _noteDecision(now);
  }

  /// Posun hodin se dozvěděl až po připojení streamu (odpověď serveru) →
  /// čas připojení přepočítat na stejnou osu jako časy fixů.
  void rebaseAttach(double at) {
    final a = _attachedAt;
    if (a == null) return;
    _attachedAt = at;
    final g = _guardFrom, q = _quietFrom;
    if (g != null) _guardFrom = g + (at - a);
    if (q != null) _quietFrom = q + (at - a);
  }

  /// Jezdec má appku v popředí → 2 min ticha pojistek. Pojistku „dlouhá
  /// pauza" NEPRODLUŽUJE: zapomenutý Stop po cestě by jinak držel GPS
  /// zapnuté dny a další jízdy tiše přidával ke staré cestě.
  void noteForeground(double now) {
    final q = _quietFrom;
    if (q == null || now > q) _quietFrom = now;
  }

  void _noteDecision(double now) {
    final g = _guardFrom;
    if (g == null || now > g) _guardFrom = now;
  }

  /// Otevření appky / obnova po restartu: vlastní cesta stojí (auto-pauza
  /// nebo „připraveno") déle než `idleDecisionS` (výchozí 20 h) od zastavení
  /// nebo od posledního Pokračovat → GPS vypnout a zeptat se (ruční pauza,
  /// důvod `long` = „Pokračovat v cestě / Ukončit a uložit"). Noc v hotelu
  /// (≤ 20 h) se neptá; když se motorka právě hýbe, rozhodne obnova jízdy.
  RideEngineStep decideIdle(double now) {
    final s = RideEngineStep();
    final since = _pausedSince;
    if (!own || !autoPauseOn || _manual || _mode != _Mode.paused || since == null) return s;
    if (_cfg.idleDecisionS <= 0) return s;
    final g = _guardFrom;
    final from = g != null && g > since ? g : since;
    if (now - from < _cfg.idleDecisionS || _recentMotion(now)) return s;
    _guard(s, RidePauseReason.long, now - since, by: 'open');
    s.idle = true;
    return s;
  }

  /// Nové prahy / zapnutí-vypnutí auto-pauzy (flag) za běhu.
  RideEngineStep applyConfig(RideMotionConfig cfg, bool on) {
    _cfg = cfg;
    _det = RideMotionDetector(cfg);
    final s = RideEngineStep();
    if (on == autoPauseOn) return s;
    autoPauseOn = on;
    if (on || _manual) return s;
    if (_mode == _Mode.pending) {
      _release(s);
    } else if (_mode == _Mode.paused) {
      _flagFrom = _awaitP0 ? null : _pausedSince;
      _toRiding();
      s.phaseChanged = true;
    }
    return s;
  }

  // ───────────────────────── vstupy ─────────────────────────

  RideEngineStep onFix(RideFix f) {
    final s = RideEngineStep();
    if (_manual) return s; // GPS má být odpojené; zbloudilý fix nic nemění
    if (_freshAttach && _attachedAt != null && f.ts < _attachedAt! - _C.cachedFixSlackS) return s;
    if (_lastFix != null && f.ts <= _lastFix!.ts) return s;
    _freshAttach = false;
    if (f.kmh != null && f.kmh! >= _C.slowKmh && _dopMoving < 1000) _dopMoving++;
    if (f.acc != null && f.usable) {
      _accHist.add(f.acc!);
      if (_accHist.length > 5) _accHist.removeAt(0);
    }
    if (!autoPauseOn) {
      final p = ridePointFromRideFix(f, _lastEmitted);
      if (p != null) _emit(s, p);
      _advance(f);
      return s;
    }
    if (_awaitP0 && _mode == _Mode.paused && f.usable) {
      final p = ridePointFromRideFix(f, null);
      if (p != null) {
        _emit(s, p);
        _anchor = p;
        _pausedSince = p[2];
        _awaitP0 = false;
      }
    }
    if (_mode != _Mode.paused && _lastFix != null && f.ts - _lastFix!.ts > _C.silenceS) {
      _silence(s, f);
    }
    switch (_mode) {
      case _Mode.riding:
        if (_det.isSlow(f, _lastFix)) {
          _enterPending(f.ts, fromEmitted: false);
          _pend.add(f);
          _addHeld(f);
        } else {
          final p = ridePointFromRideFix(f, _lastEmitted);
          if (p != null) _emit(s, p);
        }
      case _Mode.pending:
        if (_pend.length < 2000) _pend.add(f);
        _addHeld(f);
        if (_det.released(f, _lastFix, _prevFix)) {
          _release(s);
        } else {
          _evalPending(s, f.ts);
        }
      case _Mode.paused:
        _ring.add(f);
        while (_ring.length > _C.prerollMaxFixes ||
            (_ring.isNotEmpty && _ring.first.ts < f.ts - _C.prerollMaxS)) {
          _ring.removeAt(0);
        }
        _addPausePath(f);
        final t = _det.resumeTrigger(_ring, _anchor, dopplerSeen: _dopMoving >= _C.dopplerSeenFixes);
        if (t != null) _resume(s, t);
    }
    _advance(f);
    return s;
  }

  /// Časovač (90 s; 30 s v pomalém úseku). [liveKm] = ujeto v cestě,
  /// [stages] = počet etap (dnů) cesty (upozornění „doma" ho od 2026-10-30
  /// nepotřebuje — základní tábor dostane jen připomínku).
  RideEngineStep onTick(double now, {double liveKm = 0, int stages = 1}) {
    final s = RideEngineStep();
    if (!autoPauseOn || _manual) return s;
    final lf = _lastFix;
    if (_mode == _Mode.riding && lf != null && now - lf.ts >= _C.silenceS &&
        (_lastDopKmh ?? 0) < _C.signalLostKmh) {
      // Dlouho žádný fix po pomalé jízdě = nejspíš stojí (filtr 20 m).
      // Po rychlé jízdě (tunel) se nečasuje — rozhodne až další fix.
      _enterPending(lf.ts, fromEmitted: true);
    }
    if (_mode == _Mode.pending) _evalPending(s, now);
    if (_mode == _Mode.paused) _guards(s, now, liveKm);
    return s;
  }

  /// Ruční pauza (jezdec klepl): GPS se odpojí, pokračuje se jen klepnutím.
  RideEngineStep pauseManual(double now) {
    final s = RideEngineStep();
    if (_manual) return s;
    if (_mode == _Mode.pending) {
      final a = _anchor ?? _lastEmitted;
      if (_anchorHeld && a != null) _emit(s, a);
      _anchor = a;
      _pausedSince = a?[2] ?? now;
    } else if (_mode == _Mode.riding) {
      _anchor = _lastEmitted;
      _pausedSince = _anchor?[2] ?? now;
    } else {
      _pausedSince ??= now;
    }
    final held = _held.length;
    _clearBuffers();
    _mode = _Mode.paused;
    _manual = true;
    _reason = RidePauseReason.manual;
    s.detach = true;
    s.phaseChanged = true;
    s.logs.add(RideEngineLog('pause', detail: 'manual', data: {
      'reason': 'manual',
      'since': _pausedSince,
      'held': held,
    }));
    return s;
  }

  /// Pokračovat po ruční pauze → „připraveno" (pauza trvá do rozjezdu;
  /// první bod po rozjezdu dostane značku pauzy). [now] = čas klepnutí:
  /// pojistka „dlouhá pauza" od něj počítá znovu (jinak by ji další tik
  /// hned spustil a GPS zase vypnul).
  RideEngineStep resumeManual([double? now]) {
    final s = RideEngineStep();
    if (!_manual) return s;
    final was = _reason;
    if (now != null) {
      noteForeground(now);
      _noteDecision(now);
    }
    _manual = false;
    _restored = false;
    _homeNoticed = false;
    _ring.clear();
    _pausePath.clear();
    if (autoPauseOn) {
      _mode = _Mode.paused;
      _reason = RidePauseReason.start;
      _anchor ??= _lastEmitted;
      _awaitP0 = _anchor == null;
    } else {
      _flagFrom = _pausedSince;
      _toRiding();
    }
    s.phaseChanged = true;
    s.logs.add(RideEngineLog('resume', detail: 'manual', data: {'mode': 'manual', 'from': was?.name}));
    return s;
  }

  /// Ukončení záznamu: z pomalého úseku se pošle jen kotva (místo, kde
  /// motorka zastavila); během pauzy nic — server cestu ukončí u kotvy.
  RideEngineStep stopFlush() {
    final s = RideEngineStep();
    if (_mode == _Mode.pending && _anchorHeld && _anchor != null) _emit(s, _anchor!);
    _clearBuffers();
    return s;
  }

  // ───────────────────────── vnitřek ─────────────────────────

  void _clearBuffers() {
    _held.clear();
    _pend.clear();
    _ring.clear();
    _pausePath.clear();
    _anchorHeld = false;
    _slowSince = null;
  }

  void _toRiding() {
    _clearBuffers();
    _mode = _Mode.riding;
    _reason = null;
    _pausedSince = null;
    _anchor = null;
    _restored = false;
    _awaitP0 = false;
  }

  void _advance(RideFix f) {
    _prevFix = _lastFix;
    _lastFix = f;
    if (f.kmh != null) _lastDopKmh = f.kmh;
  }

  void _emit(RideEngineStep s, List<double> p, {bool flag = false}) {
    if (p.length > 3 && p[3] > s.maxKmh) s.maxKmh = p[3];
    var fl = flag;
    if (!fl && _flagFrom != null) {
      fl = p[2] - _flagFrom! >= _C.flagMinPauseS;
      _flagFrom = null;
    }
    if (fl && p.length > 3) p[3] = -1;
    s.emit.add(p);
    _lastEmitted = p;
    _tripStart ??= p;
  }

  void _enterPending(double since, {required bool fromEmitted}) {
    _clearBuffers();
    _mode = _Mode.pending;
    _slowSince = since;
    _anchor = fromEmitted ? _lastEmitted : null;
  }

  void _addHeld(RideFix f) {
    if (_held.length >= 3000) return;
    final p = ridePointFromRideFix(f, _held.isNotEmpty ? _held.last : _lastEmitted);
    if (p == null) return;
    _held.add(p);
    if (_anchor == null) {
      _anchor = p;
      _anchorHeld = true;
    }
  }

  void _addPausePath(RideFix f) {
    if (_pausePath.length >= _C.pausePathMax) return;
    final p = ridePointFromRideFix(f, _pausePath.isNotEmpty ? _pausePath.last : _anchor);
    if (p != null) _pausePath.add(p);
  }

  void _release(RideEngineStep s) {
    final held = List<List<double>>.from(_held);
    _toRiding();
    for (final p in held) {
      _emit(s, p);
    }
  }

  void _evalPending(RideEngineStep s, double now) {
    final a = _anchor ?? _lastEmitted;
    final v = _det.evalPending(
      now: now,
      slowSince: _slowSince ?? now,
      anchor: a,
      fixes: _pend,
      pathPts: [if (a != null && !_anchorHeld) a, ..._held],
      rStill: _det.stillRadius(_accHist),
      lastFix: _lastFix,
    );
    switch (v) {
      case RidePendingVerdict.stop:
        _autoPause(s, RidePauseReason.stop);
      case RidePendingVerdict.walk:
        _autoPause(s, RidePauseReason.walk);
      case RidePendingVerdict.release:
        _release(s);
      case RidePendingVerdict.none:
        break;
    }
  }

  void _autoPause(RideEngineStep s, RidePauseReason r) {
    final a = _anchor ?? _lastEmitted;
    if (_anchorHeld && a != null) _emit(s, a);
    final walkPath = r == RidePauseReason.walk
        ? _held.skip(_anchorHeld ? 1 : 0).toList()
        : const <List<double>>[];
    final held = _held.length;
    final lf = _lastFix;
    _clearBuffers();
    _pausePath.addAll(walkPath);
    _mode = _Mode.paused;
    _manual = false;
    _homeNoticed = false;
    _reason = r;
    _anchor = a;
    _pausedSince = a?[2] ?? lf?.ts;
    s.phaseChanged = true;
    s.logs.add(RideEngineLog('pause', detail: r.name, data: {
      'reason': r.name,
      'since': _pausedSince,
      if (a != null && lf != null) 'm': rideFixPtDistM(lf, a).round(),
      'held': held,
    }));
  }

  void _silence(RideEngineStep s, RideFix f) {
    final lf = _lastFix!;
    final dt = f.ts - lf.ts;
    final d = rideDistM(lf.lat, lf.lng, f.lat, f.lng);
    if (d / dt * 3.6 >= _C.rideThroughKmh) {
      // Projel (tunel, uspaný telefon) — server z toho udělá mezeru bez km.
      if (_mode == _Mode.pending) _release(s);
      return;
    }
    if (d <= math.max(_det.stillRadius(_accHist), _C.silenceStillM)) {
      if (dt >= _cfg.stopPauseS) {
        _autoPause(s, RidePauseReason.silence);
      } else if (_mode == _Mode.riding) {
        _enterPending(lf.ts, fromEmitted: true);
      }
      return;
    }
    _autoPause(s, RidePauseReason.walk); // odešel pěšky (garáž → ven)
  }

  void _resume(RideEngineStep s, int trigger) {
    final ri = _det.preRollStart(_ring, trigger);
    final r = _ring[ri];
    var base = _anchor;
    if (_reason == RidePauseReason.walk && _pausePath.isNotEmpty) {
      // Pomalý úsek (kolona, hledání parkování) vrátit do stopy, procházka
      // tam a zpět k motorce se nevrací (i* ≈ 0).
      var iStar = -1;
      for (var i = 0; i < _pausePath.length; i++) {
        if (rideFixPtDistM(r, _pausePath[i]) <= _C.restoreNearM) {
          iStar = i;
          break;
        }
      }
      if (iStar >= 0) {
        final seg = _pausePath.sublist(0, iStar + 1);
        final len = ridePathLenM([if (base != null) base, ...seg]);
        if (len >= _C.restoreMinPathM && _restoreOk(seg, base, len)) {
          for (final p in seg) {
            _emit(s, p);
          }
          base = seg.last;
          s.logs.add(RideEngineLog('tail_restore', data: {'n': seg.length, 'm': len.round()}));
        }
      }
    }
    final pts = <List<double>>[];
    for (var i = ri; i < _ring.length; i++) {
      final p = ridePointFromRideFix(_ring[i], pts.isNotEmpty ? pts.last : base);
      if (p != null) pts.add(p);
    }
    final a = _anchor;
    final killGap = _restored && a != null && rideFixPtDistM(r, a) > _C.killGapM;
    var flagged = false;
    if (base != null && !killGap) {
      if (pts.isNotEmpty) {
        flagged = pts.first[2] - base[2] >= _C.flagMinPauseS;
      } else {
        _flagFrom = base[2];
      }
    }
    final since = _pausedSince;
    final from = _reason;
    _toRiding();
    for (var i = 0; i < pts.length; i++) {
      _emit(s, pts[i], flag: i == 0 && flagged);
    }
    s.phaseChanged = true;
    s.logs.add(RideEngineLog('resume', detail: 'auto', data: {
      'mode': 'auto',
      'from': from?.name,
      if (since != null) 'pause_sec': (r.ts - since).round(),
      if (a != null) 'm': rideFixPtDistM(r, a).round(),
      'preroll': pts.length,
      'flagged': flagged,
      if (killGap) 'kill_gap': true,
    }));
  }
}
