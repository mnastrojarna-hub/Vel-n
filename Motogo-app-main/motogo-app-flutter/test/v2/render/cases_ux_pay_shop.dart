// verify:render cases — pay_shop package (v2 on every page, 2026-11-07):
// payment page (new booking / surcharge / SOS / 15 Kč rounding), thank-you
// page (verified / missing documents / load failure), payment result (all
// tones), card sheet chrome, error sheet, leave dialog, payment methods,
// e-shop, product (+ size hint), cart (items / empty), checkout, voucher.
// MG_VERIFY_RENDER=1 flutter test test/v2/render/render_ux_pay_shop_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:motogo_app/core/feature_flags.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/widgets/pickup_location_link.dart';
import 'package:motogo_app/features/auth/auth_provider.dart';
import 'package:motogo_app/features/payment/payment_methods_screen.dart';
import 'package:motogo_app/features/payment/payment_provider.dart';
import 'package:motogo_app/features/payment/payment_result_screen.dart';
import 'package:motogo_app/features/payment/payment_screen.dart';
import 'package:motogo_app/features/payment/payment_ui_helpers.dart';
import 'package:motogo_app/features/payment/v2/card_sheet_v2.dart';
import 'package:motogo_app/features/payment/v2/confirmation_view_v2.dart';
import 'package:motogo_app/features/payment/widgets/payment_error_sheet.dart';
import 'package:motogo_app/features/shop/cart_screen.dart';
import 'package:motogo_app/features/shop/product_detail_screen.dart';
import 'package:motogo_app/features/shop/shop_checkout_screen.dart';
import 'package:motogo_app/features/shop/shop_models.dart';
import 'package:motogo_app/features/shop/shop_provider.dart';
import 'package:motogo_app/features/shop/shop_screen.dart';
import 'package:motogo_app/features/shop/voucher_screen.dart';

import '../support/fakes_booking.dart';
import 'render_harness.dart';

const kPsCards = [
  SavedCard(id: 'c1', stripeId: 'pm_1', brand: 'visa', last4: '4242', expMonth: 8, expYear: 2028, holderName: 'Jan Novák', isDefault: true),
  SavedCard(id: 'c2', stripeId: 'pm_2', brand: 'mastercard', last4: '5454', expMonth: 3, expYear: 2027, isDefault: false),
];

const kPsProducts = [
  Product(id: 'p1', name: 'Tričko MotoGo24', price: 590, color: 'bílé', material: '95 % polyester, 5 % elastan',
      description: 'Lehké funkční tričko s logem MotoGo24. Rychle schne, dobře dýchá a nemačká se. Hodí se pod bundu '
          'i na výlet. Praní na 30 °C, nesušit v sušičce.',
      images: ['https://motogo24.cz/shop/a.png', 'https://motogo24.cz/shop/b.png', 'https://motogo24.cz/shop/c.png'],
      sizes: ['S', 'M', 'L', 'XL'], stockQuantity: 5),
  Product(id: 'p2', name: 'Letní motorkářské rukavice', price: 490, images: ['x'], stockQuantity: 3),
  Product(id: 'p3', name: 'Truckerka MotoGo24', price: 490, images: ['x'], stockQuantity: 0),
  Product(id: 'p4', name: 'Kukla reflexní', price: 186, images: ['x'], stockQuantity: 9),
];

GoRouter Function() psRouter(Widget Function() screen) => () => GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => Scaffold(body: screen())),
    ]);

List<Override> psPayOverrides({PaymentContext? ctx, List<SavedCard> cards = kPsCards}) => [
      ...bookingOverrides(moto: kBmw, draft: bookingDraft(kBmw, pickupTime: '12:00')),
      paymentMethodsProvider.overrideWith((ref) async => cards),
      reservationUpsellEnabledProvider.overrideWith((ref) async => false),
      productsProvider.overrideWith((ref) async => kPsProducts),
      if (ctx != null) paymentContextProvider.overrideWith((ref) => ctx),
    ];

List<Override> psShopOverrides({List<CartItem> cart = const []}) => [
      productsProvider.overrideWith((ref) async => kPsProducts),
      cartProvider.overrideWith((ref) {
        final n = CartNotifier();
        for (final c in cart) {
          for (var i = 0; i < c.qty; i++) {
            n.addItem(c.id, c.name, c.price);
          }
        }
        return n;
      }),
      profileProvider.overrideWith((ref) async => kProfileOk),
      paymentMethodsProvider.overrideWith((ref) async => kPsCards),
    ];

final kPsCart = [
  CartItem(id: 'voucher_1000_d_1', name: 'Dárkový poukaz 1 000 Kč', price: 1000),
  CartItem(id: 'p1-L', name: 'Tričko MotoGo24 (L)', price: 590, qty: 2),
];

PaymentOutcome psOutcome(PaymentOutcomeKind kind) => PaymentOutcome(
      kind: kind,
      title: switch (kind) {
        PaymentOutcomeKind.success => 'Zaplaceno',
        PaymentOutcomeKind.pending => 'Platbu ověřujeme',
        PaymentOutcomeKind.attention => 'Zaplaceno, změna se dokončuje',
        PaymentOutcomeKind.failed => 'Platba neprošla',
      },
      subtitle: 'Banka ji ještě nepotvrdila. Většinou to trvá pár vteřin, někdy pár minut.',
      lines: const [PaymentOutcomeLine('💳', 'Doplatek za prodloužení: 3 408 Kč'), PaymentOutcomeLine('🧾', 'Doklad ti pošleme e-mailem')],
      nextStepNote: 'Potvrzení ti pošleme e-mailem.',
      ctaLabel: 'Moje rezervace',
      ctaRoute: '/reservations',
      pickup: kind == PaymentOutcomeKind.success
          ? const PickupInfo(branchId: 'b1', name: 'MotoGo24 Mezná', address: 'Mezná 9, 393 01 Pelhřimov')
          : null,
      verifyBookingId: kind == PaymentOutcomeKind.pending ? 'b-1' : null,
    );

Widget psConfirm({PayDocsV2 docs = PayDocsV2.verified, bool noDetails = false, bool failed = false}) => ConfirmationViewV2(
      restored: false,
      shortId: '#8F3A2C1D',
      motoName: 'BMW R 1200 GS Adventure',
      start: DateTime(DateTime.now().year, 10, 23),
      end: DateTime(DateTime.now().year, 10, 25),
      pickup: const PickupInfo(branchId: 'b1', name: 'MotoGo24 Mezná', address: 'Mezná 9, 393 01 Pelhřimov'),
      branchName: 'MotoGo24 Mezná',
      pickupTime: '12:00',
      returnTime: '19:00',
      lateGateDate: '23. 10. 2026',
      docs: docs,
      missingReason: docs == PayDocsV2.missing ? 'Chybí řidičský průkaz.' : null,
      noDetails: noDetails,
      loadFailed: failed,
      paidTotal: 10189,
      onRetry: () {},
      onClose: () {},
      onDocs: () {},
    );

Future<void> _openErrorSheet(WidgetTester t) async {
  PaymentErrorSheet.show(t.element(find.byType(Scaffold).first),
      title: 'Banka platbu zamítla',
      message: 'Přesný důvod nám banka nesdělila. Zaplať jinou kartou, nebo se zeptej své banky.',
      buttonLabel: 'Zaplatit jinou kartou',
      secondaryLabel: 'Zkusit znovu');
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
}

Future<void> _openLeave(WidgetTester t) async {
  confirmLeaveRunningPayment(t.element(find.byType(Scaffold).first));
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
}

Future<void> _tapAdd(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey('shop-v2-add')), warnIfMissed: false);
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _custom(WidgetTester w) async {
  final other = t(w.element(find.byType(VoucherScreen))).tr('other');
  await w.tap(find.text(other).last, warnIfMissed: false);
  await w.pump(const Duration(milliseconds: 400));
}

Widget _cardSheet({bool processing = false, String? note}) => Material(
      color: Colors.white,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: CardSheetV2(
          title: 'Zaplatit kartou',
          sub: '10 189 Kč · bezpečná platba přímo v aplikaci',
          processing: processing,
          onClose: () {},
          wallet: Container(height: 48, decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8))),
          dividerLabel: 'nebo zaplatit kartou',
          cardField: const Align(alignment: Alignment.centerLeft, child: Text('Číslo karty      MM / RR   CVC')),
          helper: 'Celý rámeček je klikací · vložení čísla funguje',
          payLabel: 'Zaplatit 10 189 Kč →',
          onPay: () {},
          note: note,
          noteIsStatus: processing,
        ),
      ),
    );

List<RenderCase> uxPayShopRenderCases() {
  final edit = PaymentContext(
      flowType: PaymentFlowType.extension, bookingId: '0000-1111-2222-8f3a2c1d', amount: 3408, label: 'Doplatek za prodloužení');
  final round = PaymentContext(
      flowType: PaymentFlowType.extension, bookingId: '0000-1111-2222-8f3a2c1d', amount: 7.5, label: 'Doplatek za úpravu');
  final sos = PaymentContext(
      flowType: PaymentFlowType.sos, amount: 4900, label: 'Náhradní motorka', sosDepositNote: 'Záloha je vratná po vyhodnocení škody.');
  return [
    RenderCase('pay', 'payment', 'new_booking', () => const PaymentScreen(), () => psPayOverrides(),
        router: psRouter(() => const PaymentScreen()), scaffold: false),
    RenderCase('pay', 'payment', 'edit_surcharge', () => const PaymentScreen(), () => psPayOverrides(ctx: edit),
        router: psRouter(() => const PaymentScreen()), scaffold: false),
    RenderCase('pay', 'payment', 'edit_round15', () => const PaymentScreen(), () => psPayOverrides(ctx: round),
        router: psRouter(() => const PaymentScreen()), scaffold: false),
    RenderCase('pay', 'payment', 'sos', () => const PaymentScreen(), () => psPayOverrides(ctx: sos, cards: const []),
        router: psRouter(() => const PaymentScreen()), scaffold: false),
    RenderCase('pay', 'success', 'verified', () => psConfirm(), () => const []),
    RenderCase('pay', 'success', 'docs_missing', () => psConfirm(docs: PayDocsV2.missing), () => const []),
    RenderCase('pay', 'success', 'load_fail', () => psConfirm(noDetails: true, failed: true, docs: PayDocsV2.unknown), () => const []),
    for (final k in PaymentOutcomeKind.values)
      RenderCase('pay', 'result', k.name, () => const PaymentResultScreen(), () => [
            paymentOutcomeProvider.overrideWith((ref) => psOutcome(k)),
          ], router: psRouter(() => const PaymentResultScreen()), scaffold: false, loading: k == PaymentOutcomeKind.pending),
    RenderCase('pay', 'card_sheet', 'idle', () => _cardSheet(), () => const [], scaffold: false),
    RenderCase('pay', 'card_sheet', 'processing', () => _cardSheet(processing: true, note: 'Platba probíhá, nezavírej aplikaci.'),
        () => const [], scaffold: false),
    RenderCase('pay', 'error_sheet', 'declined', () => const SizedBox.expand(), () => const [], after: _openErrorSheet),
    RenderCase('pay', 'leave_dialog', 'running', () => const SizedBox.expand(), () => const [], after: _openLeave),
    RenderCase('pay', 'methods', 'cards', () => const PaymentMethodsScreen(), () => psShopOverrides(),
        router: psRouter(() => const PaymentMethodsScreen()), scaffold: false),
    RenderCase('shop', 'shop', 'grid', () => const ShopScreen(), () => psShopOverrides(cart: kPsCart),
        router: psRouter(() => const ShopScreen()), scaffold: false),
    RenderCase('shop', 'product', 'sizes', () => const ProductDetailScreen(productId: 'p1'), () => psShopOverrides(),
        router: psRouter(() => const ProductDetailScreen(productId: 'p1')), scaffold: false),
    RenderCase('shop', 'product', 'size_hint', () => const ProductDetailScreen(productId: 'p1'), () => psShopOverrides(),
        router: psRouter(() => const ProductDetailScreen(productId: 'p1')), scaffold: false, after: _tapAdd),
    RenderCase('shop', 'cart', 'items', () => const CartScreen(), () => psShopOverrides(cart: kPsCart),
        router: psRouter(() => const CartScreen()), scaffold: false),
    RenderCase('shop', 'cart', 'empty', () => const CartScreen(), () => psShopOverrides(),
        router: psRouter(() => const CartScreen()), scaffold: false),
    RenderCase('shop', 'checkout', 'post', () => const ShopCheckoutScreen(), () => psShopOverrides(cart: kPsCart),
        router: psRouter(() => const ShopCheckoutScreen()), scaffold: false),
    RenderCase('shop', 'voucher', 'buy', () => const VoucherScreen(), () => psShopOverrides(),
        router: psRouter(() => const VoucherScreen()), scaffold: false),
    RenderCase('shop', 'voucher', 'custom', () => const VoucherScreen(), () => psShopOverrides(),
        router: psRouter(() => const VoucherScreen()), scaffold: false, after: _custom),
  ];
}
