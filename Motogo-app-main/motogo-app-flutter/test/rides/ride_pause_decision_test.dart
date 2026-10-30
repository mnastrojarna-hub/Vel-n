// Rozhodnutí při otevření appky (2026-10-30, ověření kola 3 — H1 / X19):
// vlastní cesta stojí ≥ 20 h → GPS vypnout a zeptat se „Pokračovat v cestě /
// Ukončit a uložit"; noc v hotelu se neptá, výpůjčka nikdy, pohyb odloží.
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/features/routes/ride_motion.dart';
import 'package:motogo_app/features/routes/ride_pause_engine.dart';
import 'package:motogo_app/features/routes/ride_session.dart';

import 'support/trace.dart';

/// Vlastní cesta / výpůjčka: P0, 30 min jízdy, zastavení → auto-pauza.
Trace parked({bool own = true, bool autoPauseOn = true, RideMotionConfig cfg = const RideMotionConfig()}) {
  final tr = Trace(RidePauseEngine(own: own, autoPauseOn: autoPauseOn, cfg: cfg)..startArmed());
  tr.fix(kmh: 0);
  tr.go(60, 1800);
  tr.go(8, 10, dt: 10);
  tr.wait(400, liveKm: 30);
  return tr;
}

void main() {
  test('I1 noc v hotelu (12 h) se neptá; 20 h stání → GPS vypnout a zeptat se', () {
    final tr = parked();
    expect(tr.e.phase, RidePhase.autoPaused);
    final since = tr.e.pausedSince!;
    tr.wait(12 * 3600, every: 1800, liveKm: 30);
    expect(tr.e.decideIdle(tr.t).isEmpty, isTrue);
    tr.wait(since + 20 * 3600 + 60 - tr.t, every: 1800, liveKm: 30);
    final s = tr.e.decideIdle(tr.t);
    expect(s.detach, isTrue);
    expect(s.idle, isTrue);
    expect(s.phaseChanged, isTrue);
    expect(tr.e.phase, RidePhase.manualPaused);
    expect(tr.e.reason, RidePauseReason.long);
    expect(s.logs.single.action, 'long_pause');
    expect(s.logs.single.detail, 'open');
    // druhé otevření už nic nemění (rozhoduje jezdec)
    expect(tr.e.decideIdle(tr.t + 3600).isEmpty, isTrue);
  });

  test('I2 výpůjčka se při otevření nikdy neptá (končí vrácením)', () {
    final tr = parked(own: false);
    tr.wait(5 * 24 * 3600, every: 3600, liveKm: 30);
    expect(tr.e.decideIdle(tr.t).isEmpty, isTrue);
    expect(tr.detached, isFalse);
    expect(tr.e.phase, RidePhase.autoPaused);
  });

  test('I3 po „Pokračovat v cestě" se počítá od klepnutí, ne od zastavení', () {
    final tr = parked();
    tr.wait(30 * 3600, every: 3600, liveKm: 30);
    expect(tr.e.decideIdle(tr.t).detach, isTrue);
    tr.resumeManual(); // ráno klepne Pokračovat (rest day → vyrazí zítra)
    expect(tr.e.isArmed, isTrue);
    final tap = tr.t;
    tr.wait(19 * 3600, every: 3600, liveKm: 30);
    expect(tr.e.decideIdle(tr.t).isEmpty, isTrue);
    expect(tr.detached, isTrue); // jen z první otázky
    tr.detached = false;
    tr.wait(tap + 20 * 3600 + 60 - tr.t, every: 3600, liveKm: 30);
    expect(tr.e.decideIdle(tr.t).detach, isTrue);
  });

  test('I4 motorka se právě hýbe (pohyb v posledních 2 min) → neptat se, rozhodne obnova jízdy', () {
    final tr = parked();
    tr.wait(25 * 3600, every: 3600, liveKm: 30);
    tr.move(150); // jde k motorce, 150 m od kotvy
    tr.t += 30;
    tr.fix(kmh: 4);
    expect(tr.e.decideIdle(tr.t).isEmpty, isTrue);
    tr.t += 200;
    expect(tr.e.decideIdle(tr.t).detach, isTrue);
  });

  test('I5 kill-switch auto-pauzy / idle_h = 0 → neptat se; „připraveno" bez rozjezdu 25 h → zeptat se', () {
    final off = Trace(RidePauseEngine(own: true, autoPauseOn: false)..startArmed());
    off.fix(kmh: 0);
    off.wait(25 * 3600, every: 3600);
    expect(off.e.decideIdle(off.t).isEmpty, isTrue);
    final zero = parked(cfg: const RideMotionConfig().withFlag(idleH: 0));
    zero.wait(30 * 3600, every: 3600, liveKm: 30);
    expect(zero.e.decideIdle(zero.t).isEmpty, isTrue);
    final armed = Trace(RidePauseEngine(own: true)..startArmed());
    armed.fix(kmh: 0); // P0, nikam nejel
    armed.wait(25 * 3600, every: 3600);
    expect(armed.e.isArmed, isTrue);
    expect(armed.e.decideIdle(armed.t).detach, isTrue);
  });
}
