// Živé součty a jejich parita se serverem (`_ride_stats_v2`, SPEC §3.7),
// plurály, hranice etap, formátování.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/features/routes/ride_live_stats.dart';
import 'package:motogo_app/features/routes/ride_motion.dart';

List<List<double>> _pts(List l) =>
    [for (final p in l) [for (final v in p as List) (v as num).toDouble()]];

void main() {
  final fx = jsonDecode(File('test/rides/fixtures/stats_vectors.json').readAsStringSync()) as Map;

  group('parita se serverem (stats_vectors.json)', () {
    for (final v in fx['vectors'] as List) {
      test('${v['id']}', () {
        final pts = _pts(v['points'] as List);
        final e = v['expect'] as Map;
        var km = 0.0, mov = 0.0, gap = 0.0, pause = 0.0;
        for (var i = 1; i < pts.length; i++) {
          final c = rideClassifyPair(pts[i - 1], pts[i]);
          switch (c.kind) {
            case RidePairKind.moving:
              km += c.km;
              mov += c.sec;
            case RidePairKind.zeroDt:
              km += c.km;
            case RidePairKind.gap:
              gap += c.sec;
            case RidePairKind.pause:
            case RidePairKind.inferredPause:
              pause += c.sec;
            default:
          }
        }
        expect(km, closeTo((e['dist_km'] as num).toDouble(), 0.0006));
        expect(mov.round(), e['moving_sec']);
        expect(gap.round(), e['gap_sec']);
        expect(pause.round(), e['pause_sec']);
        final d = rideLiveDelta(null, pts);
        expect(d.km, closeTo(km, 1e-9));
        expect(d.movingSec, mov.round());
      });
    }
  });

  test('živá delta navazuje na poslední odeslaný bod', () {
    final pts = _pts((fx['vectors'] as List).first['points'] as List);
    final all = rideLiveDelta(null, pts);
    final tail = rideLiveDelta(pts[1], pts.sublist(2));
    final head = rideLiveDelta(null, pts.sublist(0, 2));
    expect(head.km + tail.km, closeTo(all.km, 1e-9));
  });

  test('plurály dnů a jízd (cs, pl, uk, fr, en)', () {
    String f(int n, String l) => ridePluralForm(n, l);
    expect([1, 2, 5, 21].map((n) => f(n, 'cs')), ['One', 'Few', 'Many', 'Many']);
    expect([2, 5, 12, 22].map((n) => f(n, 'pl')), ['Few', 'Many', 'Many', 'Few']);
    expect([1, 3, 11, 21].map((n) => f(n, 'uk')), ['One', 'Few', 'Many', 'One']);
    expect([0, 1, 2].map((n) => f(n, 'fr')), ['One', 'One', 'Many']);
    expect([1, 2].map((n) => f(n, 'en')), ['One', 'Many']);
    // Chybějící klíč → klíč sám (UI agent doplní překlady ext_46).
    expect(rideDaysLabel(3, const AppTranslations('cs')), isNotEmpty);
  });

  test('hranice etapy: ≥ 6 h, nebo ≥ 30 min přes noc (00–05)', () {
    double at(int d, int h, [int m = 0]) =>
        DateTime(2026, 10, d, h, m).millisecondsSinceEpoch / 1000;
    expect(rideIsStageBoundary(at(6, 21), at(7, 7)), isTrue); // noc
    expect(rideIsStageBoundary(at(6, 12), at(6, 13)), isFalse); // oběd
    expect(rideIsStageBoundary(at(6, 23, 50), at(7, 0, 30)), isTrue); // 40 min přes půlnoc
    expect(rideIsStageBoundary(at(6, 23, 50), at(7, 0, 10)), isFalse); // jen 20 min
    expect(rideIsStageBoundary(at(6, 8), at(6, 15)), isTrue); // 7 h
  });

  test('formátování živých hodnot', () {
    expect(rideLiveKm(12.34), '12,3');
    expect(rideLiveKm(12.34, 'en'), '12.3');
    expect(rideLiveKm(345.6), '346');
    expect(rideLiveDuration(45 * 60), '45 min');
    expect(rideLiveDuration(80 * 60), '1 h 20 min');
    expect(rideLiveDuration(50 * 3600), '2 d 2 h');
    expect(rideShortDate(DateTime(2026, 10, 6)), '6. 10. 2026');
  });
}
