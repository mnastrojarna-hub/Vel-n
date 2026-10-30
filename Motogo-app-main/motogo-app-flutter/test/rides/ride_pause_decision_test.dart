// Rozhodnutí při otevření appky (kolo 3 H1 / X19 / S4, kolo 4 V7):
// vlastní cesta stojí ≥ 20 h → ~1 min poslechu GPS, pak jen PŘIPOMENOUT
// (GPS běží dál, ranní rozjezd vícedenní cesty se nahraje sám — majitel:
// „abych to nemusel pauzovat"); ≥ 48 h → GPS vypnout a zeptat se
// „Pokračovat v cestě / Ukončit a uložit". Jede-li motorka právě při
// otevření, rozhodne rozjezd. Noc v hotelu se nepřipomíná, výpůjčka nikdy.
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

/// Otevření appky + 61 s ticha (tik časovače) → 'none' / 'remind' / 'ask'.
String openAndWait(Trace tr) {
  final r0 = tr.reminds;
  final s = tr.e.decideIdle(tr.t);
  if (s.detach) return 'ask';
  if (!s.probe) return 'none';
  tr.t += 61;
  tr.tick(liveKm: 30);
  if (tr.detached) return 'ask';
  return tr.reminds > r0 ? 'remind' : 'none';
}

void main() {
  test('I1 noc (12 h) nic; 20 h → po minutě jen připomenout (GPS běží); 48 h → GPS vypnout a zeptat se', () {
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
    expect(tr.reminds, 0);
    tr.t += 31;
    tr.tick(liveKm: 30);
    expect(tr.reminds, 1);
    expect(tr.detached, isFalse, reason: 'GPS běží dál — rozjezd se nahraje sám');
    expect(tr.e.phase, RidePhase.autoPaused);
    expect(tr.logsOf('idle_remind'), hasLength(1));
    // další otevření v téže pauze už nepřipomíná (ani neposlouchá navíc)
    expect(tr.e.decideIdle(tr.t + 3600).isEmpty, isTrue);
    // bez otevření: pojistka po 48 h od zastavení vypne GPS (zapomenutý Stop)
    tr.wait(since + 48 * 3600 + 100 - tr.t, every: 1800, liveKm: 30);
    tr.tick(liveKm: 30);
    expect(tr.detached, isTrue);
    expect(tr.e.phase, RidePhase.manualPaused);
    expect(tr.e.reason, RidePauseReason.long);
    expect(tr.logsOf('long_pause'), hasLength(1));
  });

  test('I1b otevření po ≥ 48 h → po minutě GPS vypnout a zeptat se (by: open)', () {
    final tr = parked();
    tr.wait(50 * 3600, every: 0);
    expect(openAndWait(tr), 'ask');
    expect(tr.e.reason, RidePauseReason.long);
    expect(tr.logsOf('long_pause').single.detail, 'open');
    expect(tr.e.decideIdle(tr.t + 3600).isEmpty, isTrue, reason: 'rozhoduje jezdec');
  });

  test('I2 výpůjčka se při otevření nikdy neptá ani nepřipomíná (končí vrácením)', () {
    final tr = parked(own: false);
    tr.wait(5 * 24 * 3600, every: 3600, liveKm: 30);
    expect(openAndWait(tr), 'none');
    expect(tr.e.phase, RidePhase.autoPaused);
    expect(tr.detached, isFalse);
  });

  test('I3 po „Pokračovat v cestě" se počítá od klepnutí, ne od zastavení', () {
    final tr = parked();
    tr.wait(50 * 3600, every: 0);
    expect(openAndWait(tr), 'ask');
    tr.detached = false;
    tr.resumeManual(); // klepne Pokračovat (den volna → vyrazí zítra)
    expect(tr.e.isArmed, isTrue);
    final tap = tr.t;
    tr.wait(19 * 3600, every: 3600, liveKm: 30);
    expect(openAndWait(tr), 'none');
    expect(tr.detached, isFalse, reason: 'pojistka po Pokračovat GPS nevypnula');
    tr.wait(tap + 20 * 3600 + 60 - tr.t, every: 3600, liveKm: 30);
    expect(openAndWait(tr), 'remind');
    tr.wait(tap + 48 * 3600 - 300 - tr.t, every: 1800, liveKm: 30);
    tr.tick(liveKm: 30);
    expect(tr.detached, isFalse, reason: 'ještě ne 48 h od Pokračovat');
    tr.t = tap + 48 * 3600 + 100;
    tr.tick(liveKm: 30);
    expect(tr.detached, isTrue, reason: '48 h od Pokračovat');
  });

  test('I4 S4: appka otevřená po 21 h právě při rozjezdu → nic, jízda se nahrává', () {
    final tr = parked();
    tr.wait(21 * 3600, every: 3600, liveKm: 30);
    final s = tr.e.decideIdle(tr.t);
    expect(s.probe, isTrue);
    final n = tr.emitted.length;
    tr.go(70, 60); // během minuty poslechu se rozjede
    tr.tick(liveKm: 30);
    expect(tr.detached, isFalse);
    expect(tr.reminds, 0);
    expect(tr.e.phase, RidePhase.riding);
    expect(tr.emitted.length - n, greaterThan(5));
    tr.go(70, 600);
    tr.tick(liveKm: 40);
    expect(tr.detached, isFalse);
  });

  test('I5 chůze k motorce při otevření odloží připomínku; pak stání → připomenout', () {
    final tr = parked();
    tr.wait(25 * 3600, every: 3600, liveKm: 30);
    expect(tr.e.decideIdle(tr.t).probe, isTrue);
    tr.move(150); // jde k motorce, 150 m od kotvy
    tr.t += 61;
    tr.fix(kmh: 4);
    tr.tick(liveKm: 30);
    expect(tr.reminds, 0, reason: 'pohyb → ještě počkat');
    tr.t += 200;
    tr.tick(liveKm: 30);
    expect(tr.reminds, 1);
    expect(tr.detached, isFalse);
  });

  test('I6 kill-switch auto-pauzy / idle_h = 0 → nic; „připraveno" bez rozjezdu 25 h → připomenout', () {
    final off = Trace(RidePauseEngine(own: true, autoPauseOn: false)..startArmed());
    off.fix(kmh: 0);
    off.wait(25 * 3600, every: 3600);
    expect(off.e.decideIdle(off.t).isEmpty, isTrue);
    final zero = parked(cfg: const RideMotionConfig().withFlag(idleH: 0));
    zero.wait(30 * 3600, every: 3600, liveKm: 30);
    expect(openAndWait(zero), 'none');
    final armed = Trace(RidePauseEngine(own: true)..startArmed());
    armed.fix(kmh: 0); // P0, nikam nejel
    armed.wait(25 * 3600, every: 3600);
    expect(armed.e.isArmed, isTrue);
    expect(openAndWait(armed), 'remind');
    expect(armed.e.isArmed, isTrue, reason: 'pořád čeká na rozjezd');
  });

  test('I7 nová pauza (po další jízdě) připomíná znovu', () {
    final tr = parked();
    tr.wait(21 * 3600, every: 3600, liveKm: 30);
    expect(openAndWait(tr), 'remind');
    tr.go(70, 1800); // jede dál (den 2)
    tr.go(8, 10, dt: 10);
    tr.wait(400, liveKm: 60);
    expect(tr.e.phase, RidePhase.autoPaused);
    tr.wait(21 * 3600, every: 3600, liveKm: 60);
    expect(openAndWait(tr), 'remind');
    expect(tr.reminds, 2);
  });
}
