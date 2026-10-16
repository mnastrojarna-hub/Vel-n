// Matrix runner for the Profil v2 screen tests: every case in all 8
// languages × 360×780 and 412×915 (no exception / overflow), one
// reduced-motion pass that must settle, PNGs into MG_SHOTS_DIR when set.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'v2_harness.dart';

class PfCase {
  final String screen;
  final String state;
  final Widget Function() build;
  final List<Override> Function() overrides;
  final int level;
  final Future<void> Function(WidgetTester)? after;
  final bool settle;
  const PfCase(this.screen, this.state, this.build, this.overrides,
      {this.level = 3, this.after, this.settle = true});
}

void pfMatrix(List<PfCase> cases) {
  setUp(() {
    MgMotion.resetSession();
    SharedPreferences.setMockInitialValues({});
  });
  for (final c in cases) {
    group('${c.screen} ${c.state}', () {
      for (final lang in kV2Langs) {
        for (final size in kV2Sizes) {
          testWidgets('$lang ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
            final key = GlobalKey();
            await pumpV2(tester, c.build(),
                lang: lang, size: size, overrides: c.overrides(), rank: RankTokens.forLevel(c.level), boundaryKey: key);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 50));
            if (c.after != null) await c.after!(tester);
            await expectCleanFrames(tester);
            await maybeShot(tester, key, 'profile__${c.screen}__${c.state}__${lang}__${size.width.toInt()}x${size.height.toInt()}');
          });
        }
      }
    });
  }
  group('reduced motion settles', () {
    for (final c in cases.where((c) => c.settle)) {
      testWidgets('${c.screen} ${c.state}', (tester) async {
        await pumpV2(tester, c.build(), overrides: c.overrides(), reducedMotion: true, rank: RankTokens.forLevel(c.level));
        await tester.pump();
        if (c.after != null) await c.after!(tester);
        await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
        expect(tester.takeException(), isNull);
      });
    }
  });
}

/// Taps the first widget found by [finder] (scrolling it into view) — used
/// to open sheets / dialogs from a launcher button.
Future<void> pfTap(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder.first);
  await t.pump();
  await t.tap(finder.first, warnIfMissed: false);
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
}

/// A button that runs [open] with a context below the app (sheet / dialog
/// launchers).
Widget pfLauncher(void Function(BuildContext) open) =>
    Builder(builder: (c) => Center(child: ElevatedButton(onPressed: () => open(c), child: const Text('OPEN'))));
