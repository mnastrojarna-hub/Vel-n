// pay_shop fit: the texts this package added or changed (upsell card,
// card sheet with the neon amount, cart empty state per Stavy 13.1,
// product quantity row, voucher amount segments, payment card holder) in
// all 8 languages × 320 / 360 / 412 dp × text 1.0 / 1.3 (reduced motion):
// no overflow, no cut / clipped UI text and no word broken in half
// (render_inspect.dart, the verify:render rules).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/currency.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/core/v2/motion/mg_motion.dart';
import 'package:motogo_app/features/payment/v2/card_sheet_v2.dart';
import 'package:motogo_app/features/payment/v2/card_visual_v2.dart';
import 'package:motogo_app/features/payment/v2/upsell_row_v2.dart';
import 'package:motogo_app/features/shop/v2/cart_view_v2.dart';
import 'package:motogo_app/features/shop/v2/product_view_v2.dart';
import 'package:motogo_app/features/shop/v2/voucher_view_v2.dart';

import '../render/cases_ux_pay_shop.dart' show kPsCards, kPsProducts;
import '../render/render_harness.dart' show loadRenderFonts;
import '../render/render_inspect.dart';
import '../support/v2_harness.dart';

const _widths = [320.0, 360.0, 412.0];
const _scales = [1.0, 1.3];

Widget _scaled(double scale, Widget child) => Builder(
      builder: (c) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child),
    );

Future<List<String>> _sweep(WidgetTester t, Widget Function() build, {double height = 1400}) async {
  final fails = <String>[];
  for (final lang in kV2Langs) {
    for (final w in _widths) {
      for (final s in _scales) {
        MgMotion.resetSession();
        final size = Size(w, height);
        await pumpV2(t, _scaled(s, build()), lang: lang, size: size, reducedMotion: true);
        await t.pump(const Duration(milliseconds: 400));
        final id = '$lang ${w.toInt()} ×$s';
        final e = t.takeException();
        if (e != null) fails.add('$id exception: ${'$e'.split('\n').first}');
        for (final f in inspectFrame(t.binding.renderViews.first, lang, size)) {
          if (f.fail) fails.add('$id ${f.kind}: ${f.text} (${f.detail})');
        }
      }
    }
  }
  await t.pumpWidget(const SizedBox());
  return fails;
}

class _CardSheet extends StatelessWidget {
  const _CardSheet();
  @override
  Widget build(BuildContext context) {
    final tt = t(context);
    final amount = Money.czk(10189);
    return Align(
      alignment: Alignment.bottomCenter,
      child: CardSheetV2(
        title: tt.tr('payByCardTitle'),
        sub: tt.trArgs('v2UxPsCardSheetSub', {'amount': amount}),
        processing: false,
        onClose: () {},
        dividerLabel: tt.tr('orPayByCardDivider'),
        cardField: const SizedBox(height: 40),
        helper: tt.tr('v2UxPsCardHelper'),
        payLabel: '${tt.tr('payBtn')} $amount →',
        payAmount: amount,
        onPay: () {},
      ),
    );
  }
}

void main() {
  setUpAll(loadRenderFonts);

  testWidgets('upsell card (open) + card sheet + payment cards keep whole words', (t) async {
    if (!montserratLoaded) return markTestSkipped('no Montserrat');
    final fails = <String>[
      ...await _sweep(
          t,
          () => SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  UpsellRowV2(
                    products: kPsProducts.take(3).toList(),
                    isSelected: (id) => id == 'p2',
                    sizeOf: (_) => null,
                    onToggle: (_, __) {},
                    onRemove: (_) {},
                  ),
                  const SizedBox(height: 16),
                  for (final c in kPsCards) ...[
                    SavedCardV2(card: c, onDelete: () {}, onSetDefault: c.isDefault ? null : () {}),
                    const SizedBox(height: 12),
                  ],
                ]),
              )),
      ...await _sweep(t, () => const _CardSheet(), height: 900),
    ];
    expect(fails, isEmpty, reason: fails.take(20).join('\n'));
  });

  testWidgets('cart empty (Stavy 13.1), product quantity row, voucher segments keep whole words', (t) async {
    if (!montserratLoaded) return markTestSkipped('no Montserrat');
    final ctrl = TextEditingController();
    addTearDown(ctrl.dispose);
    final fails = <String>[
      ...await _sweep(
          t,
          () => CartViewV2(
              items: const [], count: 0, subtotal: 0, digitalOnly: true, shippingLabel: '', shipping: 0,
              discount: 0, total: 0, onPlus: (_) {}, onMinus: (_) {}, onRemove: (_) {}, onClear: () {},
              onCheckout: () {}, onShop: () {}, onBack: () {}),
          height: 780),
      ...await _sweep(
          t,
          () => ProductViewV2(
              product: kPsProducts.first, imageIndex: 0, onPage: (_) {}, selectedSize: null, onSize: (_) {},
              sizeHint: true, qty: 2, onMinus: () {}, onPlus: () {}, onAdd: () {}, onBack: () {}),
          height: 1600),
      ...await _sweep(
          t,
          () => VoucherViewV2(
              amount: 1000, customMode: false, printed: false, total: 1000, customCtrl: ctrl, onPreset: (_) {},
              onCustom: () {}, onCustomChanged: (_) {}, onNormalize: () {}, onPrinted: (_) {}, onBuy: () {},
              onBack: () {}),
          height: 1400),
    ];
    expect(fails, isEmpty, reason: fails.take(20).join('\n'));
  });
}
