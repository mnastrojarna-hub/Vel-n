// pay_shop PS-08..12 / 20: e-shop in the v2 look — same routes, the
// product photo pager swipe, the inline size hint instead of the toast (no
// cart change), cart steppers / trash / empty through the same provider
// methods, voucher values reach the same purchase, the checkout field
// stays above the keyboard, the badge bumps.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/tokens/mg_format.dart';
import 'package:motogo_app/features/shop/cart_screen.dart';
import 'package:motogo_app/features/shop/product_detail_screen.dart';
import 'package:motogo_app/features/shop/shop_checkout_screen.dart';
import 'package:motogo_app/features/shop/shop_provider.dart';
import 'package:motogo_app/features/shop/shop_screen.dart';
import 'package:motogo_app/features/shop/v2/cart_view_v2.dart';
import 'package:motogo_app/features/shop/v2/product_card_v2.dart';
import 'package:motogo_app/features/shop/v2/shop_view_v2.dart';
import 'package:motogo_app/features/shop/voucher_screen.dart';

import '../render/cases_ux_pay_shop.dart' show kPsCart, psShopOverrides;
import '../support/fakes_booking.dart' show mockBookingPathProvider;
import '../support/ps_harness.dart';

ProviderContainer _c(WidgetTester t, Type screen) => ProviderScope.containerOf(t.element(find.byType(screen)));

void main() {
  setUpAll(mockBookingPathProvider);

  testWidgets('shop: card → /shop/:id, bag → /cart, voucher CTA → /voucher', (tester) async {
    await pumpPs(tester, const ShopScreen(), overrides: psShopOverrides());
    expect(find.byType(ShopViewV2), findsOneWidget);
    await tester.ensureVisible(find.byType(ProductCardV2).first);
    await tester.tap(find.byType(ProductCardV2).first);
    await tester.pumpAndSettle();
    expect(find.text('route:/shop/p1'), findsOneWidget);
    await pumpPs(tester, const ShopScreen(), overrides: psShopOverrides());
    await tester.tap(find.byKey(const ValueKey('shop-v2-bag')));
    await tester.pumpAndSettle();
    expect(find.text('route:/cart'), findsOneWidget);
    await pumpPs(tester, const ShopScreen(), overrides: psShopOverrides());
    await tester.tap(find.byKey(const ValueKey('shop-v2-voucher')));
    await tester.pumpAndSettle();
    expect(find.text('route:/voucher'), findsOneWidget);
  });

  testWidgets('product: swipe = next photo; add without size → inline hint, no cart change; with size → same add', (tester) async {
    await pumpPs(tester, const ProductDetailScreen(productId: 'p1'), overrides: psShopOverrides());
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(tester.widget<PageView>(find.byType(PageView)).controller?.page ?? 1, 1);

    await tester.tap(find.byKey(const ValueKey('shop-v2-add')));
    await tester.pump();
    expect(find.byKey(const ValueKey('shop-v2-size-hint')), findsOneWidget);
    expect(_c(tester, ProductDetailScreen).read(cartProvider), isEmpty);

    await tester.ensureVisible(find.text('L'));
    await tester.tap(find.text('L'));
    await tester.pump();
    expect(find.byKey(const ValueKey('shop-v2-size-hint')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('shop-v2-add')));
    await tester.pump();
    final cart = _c(tester, ProductDetailScreen).read(cartProvider);
    expect(cart.single.id, 'p1-L');
    expect(cart.single.qty, 1);
    expect(find.text('Do košíku'), findsOneWidget, reason: 'toast action to the cart');
  });

  testWidgets('cart: + / − / trash / Vyprázdnit act on the provider; empty = state with "Zpět do obchodu"', (tester) async {
    await pumpPs(tester, const CartScreen(), overrides: psShopOverrides(cart: kPsCart));
    expect(find.byType(CartViewV2), findsOneWidget);
    final c = _c(tester, CartScreen);
    await tester.tap(find.bySemanticsLabel('Přidat').first);
    await tester.pump();
    expect(c.read(cartProvider).first.qty, 2);
    await tester.tap(find.bySemanticsLabel('Ubrat').first);
    await tester.pump();
    expect(c.read(cartProvider).first.qty, 1);
    await tester.tap(find.bySemanticsLabel(RegExp('^Odebrat Dárkový')));
    await tester.pump();
    expect(c.read(cartProvider).length, 1);
    await tester.tap(find.byKey(const ValueKey('cart-v2-clear')));
    await tester.pump();
    expect(c.read(cartProvider), isEmpty);
    expect(find.text('Košík je prázdný'), findsOneWidget);
    await tester.tap(find.text('Zpět do obchodu'));
    await tester.pumpAndSettle();
    expect(find.text('route:/shop'), findsOneWidget);
  });

  testWidgets('voucher: 2 000 + printed reach the same purchase; custom < 100 locks the CTA', (tester) async {
    await pumpPs(tester, const VoucherScreen(), overrides: psShopOverrides());
    await tester.tap(find.text('${mgNum(2000, 'cs')}\u00A0Kč'));
    await tester.pump();
    await tester.tap(find.text('Tištěný'));
    await tester.pump();
    final c = _c(tester, VoucherScreen);
    await tester.tap(find.byKey(const ValueKey('voucher-v2-buy')));
    await tester.pumpAndSettle();
    final item = c.read(cartProvider).single;
    expect(item.price, 2000 + 180);
    expect(item.id, startsWith('voucher_2000_p_'));
    expect(find.text('route:/cart'), findsOneWidget);

    await pumpPs(tester, const VoucherScreen(), overrides: psShopOverrides());
    await tester.tap(find.text('Jiná'));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('voucher-v2-custom')), '50');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('voucher-v2-buy')), warnIfMissed: false);
    await tester.pump();
    expect(_c(tester, VoucherScreen).read(cartProvider), isEmpty);
  });

  testWidgets('checkout: the focused field is scrolled above the keyboard (page does not resize)', (tester) async {
    const kb = EdgeInsets.only(bottom: 320);
    final router = await pumpPs(tester, const ShopCheckoutScreen(), overrides: psShopOverrides(cart: kPsCart), viewInsets: kb);
    await tester.ensureVisible(find.byKey(const ValueKey('checkout-v2-promo-open')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('checkout-v2-promo-open')));
    await tester.pump();
    // Bring the field down below the keyboard line first (worst case).
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 600));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('checkout-v2-promo'));
    await tester.showKeyboard(field);
    await tester.pump();
    await tester.pumpAndSettle();
    final r = tester.getRect(field);
    expect(r.bottom, lessThanOrEqualTo(780 - kb.bottom));
    expect(r.top, greaterThanOrEqualTo(0));
    await psLeaveRoute(tester, router);
  });
}
