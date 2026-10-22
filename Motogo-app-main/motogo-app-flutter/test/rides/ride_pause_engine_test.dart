// Detektor pauz záznamu jízdy (SPEC §6, scénáře D1–D17 + semafor, kolona,
// tankování, tunel, skoky GPS) — syntetické stopy, žádné I/O.
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/features/routes/ride_motion.dart';
import 'package:motogo_app/features/routes/ride_pause_engine.dart';
import 'package:motogo_app/features/routes/ride_session.dart';

import 'support/trace.dart';

RidePauseEngine eng({bool own = true, bool on = true}) =>
    RidePauseEngine(own: own, autoPauseOn: on)..startArmed();

/// Rozjetá jízda: P0 + rozjezd 60 km/h na 2 min (engine je pak `riding`).
Trace riding({bool own = true, bool on = true}) {
  final tr = Trace(eng(own: own, on: on));
  tr.fix(kmh: 0);
  tr.wait(30, every: 0);
  tr.go(60, 120);
  expect(tr.e.phase, RidePhase.riding);
  return tr;
}

void expectIncreasing(List<List<double>> pts) {
  for (var i = 1; i < pts.length; i++) {
    expect(pts[i][2], greaterThanOrEqualTo(pts[i - 1][2]), reason: 'bod $i jde zpět v čase');
  }
}

void main() {
  test('D1 semafor: zpomalení, 90 s bez fixu, rozjezd → žádná pauza, nic se neztratí', () {
    // Stejné fixy s auto-pauzou a bez ní (= referenční stopa) musí dát
    // stejné body: krátké zastavení nic nedrží natrvalo ani nezahodí.
    final tr = riding();
    final k = riding(on: false);
    final n0 = tr.emitted.length, k0 = k.emitted.length;
    void both(void Function(Trace) f) {
      f(tr);
      f(k);
    }
    both((x) => x.go(60, 300));
    for (final v in [40.0, 20.0, 8.0]) {
      both((x) => x.go(v, 5));
    }
    both((x) => x.wait(90));
    for (final v in [15.0, 30.0]) {
      both((x) => x.go(v, 5));
    }
    both((x) => x.go(60, 300));
    expect(tr.logsOf('pause'), isEmpty);
    expect(tr.flagged, isEmpty);
    expectIncreasing(tr.emitted);
    expect(tr.emitted.sublist(n0).map((p) => p[2]).toList(),
        k.emitted.sublist(k0).map((p) => p[2]).toList());
  });

  test('D2a noc: stání s tiky 12 h → pauza „stop" za 5 min, ráno značka na předjezdu', () {
    final tr = riding();
    tr.go(60, 1800);
    for (final v in [40.0, 20.0]) {
      tr.go(v, 5);
    }
    tr.go(8, 10, dt: 10); // poslední pomalý fix ≥ 20 m (kotva)
    final slowSince = tr.t;
    final before = tr.emitted.length;
    tr.wait(12 * 3600);
    final pause = tr.phases.firstWhere((p) => p.phase == RidePhase.autoPaused);
    expect(pause.reason, RidePauseReason.stop);
    expect(pause.t, inInclusiveRange(slowSince + 300, slowSince + 390));
    expect(tr.e.pausedSince, slowSince);
    expect(tr.emitted.length - before, lessThanOrEqualTo(1)); // jen kotva
    final duringPause = tr.emitted.length;
    tr.move(120);
    final pre = tr.t + 5;
    tr.go(25, 5, dt: 5);
    tr.go(25, 5, dt: 5);
    tr.go(60, 60);
    expect(tr.logsOf('pause').length, 1);
    final first = tr.emitted[duringPause];
    expect(first[3], -1);
    expect(first[2], pre);
    expect(tr.e.phase, RidePhase.riding);
  });

  test('D2b náhlé ticho 12 h bez tiků → pauza „silence", kotva = poslední bod jízdy', () {
    final tr = riding();
    tr.go(60, 600);
    final lastRiding = tr.emitted.last;
    tr.wait(12 * 3600, every: 0);
    tr.move(40);
    tr.fix(kmh: 0);
    expect(tr.e.reason, RidePauseReason.silence);
    expect(tr.e.anchor, same(lastRiding));
    final n = tr.emitted.length;
    tr.go(25, 15);
    tr.go(60, 60);
    expect(tr.emitted[n][3], -1);
    expect(tr.logsOf('pause').length, 1);
  });

  test('D3 zastaví, jde 10 min pěšky okruhem k motorce, odjede → pauza „walk", chůze se neposílá', () {
    final tr = riding();
    tr.go(50, 300);
    tr.go(20, 5);
    tr.go(8, 10, dt: 10);
    final slowSince = tr.t;
    tr.wait(60, every: 0);
    final n = tr.emitted.length;
    tr.go(5, 300, dt: 15); // 417 m tam
    tr.go(5, 300, dt: 15, dir: -1); // a zpátky k motorce
    final walk = tr.phases.firstWhere((p) => p.phase == RidePhase.autoPaused);
    expect(walk.reason, RidePauseReason.walk);
    expect(walk.t, inInclusiveRange(slowSince + 180, slowSince + 195));
    expect(tr.emitted.length - n, lessThanOrEqualTo(1)); // nanejvýš kotva
    final m = tr.emitted.length;
    tr.go(50, 120);
    expect(tr.logsOf('tail_restore'), isEmpty);
    expect(tr.emitted[m][3], -1);
  });

  test('D4 plazení 6 km/h 5 min (500 m) → chůze, po rozjezdu se úsek vrátí bez značky', () {
    final tr = riding();
    tr.go(60, 300);
    final start = tr.lat;
    tr.go(6, 300, dt: 12);
    expect(tr.logsOf('pause').single.detail, 'walk');
    tr.go(50, 60);
    expect(tr.logsOf('tail_restore').length, 1);
    expect(tr.flagged, isEmpty);
    expectIncreasing(tr.emitted);
    final crawl = tr.emitted.where((p) => p[0] > start && p[3] <= 7).length;
    expect(crawl, greaterThan(15));
    for (var i = 1; i < tr.emitted.length; i++) {
      expect(ridePtDistM(tr.emitted[i - 1], tr.emitted[i]), lessThan(130));
    }
  });

  test('D5 tunel 90 km/h, 4 min bez fixu (s tiky) → žádná pauza, bod se pošle', () {
    final tr = riding();
    tr.go(90, 120);
    tr.wait(240);
    tr.move(6000);
    tr.fix(kmh: 90);
    expect(tr.logsOf('pause'), isEmpty);
    expect(tr.emitted.last[2], tr.t);
  });

  test('D6 pauza: 8 h driftu (přesnost 40–80 m, bez Doppleru) → zůstává pauza', () {
    final tr = riding(own: false);
    tr.go(8, 10, dt: 10);
    tr.wait(400);
    expect(tr.e.phase, RidePhase.autoPaused);
    final n = tr.emitted.length;
    for (var i = 0; i < 480; i++) {
      tr.t += 60;
      tr.move(i.isEven ? 45 : -38);
      tr.fix(acc: 40 + (i % 5) * 10.0);
    }
    expect(tr.e.phase, RidePhase.autoPaused);
    expect(tr.emitted.length, n);
  });

  test('D7 pauza: chůze 5 km/h s jedním 25 km/h výkyvem → žádná obnova', () {
    final tr = riding();
    tr.go(8, 10, dt: 10);
    tr.wait(400);
    final n = tr.emitted.length;
    tr.go(5, 120, dt: 15);
    tr.go(5, 15, dt: 15, dop: 25);
    tr.go(5, 120, dt: 15);
    expect(tr.e.phase, RidePhase.autoPaused);
    expect(tr.emitted.length, n);
  });

  test('D8 pauza: bez rychlosti, přesnost 15 m, 350 m za 40 s → obnova (pravidlo b)', () {
    final tr = riding();
    tr.go(8, 10, dt: 10);
    tr.wait(400);
    tr.move(300);
    tr.t += 20;
    tr.fix(acc: 15);
    tr.move(350);
    tr.t += 40;
    tr.fix(acc: 15);
    expect(tr.e.phase, RidePhase.riding);
  });

  test('D9 ruční pauza v pomalém úseku → kotva ven, odpojit GPS; po „Pokračovat" značka', () {
    final tr = riding();
    tr.go(10, 45, dt: 9); // 5 pomalých fixů po 25 m
    expect(tr.e.isPending, isTrue);
    final n = tr.emitted.length;
    final anchorTs = tr.t - 36;
    tr.pauseManual();
    expect(tr.detached, isTrue);
    expect(tr.e.phase, RidePhase.manualPaused);
    expect(tr.emitted.length - n, 1);
    expect(tr.emitted.last[2], anchorTs);
    tr.wait(3600, every: 0);
    tr.resumeManual();
    expect(tr.e.isArmed, isTrue);
    final m = tr.emitted.length;
    tr.go(40, 60);
    expect(tr.emitted[m][3], -1);
  });

  test('D10 fix z cache starší než připojení streamu se ignoruje', () {
    final e = RidePauseEngine(own: true)..startArmed();
    e.onAttach(1792000000);
    final s = e.onFix(const RideFix(ts: 1792000000 - 600, lat: 49.2, lng: 16.6, acc: 8, kmh: 0));
    expect(s.emit, isEmpty);
    expect(e.anchor, isNull);
  });

  test('D11 start: P0 hned, chůze 3 min se nenahrává, první bod jízdy má značku', () {
    final tr = Trace(eng());
    tr.fix(kmh: 0);
    expect(tr.emitted.length, 1); // P0
    tr.go(5, 90, dt: 15);
    tr.go(5, 90, dt: 15, dir: -1);
    expect(tr.emitted.length, 1);
    tr.go(40, 60);
    expect(tr.emitted[1][3], -1);
  });

  test('D12 vlastní cesta: okruh 40 km zpět ke startu, stání 3 h → pojistka „doma"', () {
    final tr = Trace(eng());
    tr.fix(kmh: 0);
    tr.go(80, 900);
    tr.go(80, 900, dir: -1);
    tr.go(8, 10, dt: 10);
    tr.wait(3 * 3600 + 400, liveKm: 40);
    expect(tr.detached, isTrue);
    expect(tr.e.phase, RidePhase.manualPaused);
    expect(tr.e.reason, RidePauseReason.home);
    expect(tr.logsOf('home_pause').length, 1);
  });

  test('D13 dlouhá pauza 20 h: vlastní → GPS vypnout, výpůjčka → nic', () {
    for (final own in [true, false]) {
      final tr = riding(own: own);
      tr.go(60, 1800);
      tr.go(8, 10, dt: 10);
      tr.wait(20 * 3600 + 400, liveKm: 30);
      expect(tr.detached, own);
      expect(tr.e.reason, own ? RidePauseReason.long : RidePauseReason.stop);
    }
  });

  test('D14 ukončení v pomalém úseku se 6 drženými body → pošle se jen kotva', () {
    final tr = riding();
    tr.go(10, 54, dt: 9);
    expect(tr.e.isPending, isTrue);
    final n = tr.emitted.length;
    tr.stop();
    expect(tr.emitted.length - n, 1);
    expect(tr.emitted.last[2], tr.t - 45);
  });

  test('D15 flag vypnutý: žádné držení ani pauza, vše se posílá; ruční pauza funguje', () {
    final tr = riding(on: false);
    tr.go(8, 10, dt: 10);
    tr.wait(3600);
    tr.go(5, 300, dt: 15);
    expect(tr.logsOf('pause'), isEmpty);
    expect(tr.e.phase, RidePhase.riding);
    final n = tr.emitted.length;
    tr.pauseManual();
    expect(tr.detached, isTrue);
    tr.wait(600, every: 0);
    tr.resumeManual();
    expect(tr.e.phase, RidePhase.riding);
    tr.go(50, 20);
    expect(tr.emitted[n][3], -1);
  });

  test('D16 obnova po zabití appky, první fixy 50 km od kotvy → pokračuje BEZ značky', () {
    final e = RidePauseEngine(own: true);
    const a = [49.2, 16.6, 1792000000.0, 0.0];
    e.restore(phase: RidePhase.autoPaused, reason: RidePauseReason.stop, since: a[2], anchor: [...a], last: [...a]);
    final tr = Trace(e, t: a[2] + 8 * 3600);
    tr.move(50000);
    tr.go(60, 60);
    expect(e.phase, RidePhase.riding);
    expect(tr.flagged, isEmpty);
    expect(tr.logsOf('resume').single.data['kill_gap'], isTrue);
  });

  test('D17 pomalý rozjezd 10–15 km/h 70 s, pak 25 km/h → předjezd od prvního fixu ≥ 8', () {
    final tr = Trace(eng());
    tr.fix(kmh: 0);
    tr.wait(120, every: 0);
    final pre = tr.t + 5;
    for (var i = 0; i < 14; i++) {
      tr.go(i.isEven ? 10 : 15, 5);
    }
    tr.go(25, 30);
    expect(tr.e.phase, RidePhase.riding);
    // Předjezd od prvního fixu ≥ 8 km/h (bod do 20 m od P0 odfiltruje filtr vzdálenosti).
    expect(tr.emitted[1][2], inInclusiveRange(pre, pre + 5));
    expect(tr.emitted[1][3], -1);
  });

  test('kolona stop-and-go 7 min → žádná pauza, body se pošlou', () {
    final tr = riding();
    tr.go(60, 60);
    tr.go(10, 60);
    tr.wait(90, every: 0);
    tr.go(9, 60);
    tr.wait(120, every: 0);
    tr.go(10, 60);
    tr.wait(60, every: 0);
    tr.go(50, 60);
    expect(tr.logsOf('pause'), isEmpty);
    expect(tr.flagged, isEmpty);
    expectIncreasing(tr.emitted);
  });

  test('tankování 4 min = jen zastávka; 6 min = pauza se značkou', () {
    for (final (min, paused) in [(4, false), (6, true)]) {
      final tr = riding();
      tr.go(8, 10, dt: 10);
      tr.wait(min * 60.0, every: 30);
      tr.go(40, 60);
      expect(tr.logsOf('pause').isNotEmpty, paused, reason: '$min min');
      expect(tr.flagged.isNotEmpty, paused, reason: '$min min');
    }
  });

  test('skok GPS: v pauze jeden přesný fix 500 m daleko (Doppler 0) nic nerozjede', () {
    final tr = riding();
    tr.go(8, 10, dt: 10);
    tr.wait(400);
    final n = tr.emitted.length;
    tr.t += 20;
    tr.move(500);
    tr.fix(kmh: 0, acc: 10);
    tr.t += 20;
    tr.move(-500);
    tr.fix(kmh: 0, acc: 10);
    expect(tr.e.phase, RidePhase.autoPaused);
    expect(tr.emitted.length, n);
  });

  test('skok GPS při stání u semaforu → pauza za 5 min se nezdrží', () {
    final tr = riding();
    tr.go(8, 10, dt: 10);
    tr.wait(120, every: 30);
    tr.move(200);
    tr.fix(kmh: 0, acc: 12);
    tr.move(-200);
    tr.wait(30, every: 0);
    tr.fix(kmh: 0, acc: 12);
    tr.wait(200, every: 30);
    expect(tr.e.phase, RidePhase.autoPaused);
  });

  test('změna flagu za běhu: vypnutí v auto-pauze → jízda, další bod se značkou', () {
    final tr = riding();
    tr.go(8, 10, dt: 10);
    tr.wait(400);
    expect(tr.e.phase, RidePhase.autoPaused);
    final s = tr.e.applyConfig(const RideMotionConfig(), false);
    expect(s.phaseChanged, isTrue);
    final n = tr.emitted.length;
    tr.go(30, 20);
    expect(tr.emitted[n][3], -1);
  });

  test('prahy z flagu: neplatné hodnoty se ignorují', () {
    final c = const RideMotionConfig().withFlag(stopMin: 7, walkMin: -1, resumeKmh: 500, homeH: 2, longH: 0);
    expect(c.stopPauseS, 420);
    expect(c.walkPauseS, 180);
    expect(c.resumeKmh, 20);
    expect(c.homeAfterS, 7200);
    expect(c.longPauseOwnS, 0);
  });
}
