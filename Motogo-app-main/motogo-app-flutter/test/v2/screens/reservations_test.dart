// Reservations v2 screen matrix (PLAN §5.3): list (each filter, empty,
// filter-empty, stale, loading, error, unpaid), detail (every status incl.
// codes ready / unpaid / verifying / docs withheld / active / done + rating
// 0·2·5 / cancelled / delivery / stale / codes error) and edit (chooser +
// every focused intent + price + missing sizes + confirm + load states)
// × 8 languages × 2 phone sizes — no overflow / exception. Reduced-motion
// passes must settle. Review shots go to MG_SHOTS_DIR.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/reservations/reservation_models.dart';
import 'package:motogo_app/features/reservations/v2/res_cancel_v2.dart';
import 'package:motogo_app/features/reservations/v2/reservations_screen_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_home.dart' show mockPathProvider;
import '../support/fakes_reservations.dart';
import '../support/v2_harness.dart';
import 'reservations_cases.dart';

Future<void> _settleClean(WidgetTester tester) async {
  await expectCleanFrames(tester);
  await tester.pump(const Duration(seconds: 1));
  expect(tester.takeException(), isNull);
}

typedef _Case = (Widget Function(), List<Override> Function());

void _matrix(String screen, Map<String, _Case> cases) {
  for (final entry in cases.entries) {
    for (final lang in kV2Langs) {
      for (final size in kV2Sizes) {
        final w = size.width.toInt(), h = size.height.toInt();
        testWidgets('$screen ${entry.key} $lang ${w}x$h', (tester) async {
          final key = GlobalKey();
          await pumpV2(tester, entry.value.$1(), lang: lang, size: size, overrides: entry.value.$2(), boundaryKey: key);
          await _settleClean(tester);
          await maybeShot(tester, key, 'reservations__${screen}__${entry.key}__${lang}__${w}x$h');
        });
      }
    }
  }
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerReservationStrings();
    mockPathProvider();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MgMotion.resetSession();
  });

  _matrix('list', {
    for (final e in listCases().entries) e.key: (() => const ReservationsScreenV2(), e.value),
  });
  _matrix('detail', detailCases());
  _matrix('edit', editCases());
  _matrix('dialog', {
    'cancel-confirm': (
      () => ResCancelConfirmV2(
            motoName: 'Husqvarna 701 SM',
            dateRange: '16. 10. – 18. 10. 2026',
            pct: 50,
            refundLine: 'Aktuálně: 50% vrácení (6014 Kč)',
            loading: false,
            onReason: (_) {},
            onKeep: () {},
            onCancel: () {},
          ),
      () => resOverrides(),
    ),
    'cancel-busy': (
      () => ResCancelConfirmV2(
            motoName: 'BMW R 1200 GS Adventure',
            dateRange: '23. 10. – 25. 10. 2026',
            pct: 100,
            refundLine: 'Aktuálně: 100% vrácení (12027 Kč)',
            loading: true,
            onReason: (_) {},
            onKeep: () {},
            onCancel: () {},
          ),
      () => resOverrides(),
    ),
    'cancel-done': (
      () => ResCancelResultV2(ok: true, title: 'Rezervace je zrušená', body: 'Vrátíme ti 6 014 Kč (50 %).', closeLabel: 'Zavřít', onClose: () {}),
      () => resOverrides(),
    ),
    'cancel-fail': (
      () => ResCancelResultV2(
          ok: false, title: 'Rezervaci se nepodařilo zrušit', body: 'Spojení selhalo.', closeLabel: 'Zpět', onClose: () {}, onRetry: () {}),
      () => resOverrides(),
    ),
  });

  // Whole pages in one tall frame (review shots; lays out every section).
  final full = {
    'list': (() => const ReservationsScreenV2(), () => resOverrides(list: sampleList())),
    ...{for (final k in ['ready', 'active', 'done-5', 'cancelled', 'unpaid', 'docs']) 'detail-$k': detailCases()[k]!},
    ...{for (final k in ['chooser-changed', 'extend', 'gear']) 'edit-$k': editCases()[k]!},
  };
  for (final e in full.entries) {
    for (final lang in ['cs', 'en', 'de']) {
      testWidgets('full ${e.key} $lang', (tester) async {
        final key = GlobalKey();
        await pumpV2(tester, e.value.$1(), lang: lang, size: const Size(390, 2600), overrides: e.value.$2(), boundaryKey: key);
        await _settleClean(tester);
        await maybeShot(tester, key, 'reservations__full__${e.key}__${lang}__390x2600');
      });
    }
  }

  // Expanders: payment details + history open without overflow.
  for (final lang in ['cs', 'de', 'uk']) {
    testWidgets('detail expanders open $lang', (tester) async {
      final c = detailCases()['done-5']!;
      final key = GlobalKey();
      await pumpV2(tester, c.$1(), lang: lang, size: const Size(360, 2800), overrides: c.$2(), boundaryKey: key);
      await _settleClean(tester);
      for (final label in [kPayDetailsLabel(lang), kHistoryLabel(lang)]) {
        final f = find.text(label);
        expect(f, findsOneWidget);
        await tester.ensureVisible(f);
        await tester.tap(f);
        await tester.pump(const Duration(milliseconds: 600));
      }
      await _settleClean(tester);
      await maybeShot(tester, key, 'reservations__detail__expanders__${lang}__360x2800');
    });
  }

  // Edit: picking an intent from the chooser opens its focus; back returns.
  testWidgets('edit chooser → focus → back', (tester) async {
    final c = editCases()['chooser']!;
    await pumpV2(tester, c.$1(), size: const Size(390, 1400), overrides: c.$2());
    await _settleClean(tester);
    await tester.tap(find.text('Výbava a doplňky'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Výbava a doplňky'), findsOneWidget); // header title now
    await tester.tap(find.bySemanticsLabel('Zpět'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Co chceš změnit?'), findsOneWidget);
    await _settleClean(tester);
  });

  // Reduced motion: everything settles (no endless loops), still no overflow.
  final reduced = {
    'list': (() => const ReservationsScreenV2(), () => resOverrides(list: sampleList())),
    'detail-active': detailCases()['active']!,
    'detail-ready': detailCases()['ready']!,
    'edit-extend': editCases()['extend']!,
  };
  for (final e in reduced.entries) {
    testWidgets('reduced motion ${e.key}', (tester) async {
      await pumpV2(tester, e.value.$1(), overrides: e.value.$2(), reducedMotion: true);
      await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    });
  }

  test('pay flag follows the shell pending booking', () {
    final r = resv('p1', status: 'pending', pay: 'unpaid', from: 3, to: 5, created: DateTime.now());
    expect(r.displayStatus, isNot(ResStatus.cancelled));
    final p = PendingBooking(id: r.id, totalPrice: 12027, createdAt: DateTime.now());
    expect(p.isExpired, isFalse);
  });
}
