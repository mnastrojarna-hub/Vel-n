// Rozhodnutí při otevření appky (2026-10-30, ověření kola 3 — H1 / X19 / S4):
// vlastní cesta stojí ≥ 20 h → ~1 min poslechu GPS, pak GPS vypnout a zeptat
// se „Pokračovat v cestě / Ukončit a uložit"; jede-li motorka právě při
// otevření, rozhodne rozjezd. Noc v hotelu se neptá, výpůjčka nikdy.
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

/// Otevření appky + 61 s ticha (tik časovače) → zeptala se?
bool openAndWait(Trace tr) {
  final s = tr.e.decideIdle(tr.t);
  if (s.detach) return true;
  if (!s.probe) return false;
  tr.t += 61;
  tr.tick(liveKm: 30);
  return tr.detached;
}

void main() {
  test('I1 noc v hotelu (12 h) se neptá; 20 h stání → po minutě GPS vypnout a zeptat se', () {
    final tr = parked();
    expect(tr.e.phase, RidePhase.autoPaused);
    final since = tr.e.pausedSince!;
    tr.wait(12 * 3600, every: 1800, liveKm: 30);
    expect(tr.e.decideIdle(tr.t).isEmpty, isTrue);
    tr.wait(since + 20 * 3600 + 60 - tr.t, every: 1800, liveKm: 30);
    final first = tr.e.decideIdle(tr.t);
    expect(first.probe, isTrue, reason: 'nejdřív minuta poslechu GPS');
    expect(first.detach, isFalse);
    expect(first.logs.single.action, 'idle_check');
    tr.t += 30;
    tr.tick(liveKm: 30);
    expect(tr.detached, isFalse);
    tr.t += 31;
    final before = tr.logs.length;
    tr.tick(liveKm: 30);
    expect(tr.detached, isTrue);
    expect(tr.e.phase, RidePhase.manualPaused);
    expect(tr.e.reason, RidePauseReason.long);
    final ask = tr.logs.sublist(before).single;
    expect(ask.action, 'long_pause');
    expect(ask.detail, 'open');
    // další otevření už nic nemění (rozhoduje jezdec)
    expect(tr.e.decideIdle(tr.t + 3600).isEmpty, isTrue);
  });

  test('I2 výpůjčka se při otevření nikdy neptá (končí vrácením)', () {
    final tr = parked(own: false);
    tr.wait(5 * 24 * 3600, every: 3600, liveKm: 30);
    expect(openAndWait(tr), isFalse);
    expect(tr.e.phase, RidePhase.autoPaused);
  });

  test('I3 po „Pokračovat v cestě" se počítá od klepnutí, ne od zastavení', () {
    final tr = parked();
    tr.wait(30 * 3600, every: 3600, liveKm: 30);
    expect(openAndWait(tr), isTrue);
    tr.detached = false;
    tr.resumeManual(); // klepne Pokračovat (den volna → vyrazí zítra)
    expect(tr.e.isArmed, isTrue);
    final tap = tr.t;
    tr.wait(19 * 3600, every: 3600, liveKm: 30);
    expect(openAndWait(tr), isFalse);
    expect(tr.detached, isFalse, reason: 'pojistka po Pokračovat GPS nevypnula');
    tr.wait(tap + 20 * 3600 + 60 - tr.t, every: 3600, liveKm: 30);
    expect(openAndWait(tr), isTrue);
  });

  test('I4 S4: appka otevřená po 21 h právě při rozjezdu → žádná otázka, jízda se nahrává', () {
    final tr = parked();
    tr.wait(21 * 3600, every: 3600, liveKm: 30);
    final s = tr.e.decideIdle(tr.t);
    expect(s.probe, isTrue);
    final n = tr.emitted.length;
    tr.go(70, 60); // během minuty poslechu se rozjede
    tr.tick(liveKm: 30);
    expect(tr.detached, isFalse);
    expect(tr.e.phase, RidePhase.riding);
    expect(tr.emitted.length - n, greaterThan(5));
    tr.go(70, 600);
    tr.tick(liveKm: 40);
    expect(tr.detached, isFalse);
  });

  test('I5 chůze k motorce při otevření odloží otázku; pak stání → zeptat se', () {
    final tr = parked();
    tr.wait(25 * 3600, every: 3600, liveKm: 30);
    expect(tr.e.decideIdle(tr.t).probe, isTrue);
    tr.move(150); // jde k motorce, 150 m od kotvy
    tr.t += 61;
    tr.fix(kmh: 4);
    tr.tick(liveKm: 30);
    expect(tr.detached, isFalse, reason: 'pohyb → ještě počkat');
    tr.t += 200;
    tr.tick(liveKm: 30);
    expect(tr.detached, isTrue);
  });

  test('I6 kill-switch auto-pauzy / idle_h = 0 → neptat se; „připraveno" bez rozjezdu 25 h → zeptat se', () {
    final off = Trace(RidePauseEngine(own: true, autoPauseOn: false)..startArmed());
    off.fix(kmh: 0);
    off.wait(25 * 3600, every: 3600);
    expect(off.e.decideIdle(off.t).isEmpty, isTrue);
    final zero = parked(cfg: const RideMotionConfig().withFlag(idleH: 0));
    zero.wait(30 * 3600, every: 3600, liveKm: 30);
    expect(openAndWait(zero), isFalse);
    final armed = Trace(RidePauseEngine(own: true)..startArmed());
    armed.fix(kmh: 0); // P0, nikam nejel
    armed.wait(25 * 3600, every: 3600);
    expect(armed.e.isArmed, isTrue);
    expect(openAndWait(armed), isTrue);
  });
}
