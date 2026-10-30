// fix:shared r3 regressions: SOS headers / CTAs fit at 320–412 in every
// language, StaggeredReveal + MotoSuccessHero settle at once under reduced
// motion, the pinned back of MgPage collapses into a light bar once the hero
// is gone (photo disc only over the hero), and the v2 theme overlay gives old
// text fields the lineInput look while borderless fields stay borderless.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/chrome/mg_page.dart';
import 'package:motogo_app/core/v2/tokens/mg_colors.dart';
import 'package:motogo_app/core/v2/widgets/mg_back_v2.dart';
import 'package:motogo_app/core/widgets/address_autocomplete_field.dart';
import 'package:motogo_app/core/widgets/moto_fx.dart';
import 'package:motogo_app/features/catalog/catalog_provider.dart';
import 'package:motogo_app/features/catalog/moto_model.dart';
import 'package:motogo_app/features/sos/sos_detail_screen.dart';
import 'package:motogo_app/features/sos/sos_provider.dart';
import 'package:motogo_app/features/sos/sos_replacement_screen.dart';
import 'package:motogo_app/features/sos/sos_report_screen.dart';

import 'support/v2_harness.dart';

const _motos = [
  Motorcycle(id: 'm1', model: 'BMW R 1250 GS Adventure', category: 'cestovni'),
  Motorcycle(id: 'm2', model: 'Kawasaki Z900', category: 'naked'),
];

SosIncident _inc(String type) => SosIncident(
    id: 'abcdef12-3456-7890-abcd-ef1234567890', type: type, status: 'reported', createdAt: DateTime(2026, 10, 1, 9));

const _sizes = [Size(320, 640), Size(360, 780), Size(412, 915)];

InputBorder _border(WidgetTester tester, Key key) {
  final w = tester.widget(find.descendant(
      of: find.byKey(key), matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_BorderContainer')));
  return (w as dynamic).border as InputBorder;
}

void main() {
  setUpAll(loadMontserrat);

  final screens = <String, (Widget, SosIncident?)>{
    'replacement': (const SosReplacementScreen(), null),
    'report': (const SosReportScreen(), null),
    'detail_major': (const SosDetailScreen(), _inc('accident_major')),
    'detail_minor': (const SosDetailScreen(), _inc('breakdown_minor')),
  };
  for (final lang in kV2Langs) {
    for (final size in _sizes) {
      for (final e in screens.entries) {
        testWidgets('sos ${e.key} $lang ${size.width.toInt()}: header + CTA fit', (tester) async {
          await pumpV2(tester, e.value.$1,
              lang: lang,
              size: size,
              dpr: 1,
              reducedMotion: true,
              scaffold: false,
              overrides: [
                motorcyclesProvider.overrideWith((ref) => Stream.value(_motos)),
                activeSosProvider.overrideWith((ref) => Stream.value(e.value.$2)),
                sosTimelineProvider.overrideWith((ref, id) => Stream.value(const [])),
              ]);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('StaggeredReveal + MotoSuccessHero settle at once under reduced motion', (tester) async {
    await pumpV2(
        tester,
        const Column(children: [
          MotoSuccessHero(),
          StaggeredReveal(index: 4, child: Text('Zaplaceno')),
        ]),
        reducedMotion: true);
    await tester.pump();
    final op = tester.widget<Opacity>(find.ancestor(of: find.text('Zaplaceno'), matching: find.byType(Opacity)).first);
    expect(op.opacity, 1);
    expect(find.text('✓'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('StaggeredReveal still animates in with motion on', (tester) async {
    await pumpV2(tester, const StaggeredReveal(child: Text('Ahoj')));
    await tester.pump();
    expect(tester.widget<Opacity>(find.ancestor(of: find.text('Ahoj'), matching: find.byType(Opacity)).first).opacity, 0);
    await tester.pump(const Duration(milliseconds: 600)); // delay 550 ms
    await tester.pump(const Duration(milliseconds: 500)); // fade 420 ms
    expect(tester.widget<Opacity>(find.ancestor(of: find.text('Ahoj'), matching: find.byType(Opacity)).first).opacity, 1);
  });

  group('pinned back', () {
    const back = ValueKey('mg-pinned-back');
    const bar = ValueKey('mg-pinned-bar');
    List<Widget> rows() => [for (var i = 0; i < 30; i++) SizedBox(height: 80, child: Text('row $i'))];

    testWidgets('header page: light bar with title once the hero is gone', (tester) async {
      final ctrl = ScrollController();
      var taps = 0;
      await pumpV2(
          tester,
          MgPage(
            controller: ctrl,
            pinnedBack: () => taps++,
            pinnedTitle: 'BMW R 1250 GS Adventure',
            header: Container(height: 300, color: Colors.black),
            sections: rows(),
          ),
          reducedMotion: true,
          scaffold: false);
      await tester.pump();
      expect(find.byKey(back), findsNothing);
      ctrl.jumpTo(260);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(bar), findsOneWidget);
      expect(tester.widget<MgV2Back>(find.byKey(back)).style, MgBackStyle.light);
      expect(find.text('BMW R 1250 GS Adventure'), findsOneWidget);
      await tester.tap(find.byKey(back));
      expect(taps, 1);
      ctrl.jumpTo(0);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(back), findsNothing);
    });

    testWidgets('section hero: photo disc over the hero, bar after it', (tester) async {
      final ctrl = ScrollController();
      await pumpV2(
          tester,
          MgPage(
            controller: ctrl,
            overlapHero: false,
            pinnedBack: () {},
            sections: [Container(height: 400, color: Colors.black), ...rows()],
          ),
          reducedMotion: true,
          scaffold: false);
      await tester.pump();
      ctrl.jumpTo(120);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(bar), findsNothing);
      expect(tester.widget<MgV2Back>(find.byKey(back)).style, MgBackStyle.photo);
      ctrl.jumpTo(420);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(bar), findsOneWidget);
      expect(tester.widget<MgV2Back>(find.byKey(back)).style, MgBackStyle.light);
    });
  });

  testWidgets('v2 overlay: old outline fields get lineInput, focus #0D6E0D, borderless stays borderless', (tester) async {
    const outline = Key('outline');
    const none = Key('none');
    await pumpV2(
        tester,
        Column(children: [
          TextField(
              key: outline,
              decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
          const TextField(key: none, decoration: InputDecoration(border: InputBorder.none)),
        ]));
    var b = _border(tester, outline);
    expect(b.borderSide.color, MgColors.lineInput);
    expect(b.borderSide.width, 1.5);
    expect((b as OutlineInputBorder).borderRadius, BorderRadius.circular(10));
    expect(_border(tester, none).borderSide, BorderSide.none);
    await tester.tap(find.byKey(outline));
    await tester.pump(const Duration(milliseconds: 300));
    b = _border(tester, outline);
    expect(b.borderSide.color, MgColors.focusLight);
    expect(b.borderSide.width, 2);
    final ctx = tester.element(find.byKey(outline));
    expect(Theme.of(ctx).textSelectionTheme.cursorColor, MgColors.ink);
  });

  testWidgets('address field: v2 lineInput frame, focus #0D6E0D', (tester) async {
    await pumpV2(tester, AddressAutocompleteField(onSelected: (_) {}, hint: 'Město'));
    Border frame() => tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.foregroundDecoration)
        .whereType<BoxDecoration>()
        .first
        .border! as Border;
    expect(frame().top.color, MgColors.lineInput);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(frame().top.color, MgColors.focusLight);
    expect(frame().top.width, 2);
  });
}
