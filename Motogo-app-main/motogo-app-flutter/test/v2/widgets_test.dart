// Shared v2 widgets: render in 8 languages × 2 phone sizes without overflow,
// rank CTA across tiers (loop on / off, reduced motion settles), callbacks.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/icons/mg_icon.dart';
import 'package:motogo_app/core/v2/rank/rank_tokens.dart';
import 'package:motogo_app/core/v2/widgets/mg_back_v2.dart';
import 'package:motogo_app/core/v2/widgets/mg_buttons.dart';
import 'package:motogo_app/core/v2/widgets/mg_chips.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/core/v2/widgets/mg_inputs.dart';
import 'package:motogo_app/core/v2/widgets/mg_price.dart';
import 'package:motogo_app/core/v2/widgets/mg_row.dart';
import 'package:motogo_app/core/v2/widgets/mg_section.dart';
import 'package:motogo_app/core/v2/widgets/mg_segmented.dart';
import 'package:motogo_app/core/v2/widgets/mg_skeleton.dart';
import 'package:motogo_app/core/v2/widgets/mg_stat_tile.dart';
import 'package:motogo_app/core/v2/widgets/mg_surfaces.dart';
import 'package:motogo_app/core/v2/widgets/mg_timeline.dart';

import 'support/v2_harness.dart';

/// Everything at once (light page + one dark block), with real strings.
class _Gallery extends StatelessWidget {
  const _Gallery();

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    // Not lazy: every widget must build and lay out (a ListView would skip
    // the off-screen part).
    return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      MgSectionHeader(title: tr.tr('v2CalLegYours'), eyebrow: tr.tr('v2YourPrice'), trailingLabel: tr.tr('v2ShowMore'), onTrailing: () {}),
      MgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MgRow(icon: MgIcons.calc, title: tr.tr('v2StTech'), sub: tr.tr('v2CalNote'), chevron: true, onTap: () {}),
          MgRow(icon: MgIcons.phone, title: tr.tr('v2StCall'), trailingValue: '12 027 Kč', divider: true),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            MgChoiceChip(label: '09:00', selected: true, onTap: () {}),
            MgChoiceChip(label: '12:00', sub: tr.tr('v2CalLegYours'), selected: false, onTap: () {}),
            MgFilterChip(label: tr.tr('v2CalLegFree'), count: 12, onTap: () {}),
            MgMeaningChip(label: tr.tr('v2StNoCharge'), tone: MgTone.ok),
            MgMeaningChip(label: tr.tr('v2CalLegPending'), tone: MgTone.pending),
            MgMeaningChip(label: tr.tr('v2CalError'), tone: MgTone.err),
            const MgTag('návrh'),
            MgRankChip(label: 'Motorkář · −3 %', onLight: true, onTap: () {}),
          ]),
          const SizedBox(height: 12),
          MgSegmented<int>(
            value: 1,
            onChanged: (_) {},
            segments: [
              MgSegment(value: 0, label: tr.tr('v2TabRoutes'), icon: MgIcons.route),
              MgSegment(value: 1, label: tr.tr('v2CalLegPending'), icon: MgIcons.pin),
              MgSegment(value: 2, label: tr.tr('v2CalLegOther'), icon: MgIcons.star),
            ],
            iconAbove: true,
          ),
          const SizedBox(height: 12),
          TextField(decoration: mgInputDecoration(context, label: tr.tr('v2StWrite'), error: tr.tr('v2CalError'))),
          MgSwitchRow(title: tr.tr('v2CalLegYours'), sub: tr.tr('v2CalNote'), value: true, onChanged: (_) {}),
          MgCheckRow(value: false, label: tr.tr('v2CalPickEnd'), onChanged: (_) {}),
          Row(children: [
            Expanded(child: MgStatTile(value: '12', label: tr.tr('v2TabRoutes'), icon: MgIcons.route)),
            const SizedBox(width: 10),
            Expanded(child: MgStatTile(value: '1 284 km', label: tr.tr('v2CalLegOther'), onTap: () {})),
          ]),
          const SizedBox(height: 12),
          MgPrice(label: tr.tr('v2YourPrice'), value: '10 189 Kč', struck: '11 893 Kč', suffix: tr.tr('v2PerDay').replaceAll('{amount}', '')),
          const SizedBox(height: 12),
          MgBtnInk(label: tr.tr('v2StWrite'), onTap: () {}, icon: MgIcons.chat),
          const SizedBox(height: 8),
          MgBtnGhostLight(label: tr.tr('v2CalPickEnd'), onTap: () {}),
          MgBtnText(label: tr.tr('v2ShowLess'), onTap: () {}),
          MgBtnDestructive(label: tr.tr('v2CalLegRemoved'), onTap: () {}),
          const SizedBox(height: 8),
          MgBtnSos(label: 'SOS', onTap: () {}),
          const SizedBox(height: 8),
          const MgSkeletonCard(),
        ]),
      ),
      const SizedBox(height: 16),
      MgDarkHero(
        rankAura: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MgTotalBox(
            eyebrow: '${tr.tr('v2YourPrice')} · 3 ${tr.daysWord(3)}',
            value: '10 189 Kč',
            sub: tr.trArgs('v2AvgPerDay', {'amount': '3 396 Kč'}),
            savingsChip: MgMeaningChip(label: tr.trArgs('v2RankSaves', {'amount': '305 Kč'}), tone: MgTone.ok, dark: true),
            onBreakdown: () {},
            breakdownOpen: true,
            breakdown: const Text('…'),
          ),
          const SizedBox(height: 12),
          MgTimeline(dark: true, steps: [
            MgTimelineStep(title: tr.tr('v2CalPickup'), sub: 'pá 23. 10.', state: MgStepState.done),
            MgTimelineStep(title: tr.tr('v2TabRoutes'), state: MgStepState.current, live: true),
            MgTimelineStep(title: tr.tr('v2CalReturn'), state: MgStepState.future),
          ]),
          const SizedBox(height: 12),
          MgCta(label: tr.tr('v2TabBookings'), price: '10 189 Kč', onTap: () {}, loop: true, size: MgCtaSize.lg60),
          const SizedBox(height: 8),
          MgCta(label: tr.tr('v2CalPickEnd'), onTap: () {}, size: MgCtaSize.sm48, arrow: true),
          const SizedBox(height: 8),
          MgBtnGhostDark(label: tr.tr('v2ShowMore'), onTap: () {}),
          const SizedBox(height: 8),
          Row(children: [
            MgV2Back(onTap: () {}),
            MgV2Back(onTap: () {}, close: true, style: MgBackStyle.photo),
            MgIconButton(icon: MgIcons.bell, onTap: () {}, semanticLabel: 'bell', badge: 3),
          ]),
        ]),
      ),
    ]));
  }
}

void main() {
  setUpAll(loadMontserrat);

  for (final lang in kV2Langs) {
    for (final size in kV2Sizes) {
      testWidgets('gallery $lang ${size.width.toInt()}: no overflow', (tester) async {
        final key = GlobalKey();
        await pumpV2(tester, const _Gallery(), lang: lang, size: size, boundaryKey: key);
        await expectCleanFrames(tester);
        await maybeShot(tester, key, 'core__widgets__gallery__${lang}__${size.width.toInt()}x${size.height.toInt()}');
      });
    }
  }

  testWidgets('gallery settles under reduced motion (no endless loops)', (tester) async {
    await pumpV2(tester, const _Gallery(), reducedMotion: true);
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  for (final level in [0, 1, 3, 6, 10, 15, 16, 17, 18, 19, 20]) {
    for (final loop in [true, false]) {
      testWidgets('MgCta rank $level loop=$loop', (tester) async {
        var taps = 0;
        await pumpV2(
          tester,
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: MgCta(label: 'Rezervovat', price: '10 189 Kč', onTap: () => taps++, loop: loop, size: MgCtaSize.lg60),
            ),
          ),
          rank: RankTokens.forLevel(level),
        );
        await tester.pump(const Duration(milliseconds: 1500));
        expect(tester.takeException(), isNull);
        await tester.tap(find.byType(MgCta));
        expect(taps, 1);
      });
    }
  }

  testWidgets('MgCta busy / disabled: no tap, semantics disabled', (tester) async {
    var taps = 0;
    final h = tester.ensureSemantics();
    await pumpV2(tester, Column(children: [
      MgCta(label: 'Zaplatit', onTap: () => taps++, busy: true),
      MgCta(label: 'Hotovo', onTap: () => taps++, enabled: false),
    ]));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byType(MgCta).first, warnIfMissed: false);
    await tester.tap(find.byType(MgCta).last, warnIfMissed: false);
    expect(taps, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.getSemantics(find.bySemanticsLabel('Hotovo')),
        matchesSemantics(isButton: true, hasEnabledState: true, isEnabled: false, label: 'Hotovo'));
    h.dispose();
  });

  for (final style in MgBackStyle.values) {
    testWidgets('MgV2Back $style: label, 48 px hit area, same callback', (tester) async {
      var taps = 0;
      final h = tester.ensureSemantics();
      await pumpV2(tester, Center(child: MgV2Back(onTap: () => taps++, style: style)));
      expect(find.bySemanticsLabel('Zpět'), findsOneWidget);
      final r = tester.getRect(find.byType(MgV2Back));
      await tester.tapAt(r.topLeft + const Offset(-1.5, -1.5)); // inside the 48 px slop
      await tester.tap(find.byType(MgV2Back));
      expect(taps, 2);
      h.dispose();
    });
  }

  testWidgets('MgV2Back close = "Zavřít"', (tester) async {
    final h = tester.ensureSemantics();
    await pumpV2(tester, Center(child: MgV2Back(onTap: () {}, close: true, style: MgBackStyle.light)));
    expect(find.bySemanticsLabel('Zavřít'), findsOneWidget);
    h.dispose();
  });

  testWidgets('MgSegmented reports the tapped value', (tester) async {
    String? v;
    await pumpV2(tester, MgSegmented<String>(
      value: 'a',
      onChanged: (x) => v = x,
      dark: true,
      segments: const [MgSegment(value: 'a', label: 'Najít motorku'), MgSegment(value: 'b', label: 'Spočítat cenu')],
    ));
    await tester.tap(find.text('Spočítat cenu'));
    expect(v, 'b');
  });

  testWidgets('MgCheckRow / MgSwitchRow toggle through the same callback', (tester) async {
    bool? check, sw;
    await pumpV2(tester, Column(children: [
      MgCheckRow(value: false, label: 'Souhlasím s VOP', onChanged: (x) => check = x),
      MgSwitchRow(title: 'Oznámení', value: false, onChanged: (x) => sw = x),
    ]));
    await tester.tap(find.text('Souhlasím s VOP'));
    await tester.tap(find.text('Oznámení'));
    expect(check, isTrue);
    expect(sw, isTrue);
  });
}
