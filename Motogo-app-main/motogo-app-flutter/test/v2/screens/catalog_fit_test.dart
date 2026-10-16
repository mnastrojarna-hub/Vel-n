// fix:catalog (verify:render) — catalog v2 layout guards at 320 dp and
// large text: spec tiles 2 × 2 without overflow, caps labels / values never
// split in half, the mode switch stacks its icon, the grid badge stays in
// the card, the full card grows instead of clipping and stacks price + CTA,
// the loyalty-failure note gets the full row.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/motion/mg_anim.dart';
import 'package:motogo_app/features/catalog/v2/catalog_mode.dart';
import 'package:motogo_app/features/catalog/v2/catalog_mode_switch_v2.dart';
import 'package:motogo_app/features/catalog/v2/catalog_price.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_specs_v2.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_trip_card_v2.dart';
import 'package:motogo_app/features/catalog/v2/moto_card_full_v2.dart';
import 'package:motogo_app/features/catalog/v2/moto_card_grid_v2.dart';

import '../support/fakes_catalog.dart';
import '../support/v2_harness.dart';

Widget _scaled(double scale, double width, Widget child) => Builder(
      builder: (c) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: SingleChildScrollView(
          child: Align(alignment: Alignment.topLeft, child: SizedBox(width: width, child: child)),
        ),
      ),
    );

/// Every paragraph under [of]: its longest word fits its width (no word
/// broken in half) and no line is cut.
void _expectWholeWords(WidgetTester t, Finder of) {
  final ps = find.descendant(of: of, matching: find.byType(RichText)).evaluate();
  expect(ps, isNotEmpty);
  for (final e in ps) {
    final p = e.renderObject! as RenderParagraph;
    final text = p.text.toPlainText();
    expect(p.getMinIntrinsicWidth(double.infinity), lessThanOrEqualTo(p.size.width + 0.5), reason: 'split: $text');
    expect(p.didExceedMaxLines, isFalse, reason: 'cut: $text');
  }
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerCatalogStrings();
  });

  testWidgets('spec tiles: 2 × 2 at 320 dp, 4 in a row at 412, never overflow', (t) async {
    for (final (w, lang, cols) in [(288.0, 'en', 2), (288.0, 'cs', 2), (380.0, 'en', 4)]) {
      await pumpV2(t, _scaled(1, w, DetailKeyTilesV2(moto: kBmw)), lang: lang, size: Size(w + 32, 780), reducedMotion: true);
      await t.pump(const Duration(milliseconds: 600));
      expect(t.takeException(), isNull, reason: '$lang $w');
      final tiles = find.descendant(of: find.byType(DetailKeyTilesV2), matching: find.byType(MgReveal));
      expect(tiles, findsNWidgets(4));
      final tops = {for (var i = 0; i < 4; i++) t.getRect(tiles.at(i)).top.round()};
      expect(tops.length, 4 ~/ cols, reason: '$lang $w');
      if (montserratLoaded) _expectWholeWords(t, find.byType(DetailKeyTilesV2));
    }
  });

  testWidgets('all parameters: a long caps label spans the full row', (t) async {
    const specs = [MapEntry('Rijbewijscategorie', 'A2'), MapEntry('Koppel', '62 Nm'), MapEntry('Gewicht', '199 kg')];
    await pumpV2(t, _scaled(1.3, 288, const DetailAllParamsV2(specs: specs)), lang: 'nl', size: const Size(320, 690));
    expect(t.takeException(), isNull);
    final first = find.ancestor(of: find.text('RIJBEWIJSCATEGORIE'), matching: find.byType(Container)).first;
    final second = find.ancestor(of: find.text('KOPPEL'), matching: find.byType(Container)).first;
    expect(t.getSize(first).width, 288);
    expect(t.getSize(second).width, lessThan(150));
    if (montserratLoaded) _expectWholeWords(t, find.byType(DetailAllParamsV2));
  });

  testWidgets('mode switch: icon above the title when a word would not fit beside it', (t) async {
    for (final (lang, scale, w) in [('uk', 1.0, 288.0), ('de', 1.3, 288.0), ('fr', 1.3, 328.0), ('cs', 1.0, 380.0)]) {
      await pumpV2(t, _scaled(scale, w, CatalogModeSwitchV2(mode: CatalogMode.find, onChanged: (_) {})),
          lang: lang, size: Size(w + 32, 780));
      await t.pump(const Duration(milliseconds: 400));
      expect(t.takeException(), isNull, reason: '$lang $scale');
      if (montserratLoaded) _expectWholeWords(t, find.byType(CatalogModeSwitchV2));
    }
  });

  testWidgets('grid card: a long availability badge wraps inside the card', (t) async {
    const price = CatCardPrice(label: 'od', value: '2 727 Kč', unit: '/den', sub: '', grid: 'od 2 727 Kč/den');
    for (final lang in ['de', 'pl', 'uk']) {
      await pumpV2(
        t,
        _scaled(1.3, 136, MotoCardGridV2(moto: kBmw, price: price, availability: 'Frei in deinem Zeitraum', onOpen: () {})),
        lang: lang,
        size: const Size(320, 690),
      );
      expect(t.takeException(), isNull);
      final card = t.getRect(find.byType(MotoCardGridV2));
      final badge = t.getRect(find.text('Frei in deinem Zeitraum'));
      expect(badge.right, lessThanOrEqualTo(card.right - 8 + 0.5));
      if (montserratLoaded) _expectWholeWords(t, find.text('Frei in deinem Zeitraum'));
    }
  });

  testWidgets('full card: grows instead of clipping, price and CTA stack when narrow', (t) async {
    const price = CatCardPrice(label: 'Cena od', value: '2 727 Kč', unit: '/Tag', sub: 'в середньому 630 Kč за день', grid: '');
    await pumpV2(
      t,
      _scaled(1.3, 320, MotoCardFullV2(moto: kBmw, price: price, availability: 'Вільний у твої дати', ctaLabel: 'Auswählen', onOpen: () {}, height: 497)),
      lang: 'uk',
      size: const Size(320, 690),
    );
    await t.pump(const Duration(milliseconds: 400));
    expect(t.takeException(), isNull);
    final card = t.getRect(find.byType(MotoCardFullV2));
    expect(card.height, greaterThanOrEqualTo(497));
    for (final e in find.descendant(of: find.byType(MotoCardFullV2), matching: find.byType(RichText)).evaluate()) {
      expect(t.getRect(find.byWidget(e.widget)).top, greaterThanOrEqualTo(card.top), reason: (e.widget as RichText).text.toPlainText());
    }
    if (montserratLoaded) _expectWholeWords(t, find.textContaining('2 727'));
  });

  testWidgets('trip card: caps eyebrows and the loyalty note keep whole words', (t) async {
    for (final lang in ['nl', 'de', 'uk', 'pl']) {
      await pumpV2(
        t,
        _scaled(
          1.3,
          288,
          DetailTripCardV2(
            moto: kBmw,
            selStart: null,
            selEnd: null,
            hasDates: false,
            dayCount: 0,
            listTotal: 0,
            quote: null,
            calendarExpanded: false,
            onToggleCalendar: () {},
            onRangeSelected: (_, __) {},
            onStartSelected: (_) {},
            onReset: () {},
            bookedAsync: const AsyncData([]),
          ),
        ),
        lang: lang,
        size: const Size(320, 690),
        overrides: catalogOverrides(loyaltyError: Exception('rpc')),
      );
      await t.pump(const Duration(milliseconds: 400));
      expect(t.takeException(), isNull, reason: lang);
      if (montserratLoaded) _expectWholeWords(t, find.byType(DetailTripCardV2));
    }
  });
}
