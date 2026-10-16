// Home v2 screen matrix (PLAN §5.3): every Home state × 8 languages × 2
// phone sizes must lay out without overflow / exception; one reduced-motion
// pass must settle; rank variants on the funnel; full-page review shots
// (MG_SHOTS_DIR) for cs / en / de.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/pending_sos_fab_provider.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';
import 'package:motogo_app/features/routes/ride_recorder.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_home.dart';
import '../support/v2_harness.dart';

Map<String, List<Override> Function()> homeCases() {
  final r6 = res('b6', status: 'reserved', from: 5, to: 7);
  final r6b = res('b7', status: 'reserved', from: 12, to: 14, self: false, bike: 'BMW R 1200 GS Adventure');
  final r4 = res('b4', status: 'reserved', from: 3, to: 5, self: false, bike: 'BMW R 1200 GS Adventure');
  final r5 = res('b5', status: 'reserved', from: 2, to: 4, self: false, delivery: true);
  final r7 = res('b7', status: 'reserved', from: 0, to: 2);
  final r8 = res('b8', status: 'active', from: -1, to: 1);
  final r9 = res('b9', status: 'active', from: -2, to: 0, self: false);
  final r10 = res('b10', status: 'completed', from: -5, to: -3);
  final r2 = res('b2', status: 'pending', pay: 'unpaid', from: 9, to: 11, created: DateTime.now().subtract(const Duration(minutes: 5)));
  final pending = PendingBooking(id: r2.id, totalPrice: 12027, createdAt: r2.createdAt);
  final sos = PendingSosReplacement(id: 'sos1', type: 'breakdown_major', status: 'open', replacementStatus: 'selecting', bookingId: r8.id);
  final two = kMotos.take(2).toList();
  return {
    's0': () => homeOverrides(funnel: two),
    's0-loading': () => homeOverrides(funnelLoading: true),
    's0-error': () => homeOverrides(funnelError: true),
    's0-nonefree': () => homeOverrides(funnel: const []),
    's0-noloyalty': () => homeOverrides(funnel: two, loyaltyFails: true, unread: 0, banner: false),
    's1': () => homeOverrides(reservations: [r8], sos: sos),
    's2': () => homeOverrides(reservations: [r2], pending: pending),
    's2-verifying': () => homeOverrides(
        reservations: [r2],
        pending: PendingBooking(id: r2.id, totalPrice: 12027, createdAt: r2.createdAt, verifying: true)),
    's3': () => homeOverrides(reservations: [r6], docsOk: false),
    's4': () => homeOverrides(reservations: [r4]),
    's5': () => homeOverrides(reservations: [r5]),
    's6': () => homeOverrides(reservations: [r6, r6b]),
    's7': () => homeOverrides(reservations: [r7]),
    's8-rec': () => homeOverrides(
        reservations: [r8], recorder: const RideRecorderState(recording: true, bookingId: 'b8', points: 120)),
    's9': () => homeOverrides(reservations: [r9]),
    's10': () => homeOverrides(reservations: [r10], funnel: two),
    's10-rated': () => homeOverrides(
        reservations: [res('b11', status: 'completed', from: -4, to: -2, rating: 4, ratedAt: DateTime.now())], funnel: two),
    'manual-rec': () => homeOverrides(
        funnel: two, recorder: const RideRecorderState(recording: true, manual: true, points: 40)),
    'res-loading': () => homeOverrides(resLoading: true),
  };
}

/// The harness frames + one more second, so one-shot reveals started by a
/// late rebuild finish before teardown; fails on any exception.
Future<void> _settleClean(WidgetTester tester) async {
  await expectCleanFrames(tester);
  await tester.pump(const Duration(seconds: 1));
  expect(tester.takeException(), isNull);
}

Future<void> _pump(WidgetTester tester, String state, List<Override> o,
    {String lang = 'cs', Size size = const Size(360, 780), RankTokens? rank, bool reduced = false, GlobalKey? key}) async {
  await pumpV2(tester, const HomeScreenV2(),
      lang: lang, size: size, overrides: o, rank: rank, reducedMotion: reduced, boundaryKey: key);
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerHomeStrings();
    mockPathProvider();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MgMotion.resetSession();
  });

  final cases = homeCases();
  for (final entry in cases.entries) {
    for (final lang in kV2Langs) {
      for (final size in kV2Sizes) {
        final w = size.width.toInt(), h = size.height.toInt();
        testWidgets('home ${entry.key} $lang ${w}x$h', (tester) async {
          final key = GlobalKey();
          await _pump(tester, entry.key, entry.value(), lang: lang, size: size, key: key);
          await _settleClean(tester);
          await maybeShot(tester, key, 'home__home__${entry.key}__${lang}__${w}x$h');
        });
      }
    }
  }

  // Whole page in one tall frame (review shots; also lays out every section).
  for (final state in ['s0', 's6', 's8-rec', 's10', 's2-verifying', 's1', 's3', 'manual-rec']) {
    for (final lang in ['cs', 'en', 'de']) {
      testWidgets('home full $state $lang', (tester) async {
        final key = GlobalKey();
        await _pump(tester, state, cases[state]!(), lang: lang, size: const Size(390, 3600), key: key);
        await _settleClean(tester);
        await maybeShot(tester, key, 'home__full__${state}__${lang}__390x3600');
      });
    }
  }

  // Rank drives the look: header, funnel CTA, club card for key levels.
  for (final level in [0, 1, 6, 10, 15, 17, 19, 20]) {
    testWidgets('home rank $level', (tester) async {
      final key = GlobalKey();
      await _pump(tester, 's0', homeOverrides(funnel: kMotos.take(2).toList(), loyalty: level == 0 ? null : loyaltyAt(level)),
          rank: RankTokens.forLevel(level), size: const Size(390, 1600), key: key);
      await _settleClean(tester);
      await maybeShot(tester, key, 'home__rank__l${level}__cs__390x1600');
    });
  }

  // Reduced motion: everything settles (no endless loops), still no overflow.
  for (final state in ['s0', 's6', 's8-rec', 's10', 's2-verifying']) {
    testWidgets('home reduced motion $state', (tester) async {
      await _pump(tester, state, cases[state]!(), reduced: true);
      await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3)); // routes warm-up timer (2 s)
      expect(tester.takeException(), isNull);
    });
  }
}
