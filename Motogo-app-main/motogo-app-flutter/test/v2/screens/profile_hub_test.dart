// v2 Profil hub `/profile` (PLAN §5.3, area "profile"): the v2
// hub view (built like the ProfileScreen seam), every state in all 8 languages × 360×780
// and 412×915 — fails on any exception or overflow; PNGs into MG_SHOTS_DIR
// when set (+ tall full-scroll shots).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/features/loyalty/loyalty_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes_home.dart' show kLoyalty3, loyaltyAt, mockPathProvider;
import '../support/fakes_profile.dart';
import '../support/profile_harness.dart';
import '../support/v2_harness.dart';

typedef _Case = ({String name, int level, List<Override> Function() overrides, bool open});

List<_Case> _cases() => [
      (name: 'all_ok', level: 3, overrides: () => profileOverrides(), open: false),
      (name: 'docs_missing', level: 3, overrides: () => profileOverrides(docs: PfDocs.missing), open: false),
      (name: 'sos_rental', level: 6, overrides: () => profileOverrides(reservations: activeRental(), loyalty: loyaltyAt(6)), open: false),
      (
        name: 'new_customer',
        level: 1,
        overrides: () => profileOverrides(profile: kProfileNew, docs: PfDocs.none, unread: 0, loyalty: loyaltyAt(1)),
        open: false,
      ),
      (name: 'loading', level: 3, overrides: () => profileOverrides(profileLoading: true, docs: PfDocs.unknown), open: false),
      (name: 'error', level: 3, overrides: () => profileOverrides(profileError: true), open: false),
      (name: 'eshop_on', level: 17, overrides: () => profileOverrides(eshop: true, loyalty: loyaltyAt(17), unread: 12), open: false),
      (name: 'legend', level: 20, overrides: () => profileOverrides(loyalty: loyaltyAt(20)), open: false),
      (name: 'guest_rank', level: 0, overrides: () => profileOverrides(loyalty: null), open: false),
      (name: 'form_open', level: 3, overrides: () => profileOverrides(), open: true),
    ];

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerProfileStrings();
    mockPathProvider();
  });
  setUp(() {
    MgMotion.resetSession();
    SharedPreferences.setMockInitialValues({});
  });

  final cases = _cases();
  for (final c in cases) {
    group(c.name, () {
      for (final lang in kV2Langs) {
        for (final size in kV2Sizes) {
          testWidgets('$lang ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
            final key = GlobalKey();
            await pumpV2(tester, PfHubHarness(expanded: c.open),
                lang: lang, size: size, overrides: c.overrides(), rank: RankTokens.forLevel(c.level), boundaryKey: key);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 50));
            await expectCleanFrames(tester);
            await maybeShot(tester, key, 'profile__hub__${c.name}__${lang}__${size.width.toInt()}x${size.height.toInt()}');
          });
        }
      }
    });
  }

  group('reduced motion settles', () {
    for (final c in cases.where((c) => c.name != 'loading')) {
      testWidgets(c.name, (tester) async {
        await pumpV2(tester, PfHubHarness(expanded: c.open),
            overrides: c.overrides(), reducedMotion: true, rank: RankTokens.forLevel(c.level));
        await tester.pump();
        await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('tall shots', () {
    for (final c in cases.where((c) => const {'all_ok', 'docs_missing', 'sos_rental', 'new_customer', 'form_open', 'eshop_on'}.contains(c.name))) {
      for (final lang in const ['cs', 'en', 'de', 'uk']) {
        testWidgets('${c.name} $lang', (tester) async {
          final key = GlobalKey();
          await pumpV2(tester, PfHubHarness(expanded: c.open),
              lang: lang, size: const Size(412, 3000), overrides: c.overrides(), rank: RankTokens.forLevel(c.level), boundaryKey: key);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          await expectCleanFrames(tester);
          await maybeShot(tester, key, 'profile__tall__${c.name}__${lang}__412x3000');
        });
      }
    }
  });

  test('fixtures sanity', () {
    expect(kLoyalty3.level, 3);
    expect(const LoyaltyStatus(level: 1, percent: 1, rankName: 'x', colorHex: '#000000', qualifyingCount: 0).isMax, isFalse);
  });
}
