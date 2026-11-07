// FND-18 tone motion (✓ draws in, pending → ok morph, SOS tone, plain
// hero), FND-20 CTA leading icon, choice card, back arrow surface.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/icons/mg_icon.dart';
import 'package:motogo_app/core/v2/rank/rank_hero.dart';
import 'package:motogo_app/core/v2/states/mg_state_banner.dart';
import 'package:motogo_app/core/v2/states/mg_state_screen.dart';
import 'package:motogo_app/core/v2/states/mg_state_sheet.dart';
import 'package:motogo_app/core/v2/states/mg_tone.dart';
import 'package:motogo_app/core/v2/tokens/mg_colors.dart';
import 'package:motogo_app/core/v2/widgets/mg_back_v2.dart';
import 'package:motogo_app/core/v2/widgets/mg_choice_card.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/core/widgets/state_views.dart' show MgBackArrow;

import '../support/v2_harness.dart';

double _progress(WidgetTester tester) => (tester
        .widget<CustomPaint>(find.descendant(of: find.byType(MgToneFace), matching: find.byType(CustomPaint)).first)
        .painter! as MgIconPainter)
    .progress;

void main() {
  setUpAll(loadMontserrat);

  testWidgets('✓ draws in over 300 ms, then pop + one ripple', (tester) async {
    await pumpV2(tester, const Center(child: MgToneDisc(tone: MgTone.ok, size: 88)));
    await tester.pump(const Duration(milliseconds: 150));
    expect(_progress(tester), inExclusiveRange(0.0, 1.0));
    expect(find.byKey(const ValueKey('mg-tone-ripple')), findsNothing);
    await tester.pump(const Duration(milliseconds: 250));
    expect(_progress(tester), 1);
    expect(find.byKey(const ValueKey('mg-tone-ripple')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mg-tone-ripple')), findsNothing);
  });

  testWidgets('reduced motion: the final ✓ on the first pump', (tester) async {
    await pumpV2(tester, const Center(child: MgToneDisc(tone: MgTone.ok)), reducedMotion: true);
    expect(_progress(tester), 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('pending → ok in place: the ring closes into the ✓', (tester) async {
    final tone = ValueNotifier(MgTone.pending);
    await pumpV2(
      tester,
      Center(child: ValueListenableBuilder<MgTone>(valueListenable: tone, builder: (_, t, __) => MgToneDisc(tone: t, dark: true))),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(MgTonePendingRing), findsOneWidget);
    tone.value = MgTone.ok;
    await tester.pump();
    expect(find.byType(MgToneMorph), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.descendant(of: find.byType(MgToneMorph), matching: find.byWidgetPredicate((w) => w is CustomPaint && w.foregroundPainter is MgSweepPainter)), findsOneWidget);
    await tester.pumpAndSettle();
    expect(_progress(tester), 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('SOS tone: red disc, white icon (disc, banner, sheet)', (tester) async {
    await pumpV2(
      tester,
      const SingleChildScrollView(
        child: Column(children: [
          MgToneDisc(tone: MgTone.sos),
          MgStateBanner(tone: MgTone.sos, title: 'Nehoda'),
          MgStateSheetBody(tone: MgTone.sos, title: 'Volej 112', support: false),
        ]),
      ),
    );
    final faces = tester.widgetList<MgToneFace>(find.byType(MgToneFace)).toList();
    expect(faces, isNotEmpty);
    for (final f in faces) {
      expect(f.style.disc, MgColors.sos);
      expect(f.style.icon, MgColors.onDark);
    }
    expect(find.text('Nehoda'), findsOneWidget);
  });

  testWidgets('MgStateScreen rankAura: false → plain dark hero, no rank aura', (tester) async {
    await pumpV2(tester, MgStateScreen(tone: MgTone.ok, title: 'Hlášení odesláno', rankAura: false, primary: MgStateAction('Hotovo', () {})), scaffold: false);
    expect(find.byType(MgRankHero), findsNothing);
    expect(find.byKey(const ValueKey('mg-state-plain-hero')), findsOneWidget);
    expect(find.byType(MgCta), findsNothing);
    await pumpV2(tester, MgStateScreen(tone: MgTone.ok, title: 'Zaplaceno', primary: MgStateAction('Hotovo', () {})), scaffold: false);
    expect(find.byType(MgRankHero), findsOneWidget);
  });

  testWidgets('MgCta leadingIcon: "ENREGISTRER LA SORTIE" on one line in 294 px', (tester) async {
    await pumpV2(
      tester,
      Center(child: SizedBox(width: 294, child: MgCta(label: 'Enregistrer la sortie', onTap: () {}, leadingIcon: MgIcons.record))),
      lang: 'fr',
    );
    expect(tester.takeException(), isNull);
    expect(find.byWidgetPredicate((w) => w is MgIcon && w.name == MgIcons.record), findsOneWidget);
    final text = tester.getSize(find.textContaining('ENREGISTRER', findRichText: true));
    expect(text.height, lessThan(26), reason: 'one line');
  });

  testWidgets('MgChoiceCard: selected = ✓ disc + radio semantics', (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await pumpV2(
      tester,
      Column(children: [
        MgChoiceCard(title: 'Nehoda', sub: 'Jsem v pořádku', selected: true, onTap: () => taps++),
        MgChoiceCard(title: 'Porucha', selected: false, onTap: () => taps++),
      ]),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('mg-choice-check')), findsOneWidget);
    expect(tester.getSize(find.byType(MgChoiceCard).last).height, greaterThanOrEqualTo(64));
    expect(tester.getSemantics(find.byType(MgChoiceCard).first),
        matchesSemantics(isButton: true, hasCheckedState: true, isChecked: true, hasSelectedState: true, isSelected: true,
            isInMutuallyExclusiveGroup: true, hasEnabledState: true, isEnabled: true, hasTapAction: true, label: 'Nehoda, Jsem v pořádku'));
    await tester.tap(find.text('Porucha'));
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('MgBackArrow v2Style: light disc on light pages; default unchanged', (tester) async {
    await pumpV2(tester, Row(children: [
      MgBackArrow(onTap: () {}, v2Style: MgBackStyle.light),
      MgBackArrow(onTap: () {}),
      MgBackArrow(onTap: () {}, dark: true),
    ]));
    final styles = tester.widgetList<MgV2Back>(find.byType(MgV2Back)).map((b) => b.style).toList();
    expect(styles, [MgBackStyle.light, MgBackStyle.dark, MgBackStyle.light]);
  });
}
