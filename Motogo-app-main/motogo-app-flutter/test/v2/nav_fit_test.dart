// Bottom-nav label fit (DESIGN_V2 §4.1): 8 languages × 320–430 dp — every
// gap between labels ≥ 6 px, both edge gaps ≥ 4 px, short forms only where
// needed. Widths = Montserrat 800 @ 11 px measured for the design (nav.js).
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/v2/chrome/v2_nav_bar.dart';
import 'package:motogo_app/core/v2/chrome/v2_nav_fit.dart';

const _labels = {
  'cs': ['Domů', 'Motorky', 'Rezervace', 'Trasy', 'Profil'],
  'en': ['Home', 'Bikes', 'Bookings', 'Routes', 'Profile'],
  'de': ['Home', 'Bikes', 'Buchungen', 'Routen', 'Profil'],
  'es': ['Inicio', 'Motos', 'Reservas', 'Rutas', 'Perfil'],
  'fr': ['Accueil', 'Motos', 'Locations', 'Itinéraires', 'Profil'],
  'nl': ['Home', 'Motoren', 'Boekingen', 'Routes', 'Profiel'],
  'pl': ['Start', 'Motory', 'Rezerwacje', 'Trasy', 'Profil'],
  'uk': ['Головна', 'Мото', 'Оренда', 'Маршрути', 'Профіль'],
};

// Montserrat 800 @ 11 px (Playwright, research/nav.md).
const _w = {
  'cs': [35.5, 48.8, 60.5, 31.1, 31.6],
  'en': [34.8, 32.2, 55.5, 40.9, 38.7],
  'de': [34.8, 32.2, 68.2, 42.5, 31.6],
  'es': [32.2, 35.9, 52.8, 33.4, 31.5],
  'fr': [43.4, 35.9, 56.9, 59.6, 31.6],
  'nl': [34.8, 49.4, 64.0, 40.9, 38.7],
  'pl': [28.7, 41.6, 67.8, 31.1, 31.6],
  'uk': [48.7, 30.9, 46.5, 64.5, 51.3],
};
const _short = {'Balades': 46.6, 'Wynajmy': 56.2, 'Траси': 35.9};

void main() {
  test('the app strings are the measured labels', () {
    for (final lang in _labels.keys) {
      for (var i = 0; i < 5; i++) {
        expect(translations[lang]![V2NavBar.tabKeys[i]], _labels[lang]![i], reason: '$lang tab $i');
      }
    }
    expect(translations['fr']!['v2TabRoutesShort'], 'Balades');
    expect(translations['pl']!['v2TabBookingsShort'], 'Wynajmy');
    expect(translations['uk']!['v2TabRoutesShort'], 'Траси');
  });

  for (final lang in _labels.keys) {
    for (final width in [320.0, 360.0, 375.0, 390.0, 412.0, 430.0]) {
      for (final scale in [1.0, 1.15]) {
        test('$lang @ $width dp × $scale: no overlap', () {
          final full = _labels[lang]!;
          final short = [
            for (var i = 0; i < 5; i++)
              (translations[lang]![V2NavBar.shortKeys[i] ?? ''] ?? full[i]),
          ];
          double measure(String l, double px) {
            final i = full.indexOf(l);
            final base = i >= 0 ? _w[lang]![i] : _short[l]!;
            return base * px / 11;
          }

          final fit = v2NavFit(full: full, short: short, width: width, measure: measure, scale: scale);
          expect(fit.ok, isTrue, reason: 'gap ${fit.gap} edge ${fit.edge} rung ${fit.rung}');
          expect(fit.gap, greaterThanOrEqualTo(kV2NavGap));
          expect(fit.edge, greaterThanOrEqualTo(kV2NavEdge));
          expect(fit.rung, lessThanOrEqualTo(2), reason: 'rung 3 must never be needed at 320–430 dp');
          // Short forms only for the languages that have one.
          for (var i = 0; i < 5; i++) {
            if (fit.shortened[i]) expect(short[i], isNot(full[i]));
          }
        });
      }
    }
  }

  test('fr at 320 dp needs "Balades", at 390 dp the full word fits', () {
    double m(String l, double px) =>
        (_labels['fr']!.contains(l) ? _w['fr']![_labels['fr']!.indexOf(l)] : _short[l]!) * px / 11;
    final short = [null, null, null, 'Balades', null];
    final narrow = v2NavFit(full: _labels['fr']!, short: short, width: 320, measure: m);
    expect(narrow.labels[3], 'Balades');
    final wide = v2NavFit(full: _labels['fr']!, short: short, width: 390, measure: m);
    expect(wide.labels[3], 'Itinéraires');
    expect(wide.compromised, isFalse);
  });

  test('impossible width falls back to the smallest rung (never throws)', () {
    final fit = v2NavFit(
      full: const ['aaaaaaaaaaaa', 'b', 'c', 'd', 'e'],
      short: const [null, null, null, null, null],
      width: 120,
      measure: (l, px) => l.length * px,
    );
    expect(fit.rung, 3);
    expect(fit.ok, isFalse);
  });
}
