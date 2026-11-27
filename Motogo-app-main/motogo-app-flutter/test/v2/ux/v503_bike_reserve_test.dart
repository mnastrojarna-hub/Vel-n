// 5.0.3 (owner 2026-11-27: "když procházím motorky, je tam tlačítko Detail,
// ale mohlo by tam být rovnou tlačítko Rezervovat … Rezervovat po mně bude
// chtít hned vybrat termín v kalendáři"): the bike list card has "Detail"
// AND "Rezervovat". Rezervovat without dates opens the REAL detail on its
// date step (the dock's own "VYBRAT TERMÍN" action, run once); both buttons
// fit 320 px in 8 languages. (Routing with / without dates and the busy
// rule: screens/catalog_card_book_test.dart.)
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/calendar/trip_calendar.dart';
import 'package:motogo_app/core/v2/gestures/mg_zone_snap.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/catalog/moto_detail_screen.dart';
import 'package:motogo_app/features/catalog/v2/bike_card_reserve_v2.dart';
import 'package:motogo_app/features/catalog/v2/bike_screen_card_parts_v2.dart';
import 'package:motogo_app/features/catalog/v2/bike_screen_list_v2.dart';
import 'package:motogo_app/features/catalog/v2/catalog_price.dart';
import 'package:motogo_app/features/catalog/v2/detail/detail_trip_card_v2.dart';
import 'package:motogo_app/features/catalog/v2/detail/moto_detail_view_v2.dart';
import 'package:motogo_app/features/catalog/v2/moto_card_full_v2.dart';
import 'package:motogo_app/features/catalog/v2/motorky_screen_v2.dart';
import 'package:motogo_app/features/home/v2/home_screen_v2.dart';

import '../screens/home_test.dart' show homeCases;
import '../support/bars_harness.dart';
import '../support/fakes_catalog.dart';
import '../support/v2_harness.dart';

final _routes = <String, Widget Function(GoRouterState)>{
  '/search': (_) => const MotorkyScreenV2(),
  '/moto/:id': (s) => MotoDetailScreen(motoId: s.pathParameters['id']!),
};

ScrollPosition _page(WidgetTester t) => t
    .state<ScrollableState>(find.descendant(of: find.byType(MotorkyScreenV2), matching: find.byType(Scrollable)).first)
    .position;

MgSnapZone _zone(WidgetTester t) =>
    t.renderObject<RenderMgSnapZone>(find.byType(MgSnapZoneSliver, skipOffstage: false)).zone;

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 14; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _drain(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 3));
}

/// Every paragraph under [of]: no word broken in half, no line cut.
void _expectWholeWords(WidgetTester t, Finder of, String why) {
  for (final e in find.descendant(of: of, matching: find.byType(RichText)).evaluate()) {
    final p = e.renderObject! as RenderParagraph;
    final text = p.text.toPlainText();
    expect(p.getMinIntrinsicWidth(double.infinity), lessThanOrEqualTo(p.size.width + 0.5), reason: 'split: $text ($why)');
    expect(p.didExceedMaxLines, isFalse, reason: 'cut: $text ($why)');
  }
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerCatalogStrings();
  });

  for (final viaReserve in [true, false]) {
    testWidgets(
        'no dates, real detail: ${viaReserve ? '"Rezervovat" opens it ON the date step (calendar in view)' : '"Detail" opens it at the top, as before'}',
        (t) async {
      await pumpBarsShell(t, '/search', _routes, reducedMotion: true);
      await t.pump(const Duration(milliseconds: 500));
      final ids = t.widget<BikeScreenList>(find.byType(BikeScreenList, skipOffstage: false)).ids;
      _page(t).jumpTo(_zone(t).offsetOf(0));
      await t.pump();
      final card = find.byKey(ValueKey('mc-${ids.first}'));
      final c = ProviderScope.containerOf(t.element(card));
      await t.tap(find.descendant(
          of: card, matching: find.byKey(ValueKey(viaReserve ? 'bike-card-reserve' : 'bike-card-detail'))));
      await t.pump();
      await _settle(t);
      final view = find.byType(MotoDetailV2View);
      expect(view, findsOneWidget);
      expect(t.widget<MotoDetailV2View>(view).moto.id, ids.first);
      expect(t.widget<MotoDetailV2View>(view).pickDatesOnOpen, viaReserve);
      // The request is used once: a later open of the same bike is plain.
      expect(c.read(detailPickDatesRequestProvider), isNull);
      final scroll =
          t.state<ScrollableState>(find.descendant(of: view, matching: find.byType(Scrollable)).first).position;
      final trip = find.byType(DetailTripCardV2);
      if (viaReserve) {
        expect(scroll.pixels, greaterThan(100), reason: 'scrolled down to "Tvoje jízda"');
        final r = t.getRect(trip);
        expect(r.top, greaterThanOrEqualTo(0));
        expect(r.top, lessThan(844 * 0.4), reason: 'the date step is at the top of the screen');
        expect(find.descendant(of: trip, matching: find.byType(TripCalendar)), findsOneWidget);
      } else {
        expect(scroll.pixels, 0);
      }
      // Same dock either way: no dates → "VYBRAT TERMÍN", never a booking.
      final dock = find.byWidgetPredicate((w) => w is MgCta && w.label == 'Vybrat termín');
      expect(dock, findsOneWidget);
      expect(t.takeException(), isNull);
      await _drain(t);
    });
  }

  testWidgets('Domů list: the same card with "Detail" + "Rezervovat"', (t) async {
    await pumpBarsShell(t, '/', {'/': (_) => const HomeScreenV2(), ..._routes}, overrides: homeCases()['s0']!());
    await t.pump(const Duration(milliseconds: 500));
    final pos = t
        .state<ScrollableState>(find.descendant(of: find.byType(HomeScreenV2), matching: find.byType(Scrollable)).first)
        .position;
    pos.jumpTo(_zone(t).offsetOf(0));
    await _settle(t);
    final card = find.byType(MotoCardFullV2).first;
    expect(find.descendant(of: card, matching: find.byKey(const ValueKey('bike-card-detail'))), findsOneWidget);
    expect(find.descendant(of: card, matching: find.byKey(const ValueKey('bike-card-reserve'))), findsOneWidget);
    expect(t.widget<MotoCardFullV2>(card).onReserve, isNotNull);
    await _drain(t);
  });

  for (final width in const [320.0, 360.0]) {
    for (final scale in const [1.0, 1.3]) {
      testWidgets('both buttons fit ${width.toInt()} px, text ×$scale, 8 languages — whole words, no overflow', (t) async {
        for (final lang in kV2Langs) {
          final tr = AppTranslations.of(lang);
          const price = CatCardPrice(label: 'Cena od', value: '12 727 Kč', unit: '/den', sub: 'průměrně 2 630 Kč za den', grid: '');
          await pumpV2(
            t,
            Builder(
              builder: (c) => MediaQuery(
                data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
                child: SingleChildScrollView(
                  child: MotoCardFullV2(
                    moto: kBmw,
                    price: price,
                    availability: null,
                    ctaLabel: tr.tr('motoCardDetail'),
                    reserveLabel: tr.tr('v2CatCtaBook'),
                    onReserve: () {},
                    onOpen: () {},
                    height: 640,
                  ),
                ),
              ),
            ),
            lang: lang,
            size: Size(width, 780),
            reducedMotion: true,
          );
          await t.pump(const Duration(milliseconds: 400));
          expect(t.takeException(), isNull, reason: '$lang $width ×$scale');
          final foot = find.byType(BikeCardFoot);
          final d = t.getRect(find.byKey(const ValueKey('bike-card-detail')));
          final r = t.getRect(find.byKey(const ValueKey('bike-card-reserve')));
          for (final b in [d, r]) {
            expect(b.left, greaterThanOrEqualTo(16 - 0.5), reason: '$lang $width ×$scale');
            expect(b.right, lessThanOrEqualTo(width - 16 + 0.5), reason: '$lang $width ×$scale');
            expect(b.height, greaterThanOrEqualTo(48));
          }
          expect(d.overlaps(r), isFalse, reason: lang);
          if (montserratLoaded) _expectWholeWords(t, foot, '$lang $width ×$scale');
          // Plain text size: always one row, Rezervovat the wider one.
          if (scale == 1.0) {
            expect((d.center.dy - r.center.dy).abs(), lessThan(1), reason: '$lang $width one row');
            expect(r.width, greaterThanOrEqualTo(d.width), reason: '$lang $width');
          }
        }
      });
    }
  }

  testWidgets('one action (no onReserve): the card is as before — price and the rank CTA side by side', (t) async {
    const price = CatCardPrice(label: 'Cena od', value: '2 727 Kč', unit: '/den', sub: 'x', grid: '');
    await pumpV2(
        t,
        SingleChildScrollView(
            child: MotoCardFullV2(moto: kBmw, price: price, availability: null, ctaLabel: 'DETAIL', onOpen: () {}, height: 640)),
        reducedMotion: true);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('bike-card-detail')), findsNothing);
    expect(find.byKey(const ValueKey('bike-card-reserve')), findsNothing);
    final cta = find.byType(MgCta);
    expect(t.widget<MgCta>(cta).label, 'DETAIL');
    final p = t.getRect(find.textContaining('2 727'));
    expect(t.getRect(cta).left, greaterThan(p.right), reason: 'the button beside the price');
  });
}
