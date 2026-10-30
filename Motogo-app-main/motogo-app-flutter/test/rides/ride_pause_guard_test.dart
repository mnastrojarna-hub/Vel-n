// Opravy detektoru pauz z ověření 2026-10-29 (fix:logic:r1): pojistka
// „dlouhá pauza" po Pokračovat / otevření appky, přeskoky polohy z Wi-Fi
// v noci, chůze bez Doppleru po brzdění, posun hodin telefonu.
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/features/routes/ride_live_stats.dart';
import 'package:motogo_app/features/routes/ride_motion.dart';
import 'package:motogo_app/features/routes/ride_pause_engine.dart';
import 'package:motogo_app/features/routes/ride_session.dart';

import 'support/trace.dart';

RidePauseEngine eng({bool own = true}) => RidePauseEngine(own: own)..startArmed();

/// Vlastní cesta: P0, 30 min jízdy, zastavení → auto-pauza (stop).
Trace parked({bool own = true}) {
  final tr = Trace(eng(own: own));
  tr.fix(kmh: 0);
  tr.go(60, 1800);
  tr.go(8, 10, dt: 10);
  tr.wait(400, liveKm: 30);
  expect(tr.e.phase, RidePhase.autoPaused);
  return tr;
}

void main() {
  test('G1 pojistka → Pokračovat → 10 min u kafe → GPS zůstane, rozjezd se nahraje se značkou', () {
    final tr = parked();
    tr.wait(49 * 3600, liveKm: 30);
    expect(tr.detached, isTrue);
    expect(tr.e.reason, RidePauseReason.long);
    tr.detached = false;
    tr.resumeManual(); // ráno klepne „Pokračovat v cestě"
    expect(tr.e.isArmed, isTrue);
    tr.wait(600, liveKm: 30); // tiky 90 s, ještě nejede
    expect(tr.detached, isFalse, reason: 'pojistka hned znovu vypnula GPS');
    expect(tr.logsOf('long_pause').length, 1);
    final n = tr.emitted.length;
    tr.go(60, 120);
    expect(tr.e.phase, RidePhase.riding);
    expect(tr.emitted.length - n, greaterThan(15));
    expect(tr.emitted[n][3], -1); // první bod po pauze = značka
    // další den stání bez kontaktu se počítá od klepnutí, ne od včerejška
    tr.go(8, 10, dt: 10);
    tr.wait(20 * 3600, liveKm: 60);
    expect(tr.detached, isFalse);
  });

  test('G2 připojení streamu (obnova) dlouho po zastavení: 2 min nic, dlouhá pauza dál od zastavení', () {
    const a = [49.2, 16.6, 1792000000.0, 0.0];
    RidePauseEngine restored() => RidePauseEngine(own: true)
      ..restore(phase: RidePhase.autoPaused, reason: RidePauseReason.stop, since: a[2], anchor: [...a], last: [...a], start: [...a]);
    // otevřel appku po 30 h → zeptat se (zapomenutý Stop?)
    final e = restored();
    final ask = e.decideIdle(a[2] + 30 * 3600);
    expect(ask.detach, isTrue);
    expect(ask.idle, isTrue);
    expect(e.phase, RidePhase.manualPaused);
    expect(e.reason, RidePauseReason.long);
    // po 10 h (noc) se neptá; připojení streamu pojistku NEPRODLUŽUJE
    final f = restored();
    final t1 = a[2] + 10 * 3600;
    expect(f.decideIdle(t1).isEmpty, isTrue);
    f.onAttach(t1);
    expect(f.onTick(t1 + 30, liveKm: 50).detach, isFalse); // 2 min ticha
    expect(f.onTick(a[2] + 47 * 3600, liveKm: 50).detach, isFalse);
    expect(f.onTick(a[2] + 48 * 3600 + 60, liveKm: 50).detach, isTrue); // 48 h od zastavení
  });

  test('G3 otevření appky pojistku neprodlouží (zapomenutý Stop); pohyb v posledních 2 min ji odloží', () {
    final tr = parked();
    tr.wait(40 * 3600, liveKm: 30);
    tr.e.noteForeground(tr.t); // jezdec se podíval do appky
    tr.wait(20 * 3600, liveKm: 30);
    expect(tr.detached, isTrue, reason: 'GPS má jít vypnout 48 h po zastavení, ne 48 h po otevření');
    expect(tr.logsOf('long_pause').length, 1);
    expect(tr.e.reason, RidePauseReason.long);
    final m = parked();
    final since = m.e.pausedSince!;
    m.wait(since + 48 * 3600 - 30 - m.t, liveKm: 30);
    expect(m.detached, isFalse);
    m.move(150); // chůze k motorce, 150 m od kotvy
    m.t += 60;
    m.fix(kmh: 4);
    m.tick(liveKm: 30); // pojistka by už platila, ale jezdec se hýbe
    expect(m.detached, isFalse, reason: 'pohyb → rozhodne obnova jízdy');
    m.t += 180;
    m.tick(liveKm: 30); // 3 min bez pohybu → pojistka
    expect(m.detached, isTrue);
  });

  test('W1 noc v hotelu: přeskoky Wi-Fi o 400 m (přesnost 12/20/30 m) → žádná obnova, žádné body', () {
    for (final acc in [12.0, 20.0, 30.0]) {
      for (final own in [true, false]) {
        final tr = parked(own: own);
        final n = tr.emitted.length;
        final r0 = tr.logsOf('resume').length; // rozjezd z „připraveno"
        final base = tr.lat;
        for (var m = 0; m < 600; m++) {
          tr.t += 40;
          if (m % 20 == 0) {
            tr.lat = base + 400 / kMPerDegLat;
            tr.fix(acc: acc);
            tr.t += 30;
            tr.lat = base + 420 / kMPerDegLat;
            tr.fix(acc: acc);
            tr.t += 30;
            tr.lat = base;
            tr.fix(acc: acc);
          } else {
            tr.lat = base + ((m % 3) - 1) * 15 / kMPerDegLat;
            tr.fix(acc: acc);
          }
          tr.tick(liveKm: 30);
        }
        expect(tr.logsOf('resume').length, r0, reason: 'acc $acc own $own');
        expect(tr.emitted.length, n);
      }
    }
  });

  test('W2 telefon bez Doppleru: přeskok Wi-Fi tam a zpět nic, skutečný rozjezd ano', () {
    final tr = Trace(eng());
    tr.fix(acc: 8);
    tr.go(60, 600, noDop: true);
    tr.wait(400);
    expect(tr.e.phase, RidePhase.autoPaused);
    final base = tr.lat;
    for (var i = 0; i < 10; i++) {
      tr.t += 600;
      tr.lat = base + 400 / kMPerDegLat;
      tr.fix(acc: 15);
      tr.t += 30;
      tr.lat = base + 420 / kMPerDegLat;
      tr.fix(acc: 15);
      tr.t += 30;
      tr.lat = base;
      tr.fix(acc: 15);
    }
    expect(tr.e.phase, RidePhase.autoPaused);
    tr.go(60, 40, dt: 10, noDop: true, acc: 10);
    expect(tr.e.phase, RidePhase.riding);
  });

  test('K1 brzdění s 1 Dopplerem, pak 40 min chůze bez rychlosti → pauza chůze, nic se nenahraje ani nevrátí', () {
    final tr = Trace(eng());
    tr.fix(kmh: 0);
    tr.go(45, 1500);
    tr.move(12);
    tr.t += 5;
    tr.fix(kmh: 8.6); // brzdění — jediný vzorek Doppleru
    final bike = tr.lat;
    tr.t += 75;
    final n = tr.emitted.length;
    for (final dir in [1.0, -1.0]) {
      for (var i = 0; i < 80; i++) {
        tr.t += 15;
        tr.lng += dir * 20 / (kMPerDegLat * 0.653);
        tr.fix(acc: 7);
        tr.tick();
      }
    }
    expect(tr.logsOf('pause').single.detail, 'walk');
    // nanejvýš kotva (místo, kde motorka zastavila), žádný bod chůze
    expect(tr.emitted.length - n, lessThanOrEqualTo(1));
    if (tr.emitted.length > n) expect(tr.emitted.last[0], closeTo(bike, 1e-4));
    final m = tr.emitted.length;
    tr.t += 60;
    tr.go(45, 100);
    expect(tr.e.phase, RidePhase.riding);
    expect(tr.logsOf('tail_restore'), isEmpty);
    final walkKm = rideLiveDelta(tr.emitted[m - 1], tr.emitted.sublist(m, m + 1)).km;
    expect(walkKm, 0); // první bod po pauze = značka, žádné km chůze
    expect(tr.emitted[m][3], -1);
  });

  test('C1 posun hodin: čas připojení se přepočítá → fixy v čase serveru se nezahodí jako z cache', () {
    final e = RidePauseEngine(own: true)..startArmed();
    const phone = 1792000000.0;
    const off = -7 * 3600.0; // telefon jde o 7 h napřed
    e.onAttach(phone); // stream se připojil dřív, než server řekl posun
    final f = RideFix(ts: phone + off + 5, lat: 49.2, lng: 16.6, acc: 8, kmh: 0);
    expect(e.onFix(f).emit, isEmpty); // bez přepočtu = „z cache"
    e.rebaseAttach(phone + off);
    final s = e.onFix(RideFix(ts: phone + off + 10, lat: 49.2, lng: 16.6, acc: 8, kmh: 0));
    expect(s.emit.length, 1); // P0
    // telefon o 40 s napřed, fix s časem GPS (pásmo bez opravy) → bere se
    final g = RidePauseEngine(own: true)..startArmed();
    g.onAttach(phone);
    expect(g.onFix(RideFix(ts: phone - 40, lat: 49.2, lng: 16.6, acc: 8, kmh: 0)).emit.length, 1);
    // skutečný fix z cache (10 min starý) se dál zahazuje
    final h = RidePauseEngine(own: true)..startArmed();
    h.onAttach(phone);
    expect(h.onFix(RideFix(ts: phone - 600, lat: 49.2, lng: 16.6, acc: 8, kmh: 0)).emit, isEmpty);
  });

  test('config: výchozí dlouhá pauza 48 h, otázka při otevření 20 h, flag je smí změnit', () {
    expect(const RideMotionConfig().longPauseOwnS, 48 * 3600);
    expect(const RideMotionConfig().withFlag(longH: 20).longPauseOwnS, 20 * 3600);
    expect(const RideMotionConfig().idleDecisionS, 20 * 3600);
    expect(const RideMotionConfig().withFlag(idleH: 30).idleDecisionS, 30 * 3600);
    expect(const RideMotionConfig().withFlag(idleH: 0).idleDecisionS, 0);
    expect(const RideMotionConfig().withFlag(idleH: 999).idleDecisionS, 20 * 3600); // neplatné → výchozí
  });
}
