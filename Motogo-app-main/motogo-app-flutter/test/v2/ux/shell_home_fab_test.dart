// SH-12: the AI disc never sits on the ½ offer box (tap zone) — real
// AppShellV2 + HomeScreenV2 at 360×780 cs and 320×690 uk, at rest.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/feature_flags.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/pending_booking_fab_provider.dart';
import 'package:motogo_app/core/v2/chrome/mg_ai_fab.dart';
import 'package:motogo_app/core/v2/flag/v2_scope.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/core/v2/rank/rank_provider.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/core/v2/shell/app_shell_v2.dart';
import 'package:motogo_app/core/v2/widgets/mg_surfaces.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';
import 'package:motogo_app/features/messages/messages_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/home_test.dart' show homeCases;
import '../support/fakes_home.dart';
import '../support/v2_harness.dart';

class _Locale extends LocaleNotifier {
  _Locale(String l) {
    state = Locale(l);
  }
}

Future<void> _pump(WidgetTester tester, String lang, Size size) async {
  SharedPreferences.setMockInitialValues({'mg_v2_ai_coach_seen': true});
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final router = GoRouter(initialLocation: '/', routes: [
    ShellRoute(
      builder: (_, __, child) => AppShellV2(child: child),
      routes: [GoRoute(path: '/', builder: (_, __) => const HomeScreenV2())],
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...homeCases()['s0']!(),
      localeProvider.overrideWith((ref) => _Locale(lang)),
      rankTokensProvider.overrideWithValue(RankTokens.forLevel(3)),
      rankArcPctProvider.overrideWithValue(50),
      appV2UiProvider.overrideWith((ref) => AppV2UiNotifier(fetch: () async => null, autoRefresh: false, initial: true)),
      paidAfterRestartProvider.overrideWith((ref) async => null),
      adminUnreadCountProvider.overrideWithValue(0),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      locale: Locale(lang),
      supportedLocales: supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: v2TestTheme(),
      builder: (c, child) => MgV2Scope(
        enabled: true,
        child: MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.noScaling, disableAnimations: true),
          child: child!,
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 2400));
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    mockPathProvider();
  });
  setUp(MgMotion.resetSession);

  for (final (lang, size) in [('cs', const Size(360, 780)), ('uk', const Size(320, 690))]) {
    testWidgets('SH-12 AI disc never on the offer box · $lang ${size.width.toInt()}', (tester) async {
      await _pump(tester, lang, size);
      final offer = find.byType(MgTintFeature);
      expect(offer, findsOneWidget);
      // Scroll the offer through the viewport; at every rest stop the disc
      // must not cover its text.
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      for (var y = 0.0; y <= 600; y += 150) {
        scroll.jumpTo(y.clamp(0, scroll.maxScrollExtent));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        final disc = find.descendant(of: find.byType(MgAiFab), matching: find.byType(MgAiDisc));
        if (disc.evaluate().isEmpty) continue;
        // "off" = invisible (opacity 0, no taps) → nothing is covered.
        final fade = find.ancestor(of: disc.first, matching: find.byType(AnimatedOpacity));
        if (tester.widget<AnimatedOpacity>(fade.first).opacity == 0) continue;
        final d = tester.getRect(disc.first).deflate(4);
        // The painted glyphs of every offer text line (not the text boxes).
        for (final e in find.descendant(of: offer, matching: find.byType(RichText)).evaluate()) {
          final p = e.renderObject! as RenderParagraph;
          final text = p.text.toPlainText();
          for (final b in p.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: text.length))) {
            final r = MatrixUtils.transformRect(p.getTransformTo(null), b.toRect());
            if (r.bottom < 0 || r.top > size.height) continue;
            expect(d.overlaps(r), isFalse, reason: 'scroll $y: disc $d over "$text" $r');
          }
        }
      }
    });
  }
}
