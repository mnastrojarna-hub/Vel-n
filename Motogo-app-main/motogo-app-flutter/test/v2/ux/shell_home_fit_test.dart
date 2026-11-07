// Fit of every new / changed shell_home text: 8 languages × 320 / 360 /
// 412 dp × text scale 1.0 / 1.3 — no overflow, no word split inside a word
// (render_inspect), no exception.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/home/v2/home_club_card_v2.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';
import 'package:motogo_app/features/home/v2/home_tier_preview_v2.dart';
import 'package:motogo_app/features/shell/v2/crash_view_v2.dart';
import 'package:motogo_app/features/shell/v2/offline_view_v2.dart';
import 'package:motogo_app/features/shell/v2/onboarding_lang_v2.dart';
import 'package:motogo_app/features/shell/v2/onboarding_perm_v2.dart';
import 'package:motogo_app/features/shell/v2/update_dialog_v2.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../render/cases_ux_shell_home.dart' show kOnbLangs, kOnbPerms;
import '../render/render_inspect.dart';
import '../screens/home_test.dart' show homeCases;
import '../support/fakes_home.dart';
import '../support/v2_harness.dart';

const _sizes = [Size(320, 690), Size(360, 780), Size(412, 915)];

Widget _scaled(double s, Widget child) =>
    Builder(builder: (c) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(s)), child: child));

Map<String, Widget Function()> _views() => {
      'lang': () => OnboardingLangV2(langs: kOnbLangs, onPick: (_) {}),
      'perm': () => Builder(
          builder: (c) => OnboardingPermV2(
              perms: kOnbPerms, allowLabel: t(c).tr('v2UxShPermAllow'), onAllow: () {}, onSkip: () {}, onBack: () {})),
      'perm_ios': () => Builder(builder: (c) => OnboardingPermV2(perms: kOnbPerms, allowLabel: t(c).tr('next'), onAllow: () {})),
      'offline': () => OfflineViewV2(checking: false, stillOffline: true, onRetry: () {}, onContinue: () {}, onCall112: () {}),
      'strip': () => Stack(children: [OfflineStripV2(offline: false)]),
      'crash': () => Builder(
          builder: (c) => CrashViewV2(
                title: t(c).tr('v2UxShCrashTitle'),
                why: t(c).tr('v2UxShCrashWhy'),
                homeLabel: t(c).tr('v2UxShCrashHome'),
                backLabel: t(c).tr('eoBack'),
                onHome: () {},
                onBack: () {},
              )),
      'force': () => Center(
          child: SingleChildScrollView(
              child: UpdateForceDialogV2(version: '4.3.0', storeFailed: true, onUpdate: () {}, onCall: () {}, onCall112: () {}))),
      'offer': () => Center(child: UpdateOfferDialogV2(version: '4.3.0', onLater: () {}, onUpdate: () {})),
      'tier': () => SingleChildScrollView(padding: const EdgeInsets.all(16), child: TierPreviewV2(rank: RankTokens.forLevel(17))),
    };

void _expectFits(WidgetTester tester, String id, String lang, Size size) {
  expect(tester.takeException(), isNull, reason: '$id $lang $size');
  final bad = inspectFrame(tester.binding.renderViews.first, lang, size)
      .where((f) => f.fail && (f.kind.startsWith('word-break') || f.kind == 'overflow'))
      .map((f) => '${f.kind}: ${f.text} ${f.detail}')
      .toList();
  expect(bad, isEmpty, reason: '$id $lang ${size.width.toInt()}');
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    mockPathProvider();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MgMotion.resetSession();
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('shell views fit · 8 langs × 320/360/412 · scale $scale', (tester) async {
      for (final v in _views().entries) {
        for (final lang in kV2Langs) {
          for (final size in _sizes) {
            await pumpV2(tester, _scaled(scale, v.value()), lang: lang, size: size, scaffold: v.key == 'tier' || v.key == 'force' || v.key == 'offer', reducedMotion: true);
            await tester.pump(const Duration(milliseconds: 50));
            _expectFits(tester, v.key, lang, size);
          }
        }
      }
    });

    testWidgets('Home S2 / S6 / S8 / club fit · 8 langs × 320/360/412 · scale $scale', (tester) async {
      final cases = homeCases();
      for (final state in ['s2', 's6', 's8-rec', 's7']) {
        for (final lang in kV2Langs) {
          for (final size in _sizes) {
            if (scale > 1 && size.width > 320) continue;
            await tester.pumpWidget(const SizedBox());
            await pumpV2(tester, _scaled(scale, const HomeScreenV2()),
                lang: lang, size: size, overrides: cases[state]!(), reducedMotion: true);
            await tester.pump(const Duration(milliseconds: 2200));
            _expectFits(tester, state, lang, size);
          }
        }
      }
      for (final lang in kV2Langs) {
        await tester.pumpWidget(const SizedBox());
        await pumpV2(tester, _scaled(scale, const SingleChildScrollView(child: HomeClubCardV2())),
            lang: lang, size: const Size(320, 690), overrides: homeOverrides(), reducedMotion: true);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byKey(const ValueKey('home-club-more')).first, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 300));
        _expectFits(tester, 'club', lang, const Size(320, 690));
      }
    });
  }
}
