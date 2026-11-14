// pay_shop PS-07: the booking upsell in the v2 look after lookonly-fix —
// the old card (title, no fold) with the featured products one under
// another, all visible at once; the old tile's tap rules on the same
// provider; flag OFF keeps the old section.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/i18n/i18n_provider.dart';
import 'package:motogo_app/features/payment/booking_upsell_provider.dart';
import 'package:motogo_app/features/payment/v2/upsell_row_v2.dart';
import 'package:motogo_app/features/payment/widgets/upsell_section.dart';

import '../render/cases_ux_pay_shop.dart' show kPsProducts, psShopOverrides;
import '../support/ps_harness.dart';

Widget _host() => const Material(
      child: SingleChildScrollView(
        child: Padding(padding: EdgeInsets.all(16), child: UpsellSection(showProducts: true)),
      ),
    );

List<BookingUpsellItem> _items(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(UpsellSection))).read(bookingUpsellProvider);

void main() {
  testWidgets('flag ON: the old card, all products at once, no fold; flag OFF: the old section', (tester) async {
    await pumpPs(tester, _host(), overrides: psShopOverrides());
    await tester.pumpAndSettle();
    expect(find.byType(UpsellRowV2), findsOneWidget);
    expect(find.byKey(const ValueKey('upsell-v2-row')), findsNothing);
    for (final p in kPsProducts.take(3)) {
      expect(find.byKey(ValueKey('upsell-v2-${p.id}')), findsOneWidget);
    }
    // The title is not a fold: a tap keeps every product.
    await tester.tap(find.text(AppTranslations.of('cs').tr('recommendForBooking')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('upsell-v2-p3')), findsOneWidget);

    await pumpPs(tester, _host(), overrides: psShopOverrides(), v2: false);
    await tester.pumpAndSettle();
    expect(find.byType(UpsellRowV2), findsNothing);
  });

  testWidgets('same tap rules: Přidat adds / removes, a size chip replaces the size', (tester) async {
    await pumpPs(tester, _host(), overrides: psShopOverrides());
    await tester.pumpAndSettle();
    // p1 needs a size: no add chip, sizes instead.
    expect(find.byKey(const ValueKey('upsell-v2-toggle-p1')), findsNothing);
    await tester.tap(find.text('M'));
    await tester.pump();
    expect(_items(tester).map((i) => (i.id, i.size)), [('p1-M', 'M')]);
    await tester.tap(find.text('L'));
    await tester.pump();
    expect(_items(tester).map((i) => (i.id, i.size)), [('p1-L', 'L')]);
    await tester.tap(find.text('L'));
    await tester.pump();
    expect(_items(tester), isEmpty);

    // p2 has no size: the chip adds, the same chip removes.
    await tester.ensureVisible(find.byKey(const ValueKey('upsell-v2-toggle-p2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('upsell-v2-toggle-p2')));
    await tester.pumpAndSettle();
    expect(_items(tester).map((i) => (i.id, i.size)), [('p2', null)]);
    await tester.tap(find.byKey(const ValueKey('upsell-v2-toggle-p2')));
    await tester.pumpAndSettle();
    expect(_items(tester), isEmpty);
  });

  // lookonly-fix: no snapping row — the products are one under another as before.
}
