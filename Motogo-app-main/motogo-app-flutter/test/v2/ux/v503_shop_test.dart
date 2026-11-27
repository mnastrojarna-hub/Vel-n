// 5.0.3 (owner 2026-11-27: e-shop "stejné, nebo minimálně podobné
// prohlížení, jako mají trasy anebo motorky, detaily motorek"): the v2 shop
// list is ONE PRODUCT PER SCREEN (the Motorky geometry and snap, "n / total",
// the arrow back to the top) and the product page has the bike detail's
// photo hero + sheet. Look only: the same routes, cart, voucher, states.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/v2/chrome/mg_page.dart';
import 'package:motogo_app/core/v2/gestures/mg_zone_snap.dart';
import 'package:motogo_app/core/v2/widgets/mg_back_v2.dart';
import 'package:motogo_app/core/v2/widgets/mg_cta.dart';
import 'package:motogo_app/features/catalog/v2/bike_screen_list_v2.dart' show kBikeScreenGap;
import 'package:motogo_app/features/shop/product_detail_screen.dart';
import 'package:motogo_app/features/shop/shop_models.dart';
import 'package:motogo_app/features/shop/shop_provider.dart';
import 'package:motogo_app/features/shop/shop_screen.dart';
import 'package:motogo_app/features/shop/v2/product_card_full_v2.dart';
import 'package:motogo_app/features/shop/v2/product_card_parts_v2.dart';
import 'package:motogo_app/features/shop/v2/product_hero_v2.dart';
import 'package:motogo_app/features/shop/v2/shop_voucher_hero_v2.dart';

import '../render/cases_ux_pay_shop.dart' show kPsCart, kPsProducts, psShopOverrides;
import '../support/bars_harness.dart';
import '../support/fakes_booking.dart' show mockBookingPathProvider;
import '../support/ps_harness.dart';
import '../support/v2_harness.dart' show kV2Langs, loadMontserrat;

final _shell = <String, Widget Function(GoRouterState)>{
  '/shop': (_) => const ShopScreen(),
  '/shop/:id': (s) => Scaffold(body: Text('route:/shop/${s.pathParameters['id']}')),
  '/cart': (_) => const Scaffold(body: Text('route:/cart')),
  '/profile': (_) => const Scaffold(body: Text('route:/profile')),
};

List<Override> _with(Future<List<Product>> Function() load) =>
    [...psShopOverrides(), productsProvider.overrideWith((ref) => load())];

ScrollPosition _pos(WidgetTester t) =>
    t.state<ScrollableState>(find.descendant(of: find.byType(ShopScreen), matching: find.byType(Scrollable)).first).position;

MgSnapZone _zone(WidgetTester t) =>
    t.renderObject<RenderMgSnapZone>(find.byType(MgSnapZoneSliver, skipOffstage: false)).zone;

Finder _card(String id) => find.byKey(ValueKey('shop-card-$id'));

double _arrow(WidgetTester t) => t
    .widget<AnimatedOpacity>(find.ancestor(of: find.byKey(const ValueKey('mg-to-top')), matching: find.byType(AnimatedOpacity)))
    .opacity;

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Pops the pushed destination: the list is back as it was left.
Future<void> _back(WidgetTester t, GoRouter router) async {
  router.pop();
  await t.pumpAndSettle();
}

Future<void> _drain(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 3));
}

void main() {
  setUpAll(() async {
    await loadMontserrat();
    mockBookingPathProvider();
  });

  testWidgets('in the shell: every product is the folded viewport tall (844 − 34), one per screen, as Motorky', (t) async {
    await pumpBarsShell(t, '/shop', _shell, overrides: psShopOverrides(cart: kPsCart));
    await t.pump(const Duration(milliseconds: 500));
    // Above the list: the header's bag and the voucher hero, as before.
    expect(find.byKey(const ValueKey('shop-v2-bag')), findsOneWidget);
    expect(find.byType(ShopVoucherHeroV2), findsOneWidget);
    final z = _zone(t);
    expect(z.active, isTrue);
    expect(z.count, kPsProducts.length);
    expect(z.extent, 844 - 34 + kBikeScreenGap);
    _pos(t).jumpTo(z.offsetOf(1) - 60);
    await t.pump();
    await slowDrag(t, find.byType(CustomScrollView), -60);
    await _settle(t);
    expect(navFolded(t), isTrue);
    expect(_pos(t).pixels, moreOrLessEquals(z.offsetOf(1), epsilon: 0.5));
    final r = t.getRect(_card('p2'));
    expect(r.top, moreOrLessEquals(0, epsilon: 0.5));
    expect(r.height, 844 - 34);
    // Top controls under the status-bar inset (47).
    final card = t.widget<ProductCardFullV2>(_card('p2'));
    expect(card.topInset, 47);
    expect(card.index, 1);
    expect(card.total, kPsProducts.length);
    expect(t.getRect(find.descendant(of: _card('p2'), matching: find.byType(MgV2Back))).top, greaterThanOrEqualTo(47));
    expect(find.descendant(of: _card('p2'), matching: find.text('2 / 4')), findsOneWidget);
    expect(find.bySemanticsLabel('Produkt 2 z 4'), findsOneWidget);
    expect(t.takeException(), isNull);
    await _drain(t);
  });

  for (final reduced in [false, true]) {
    testWidgets('snap (reduced=$reduced): a short drag returns, a long one moves ONE product, a hard flick never two',
        (t) async {
      await pumpBarsShell(t, '/shop', _shell, overrides: psShopOverrides(), reducedMotion: reduced);
      await t.pump(const Duration(milliseconds: 500));
      final z = _zone(t);
      final pos = _pos(t);
      expect(z.reduced, reduced);
      pos.jumpTo(z.offsetOf(0));
      await t.pump();
      await slowDrag(t, find.byType(CustomScrollView), -(z.extent * 0.3));
      await _settle(t);
      expect(pos.pixels, moreOrLessEquals(z.offsetOf(0), epsilon: 1), reason: '30 % → back to the same product');
      await slowDrag(t, find.byType(CustomScrollView), -(z.extent * 0.65));
      await _settle(t);
      expect(pos.pixels, moreOrLessEquals(z.offsetOf(1), epsilon: 1), reason: '65 % → the next product');
      await t.fling(find.byType(CustomScrollView), const Offset(0, -300), 4000);
      await _settle(t);
      expect(pos.pixels, moreOrLessEquals(z.offsetOf(2), epsilon: 1), reason: 'one swipe = one product');
      expect(t.takeException(), isNull);
      await _drain(t);
    });
  }

  testWidgets('arrow up: hidden on the first product, shown from the second, tap → the top; the caption rides above it',
      (t) async {
    await pumpBarsShell(t, '/shop', _shell, overrides: psShopOverrides());
    await t.pump(const Duration(milliseconds: 500));
    final z = _zone(t);
    _pos(t).jumpTo(z.offsetOf(0));
    await _settle(t);
    expect(_arrow(t), 0);
    expect(t.widget<ProductCardFullV2>(_card('p1')).liftExtra, 0);
    _pos(t).jumpTo(z.offsetOf(2));
    await _settle(t);
    expect(_arrow(t), 1);
    final arrow = t.getRect(find.byKey(const ValueKey('mg-to-top')));
    final cta = t.getRect(find.byKey(const ValueKey('shop-v2-open-p3')));
    expect(t.widget<ProductCardFullV2>(_card('p3')).liftExtra, greaterThan(0));
    expect(arrow.overlaps(cta), isFalse, reason: 'the arrow never covers "Detail"');
    await t.tap(find.byKey(const ValueKey('mg-to-top')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await _settle(t);
    expect(_pos(t).pixels, 0);
    expect(_arrow(t), 0);
    await _drain(t);
  });

  testWidgets('card: photo, name, description line, sizes, price, stock; every tap = the old card tap', (t) async {
    final router = await pumpPs(t, const ShopScreen(), overrides: psShopOverrides(cart: kPsCart));
    final z = _zone(t);
    _pos(t).jumpTo(z.offsetOf(0));
    await t.pump();
    final c = _card('p1');
    for (final s in ['Tričko MotoGo24', 'CENA', 'Skladem', 'Velikost', 'S', 'M', 'L', 'XL', '1 / 4']) {
      expect(find.descendant(of: c, matching: find.text(s)), findsOneWidget, reason: s);
    }
    expect(find.descendant(of: c, matching: find.textContaining('590')), findsOneWidget);
    expect(find.descendant(of: c, matching: find.textContaining('Lehké funkční tričko')), findsOneWidget);
    expect(find.descendant(of: c, matching: find.byType(MgCta)), findsOneWidget);
    // Photo → the product route.
    await t.tapAt(t.getRect(c).center - const Offset(0, 120));
    await t.pumpAndSettle();
    expect(find.text('route:/shop/p1'), findsOneWidget);
    // "DETAIL" → the same route.
    await _back(t, router);
    await t.tap(find.byKey(const ValueKey('shop-v2-open-p1')));
    await t.pumpAndSettle();
    expect(find.text('route:/shop/p1'), findsOneWidget);
    // Name / price block → the same route.
    await _back(t, router);
    await t.tap(find.descendant(of: _card('p1'), matching: find.text('Tričko MotoGo24')));
    await t.pumpAndSettle();
    expect(find.text('route:/shop/p1'), findsOneWidget);
    await _back(t, router);
    expect(_pos(t).pixels, _zone(t).offsetOf(0), reason: 'Back lands on the product that was opened');
  });

  testWidgets('card top row: the cart (with the badge) and back are the screen\'s own actions', (t) async {
    final router = await pumpPs(t, const ShopScreen(), overrides: psShopOverrides(cart: kPsCart));
    _pos(t).jumpTo(_zone(t).offsetOf(1));
    await t.pump();
    final bag = find.byKey(const ValueKey('shop-v2-card-bag-p2'));
    expect(find.descendant(of: bag, matching: find.text('3')), findsOneWidget, reason: 'kPsCart = 1 + 2 pieces');
    await t.tap(bag);
    await t.pumpAndSettle();
    expect(find.text('route:/cart'), findsOneWidget);
    await _back(t, router);
    await t.tap(find.descendant(of: _card('p2'), matching: find.byType(MgV2Back)));
    await t.pumpAndSettle();
    expect(find.text('route:/profile'), findsOneWidget, reason: 'context.backOr(Routes.profile), as the header back');
  });

  testWidgets('photos: several = a sideways pager (one per swipe, tap zones, segments); one photo = no pager',
      (t) async {
    await pumpPs(t, const ShopScreen(), overrides: psShopOverrides());
    _pos(t).jumpTo(_zone(t).offsetOf(0));
    await t.pump();
    final pager = find.descendant(of: _card('p1'), matching: find.byType(PageView));
    expect(pager, findsOneWidget);
    final segs = find.descendant(of: _card('p1'), matching: find.byType(ShopPhotoSegmentsV2));
    expect(t.widget<ShopPhotoSegmentsV2>(segs).count, 3);
    expect(t.widget<ShopPhotoSegmentsV2>(segs).index, 0);
    await t.fling(pager, const Offset(-300, 0), 3000);
    await t.pumpAndSettle();
    expect(t.widget<ShopPhotoSegmentsV2>(segs).index, 1, reason: 'a hard flick = one photo');
    await t.tap(find.descendant(of: _card('p1'), matching: find.bySemanticsLabel('Další fotka')));
    await t.pumpAndSettle();
    expect(t.widget<ShopPhotoSegmentsV2>(segs).index, 2);
    await t.tap(find.descendant(of: _card('p1'), matching: find.bySemanticsLabel('Předchozí fotka')));
    await t.pumpAndSettle();
    expect(t.widget<ShopPhotoSegmentsV2>(segs).index, 1);
    // The page did not move sideways-swiping.
    expect(_pos(t).pixels, _zone(t).offsetOf(0));
    _pos(t).jumpTo(_zone(t).offsetOf(1));
    await t.pump();
    expect(find.descendant(of: _card('p2'), matching: find.byType(PageView)), findsNothing);
    expect(find.descendant(of: _card('p2'), matching: find.byType(ShopPhotoSegmentsV2)), findsNothing);
  });

  testWidgets('sold out: the red tag + "Vyprodáno" under the price, still opens the product', (t) async {
    await pumpPs(t, const ShopScreen(), overrides: psShopOverrides());
    _pos(t).jumpTo(_zone(t).offsetOf(2));
    await t.pump();
    final c = _card('p3');
    expect(find.descendant(of: c, matching: find.text('VYPRODÁNO')), findsOneWidget);
    expect(find.descendant(of: c, matching: find.text('Vyprodáno')), findsOneWidget);
    expect(find.descendant(of: c, matching: find.text('Skladem')), findsNothing);
    expect(find.descendant(of: c, matching: find.text('Velikost')), findsNothing, reason: 'no sizes in the model');
    await t.tap(find.byKey(const ValueKey('shop-v2-open-p3')));
    await t.pumpAndSettle();
    expect(find.text('route:/shop/p3'), findsOneWidget);
  });

  testWidgets('0 products = the empty state, 1 product = one card without "1 / 1", error = retry, loading = skeleton',
      (t) async {
    await pumpPs(t, const ShopScreen(), overrides: _with(() async => const []));
    expect(find.text('Zatím žádné produkty'), findsOneWidget);
    expect(find.byType(ProductCardFullV2, skipOffstage: false), findsNothing);
    expect(find.byType(MgSnapZoneSliver, skipOffstage: false), findsNothing);
    expect(find.byType(ShopVoucherHeroV2), findsOneWidget);

    await pumpPs(t, const ShopScreen(), overrides: _with(() async => [kPsProducts[1]]));
    expect(_zone(t).count, 1);
    _pos(t).jumpTo(_zone(t).offsetOf(0));
    await t.pump();
    expect(find.byType(ProductCardFullV2), findsOneWidget);
    expect(find.byType(ShopPosPillV2), findsNothing);
    expect(t.takeException(), isNull);

    var loads = 0;
    await pumpPs(t, const ShopScreen(), overrides: _with(() async {
      loads++;
      if (loads == 1) throw Exception('SocketException: offline');
      return kPsProducts;
    }));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Nabídku obchodu se nepodařilo načíst'), findsOneWidget);
    expect(find.byType(ProductCardFullV2, skipOffstage: false), findsNothing);
    await t.ensureVisible(find.text('Zkusit znovu'));
    await t.tap(find.text('Zkusit znovu'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(loads, 2);
    expect(_zone(t).count, kPsProducts.length);

    await pumpPs(t, const ShopScreen(),
        overrides: _with(() => Future<List<Product>>.delayed(const Duration(seconds: 30), () => kPsProducts)));
    expect(find.byType(ShopListSkeletonV2, skipOffstage: false), findsOneWidget);
    expect(find.byType(ProductCardFullV2, skipOffstage: false), findsNothing);
    await t.pump(const Duration(seconds: 31));
    expect(find.byType(ShopListSkeletonV2, skipOffstage: false), findsNothing);
    expect(_zone(t).count, kPsProducts.length);
  });

  for (final size in const [Size(320, 640), Size(360, 780)]) {
    for (final scale in const [1.0, 1.3]) {
      testWidgets('fit ${size.width.toInt()}×${size.height.toInt()} text ×$scale: list + product page, 8 languages',
          (t) async {
        for (final lang in kV2Langs) {
          for (final reduced in [true, false]) {
            await pumpPs(t, const ShopScreen(),
                overrides: psShopOverrides(cart: kPsCart), size: size, lang: lang, textScale: scale, reducedMotion: reduced);
            for (var i = 0; i < kPsProducts.length; i++) {
              _pos(t).jumpTo(_zone(t).offsetOf(i));
              await t.pump();
              await t.pump(const Duration(milliseconds: 700));
              expect(t.takeException(), isNull, reason: 'list $lang product $i');
              final r = t.getRect(_card(kPsProducts[i].id));
              expect(r.height, greaterThanOrEqualTo(size.height));
              // The caption (name … CTA) and the top row never leave the card.
              final cta = t.getRect(find.byKey(ValueKey('shop-v2-open-${kPsProducts[i].id}')));
              expect(cta.bottom, lessThanOrEqualTo(r.bottom), reason: '$lang $i');
              expect(cta.left, greaterThanOrEqualTo(0));
              expect(cta.right, lessThanOrEqualTo(size.width));
              final back = t.getRect(find.descendant(of: _card(kPsProducts[i].id), matching: find.byType(MgV2Back)));
              final name = t.getRect(find.descendant(of: _card(kPsProducts[i].id), matching: find.text(kPsProducts[i].name)));
              expect(name.top, greaterThan(back.bottom), reason: 'the name never climbs over the top row ($lang $i)');
            }
          }
          for (final id in ['p1', 'p3']) {
            await pumpPs(t, ProductDetailScreen(productId: id),
                overrides: psShopOverrides(), size: size, lang: lang, textScale: scale);
            await t.pump(const Duration(milliseconds: 300));
            expect(t.takeException(), isNull, reason: 'product $id $lang');
            await t.drag(find.byType(CustomScrollView), const Offset(0, -500));
            await t.pump(const Duration(milliseconds: 300));
            expect(t.takeException(), isNull, reason: 'product $id $lang scrolled');
          }
        }
      });
    }
  }

  testWidgets('product page: the bike detail\'s photo hero (back, stock, photo counter) + sheet; pinned back', (t) async {
    final router = await pumpPs(t, const ProductDetailScreen(productId: 'p1'), overrides: psShopOverrides());
    final hero = find.byType(ProductHeroV2);
    expect(hero, findsOneWidget);
    final hr = t.getRect(hero);
    expect(hr.top, 0);
    expect(hr.width, 360);
    expect(hr.height, t.widget<ProductHeroV2>(hero).height);
    expect(hr.height, 360 + ProductHeroV2.sheetOverlap, reason: 'a square photo fills the width');
    expect(find.descendant(of: hero, matching: find.text('Skladem')), findsOneWidget);
    expect(find.descendant(of: hero, matching: find.text('1 / 3')), findsOneWidget);
    expect(find.bySemanticsLabel('Fotka 1 z 3'), findsOneWidget);
    // Name and price open the white sheet over the hero's foot.
    final name = t.getRect(find.text('Tričko MotoGo24'));
    expect(name.top, greaterThan(hr.bottom - ProductHeroV2.sheetOverlap));
    expect(t.getRect(find.textContaining('590').first).top, greaterThan(name.top));
    // Swipe = next photo (one per swipe) → the counter follows.
    await t.fling(find.byType(PageView), const Offset(-300, 0), 3000);
    await t.pumpAndSettle();
    expect(find.descendant(of: hero, matching: find.text('2 / 3')), findsOneWidget);
    expect(t.widget<ShopPhotoSegmentsV2>(find.byType(ShopPhotoSegmentsV2)).index, 1);
    // The hero scrolled away → the pinned back with the product name.
    await t.drag(find.byType(CustomScrollView), const Offset(0, -420));
    await t.pumpAndSettle();
    expect(find.byType(MgPinnedBack), findsOneWidget);
    await t.drag(find.byType(CustomScrollView), const Offset(0, 420));
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: hero, matching: find.byType(MgV2Back)));
    await t.pumpAndSettle();
    expect(find.text('route:/shop'), findsOneWidget, reason: 'context.backOr(Routes.shop), as before');
    expect(psPath(router), '/shop');
  });

  testWidgets('product page, sold out: "Vyprodáno" in the hero and the banner, no dock; one photo = no pager',
      (t) async {
    await pumpPs(t, const ProductDetailScreen(productId: 'p3'), overrides: psShopOverrides());
    final hero = find.byType(ProductHeroV2);
    expect(find.descendant(of: hero, matching: find.text('Vyprodáno')), findsOneWidget);
    expect(find.text('Vyprodáno'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('shop-v2-add')), findsNothing);
    expect(find.byType(PageView), findsNothing);
    expect(find.byType(ShopPhotoSegmentsV2), findsNothing);
    expect(t.takeException(), isNull);
  });
}
