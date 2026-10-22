// State templates T1 / T2 / T3 (DESIGN_V22 §5.2) in 8 languages × 2 sizes,
// plus the V-seams of the existing state widgets: v2 look with the scope ON,
// the untouched old widgets with it OFF.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/friendly_error.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/states/mg_state_banner.dart';
import 'package:motogo_app/core/v2/states/mg_state_screen.dart';
import 'package:motogo_app/core/v2/states/mg_state_sheet.dart';
import 'package:motogo_app/core/v2/states/mg_tone.dart';
import 'package:motogo_app/core/v2/widgets/mg_back_v2.dart';
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/core/widgets/error_feedback.dart';
import 'package:motogo_app/core/widgets/state_views.dart';

import 'support/v2_harness.dart';

Widget _t1(MgTone tone, {VoidCallback? onClose, VoidCallback? onPrimary}) => Builder(builder: (context) {
      final tr = t(context);
      return MgStateScreen(
        tone: tone,
        title: tr.tr('v2CalError'),
        why: tr.tr('v2CalBusyInRange').replaceAll('{date}', '24. 10.'),
        summary: tone == MgTone.ok || tone == MgTone.pending ? Text(tr.tr('v2CalNote')) : null,
        stepsTitle: tr.tr(tone == MgTone.ok ? 'v2StNext' : 'v2StFix'),
        steps: [tr.tr('v2CalPickEnd'), tr.tr('v2CalNote')],
        tech: 'code: card_declined · ref pi_123 · 2026-10-16 12:00',
        primary: MgStateAction(tr.tr('v2StWrite'), onPrimary ?? () {}),
        secondary: MgStateAction(tr.tr('v2ShowMore'), () {}),
        onClose: onClose ?? () {},
      );
    });

void main() {
  setUpAll(loadMontserrat);

  for (final tone in [MgTone.ok, MgTone.pending, MgTone.warn, MgTone.err, MgTone.info]) {
    for (final lang in kV2Langs) {
      for (final size in kV2Sizes) {
        testWidgets('T1 $tone $lang ${size.width.toInt()}', (tester) async {
          final key = GlobalKey();
          await pumpV2(tester, _t1(tone), lang: lang, size: size, scaffold: false, boundaryKey: key);
          await expectCleanFrames(tester);
          await maybeShot(tester, key, 'core__state_t1__${tone.name}__${lang}__${size.width.toInt()}x${size.height.toInt()}');
        });
      }
    }
  }

  testWidgets('T1: close + primary run the caller callbacks; settles reduced', (tester) async {
    var closed = 0, primary = 0;
    final h = tester.ensureSemantics();
    await pumpV2(tester, _t1(MgTone.err, onClose: () => closed++, onPrimary: () => primary++),
        scaffold: false, reducedMotion: true);
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(find.bySemanticsLabel('Zavřít'), findsOneWidget);
    await tester.tap(find.byType(MgV2Back));
    await tester.tap(find.byType(MgBtnInk));
    expect((closed, primary), (1, 1));
    h.dispose();
  });

  for (final lang in kV2Langs) {
    testWidgets('T2 sheet $lang: opens, ✕ closes, buttons call back', (tester) async {
      var retried = 0;
      await pumpV2(tester, Builder(builder: (context) {
        return Center(
          child: ElevatedButton(
            onPressed: () => showMgStateSheet<void>(
              context,
              tone: MgTone.err,
              title: t(context).tr('v2CalError'),
              why: t(context).tr('v2CalNote'),
              chips: [MgStateChip(t(context).trArgs('v2StAttempt', {'n': 2, 'max': 3})), MgStateChip(t(context).tr('v2StNoCharge'), MgTone.ok)],
              steps: [t(context).tr('v2CalPickEnd')],
              tech: 'stripe: card_declined',
              primary: MgStateAction(t(context).tr('retry'), () => retried++),
              secondary: MgStateAction(t(context).tr('close'), null),
            ),
            child: const Text('open'),
          ),
        );
      }), lang: lang);
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(MgBtnInk));
      expect(retried, 1);
      await tester.tap(find.byType(MgV2Back));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(MgStateSheetBody), findsNothing);
    });
  }

  testWidgets('T3 banners in every tone render (light + dark)', (tester) async {
    await pumpV2(tester, ListView(children: [
      for (final dark in [false, true])
        for (final tone in MgTone.values)
          Container(
            color: dark ? const Color(0xFF0E2A1C) : null,
            padding: const EdgeInsets.all(8),
            child: MgStateBanner(
              tone: tone,
              dark: dark,
              title: 'Obsazenost se nepodařila načíst',
              text: 'Zkontroluj připojení a zkus to znovu.',
              actions: [MgBtnText(label: 'Zkusit znovu', onTap: () {}, dark: dark)],
            ),
          ),
    ]));
    await expectCleanFrames(tester);
  });

  group('V-seams of existing state widgets', () {
    testWidgets('scope ON: MgErrorView / MgStaleNote / MgBackArrow use the v2 look', (tester) async {
      var retry = 0, back = 0;
      await pumpV2(tester, Column(children: [
        Expanded(child: MgErrorView(error: Exception('x'), onRetry: () => retry++, onBack: () => back++)),
        MgStaleNote(onRetry: () => retry++),
        MgBackArrow(onTap: () => back++),
      ]));
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.byType(MgToneDisc), findsOneWidget);
      expect(find.byType(MgStateBanner), findsOneWidget);
      expect(find.byType(MgV2Back), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
      await tester.tap(find.byType(MgBtnInk));
      await tester.tap(find.byType(MgV2Back));
      expect((retry, back), (1, 1));
    });

    testWidgets('scope OFF: the old widgets, untouched', (tester) async {
      await pumpV2(tester, Column(children: [
        Expanded(child: MgErrorView(error: Exception('x'), onRetry: () {})),
        MgStaleNote(onRetry: () {}),
        MgBackArrow(onTap: () {}),
      ]), v2: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ElevatedButton), findsOneWidget);
      expect(find.byType(MgToneDisc), findsNothing);
      expect(find.byType(MgStateBanner), findsNothing);
      expect(find.byType(MgV2Back), findsNothing);
    });

    testWidgets('MgStateScaffold + MgLoadingView v2 keep their callbacks', (tester) async {
      var back = 0;
      await pumpV2(tester, MgStateScaffold(title: 'Zprávy', onBack: () => back++, child: const MgLoadingView()),
          scaffold: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AppBar), findsNothing);
      await tester.tap(find.byType(MgV2Back));
      expect(back, 1);
      // 15 s "trvá to déle" still comes from the old State.
      await tester.pump(const Duration(seconds: 16));
      expect(find.text(t(tester.element(find.byType(MgLoadingView))).tr('eoSlowTitle')), findsOneWidget);
    });

    testWidgets('dialogs: confirmDiscard v2 returns the same values', (tester) async {
      bool? result;
      await pumpV2(tester, Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async => result = await confirmDiscard(context),
          child: const Text('open'),
        );
      }));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.byType(MgBtnDestructive));
      await tester.pump(const Duration(milliseconds: 400));
      expect(result, isTrue);

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byType(MgBtnGhostLight));
      await tester.pump(const Duration(milliseconds: 400));
      expect(result, isFalse);
    });

    test('tone of a FriendlyError', () {
      expect(const FriendlyError(FriendlyKind.offline).isNetwork, isTrue);
    });
  });
}
