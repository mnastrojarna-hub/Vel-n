// pay_shop PS-07: the booking upsell in the v2 look — collapsed card, a
// product row that snaps to whole cards (24 px peek), the old tile's tap
// rules on the same provider; flag OFF keeps the old section.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

ScrollPosition _rowPos(WidgetTester t) =>
    t.state<ScrollableState>(find.descendant(of: find.byKey(const ValueKey('upsell-v2-row')), matching: find.byType(Scrollable))).position;

void main() {
  testWidgets('flag ON: collapsed card; one tap opens the row; flag OFF: the old section', (tester) async {
    await pumpPs(tester, _host(), overrides: psShopOverrides());
    await tester.pumpAndSettle();
    expect(find.byType(UpsellRowV2), findsOneWidget);
    expect(find.byKey(const ValueKey('upsell-v2-row')), findsNothing);
    await tester.tap(find.text('Doporučujeme k rezervaci'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('upsell-v2-row')), findsOneWidget);

    await pumpPs(tester, _host(), overrides: psShopOverrides(), v2: false);
    await tester.pumpAndSettle();
    expect(find.byType(UpsellRowV2), findsNothing);
  });

  testWidgets('same tap rules: Přidat adds / removes, a size chip replaces the size', (tester) async {
    await pumpPs(tester, _host(), overrides: psShopOverrides());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Doporučujeme k rezervaci'));
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

  testWidgets('swipe snaps to whole cards; a fling moves one card; something chosen = open', (tester) async {
    await pumpPs(tester, _host(), overrides: psShopOverrides(), reducedMotion: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Doporučujeme k rezervaci'));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('upsell-v2-row'));
    final card = tester.getSize(find.descendant(of: row, matching: find.byType(SizedBox)).first).width;
    final extent = card + 12;
    // One whole card + 12 gap + 24 px peek of the next.
    expect(card, closeTo(tester.getSize(row).width - 24 - 12, 0.5));
    await tester.drag(row, const Offset(-60, 0));
    await tester.pumpAndSettle();
    expect(_rowPos(tester).pixels % extent, closeTo(0, 0.5));
    await tester.fling(row, const Offset(-80, 0), 900);
    await tester.pumpAndSettle();
    expect(_rowPos(tester).pixels, closeTo(extent, 0.5));

    // Something already chosen → the card starts open.
    await pumpPs(
        tester,
        Material(
          child: UpsellRowV2(
            products: kPsProducts.take(3).toList(),
            isSelected: (id) => id == 'p2',
            sizeOf: (_) => null,
            onToggle: (_, __) {},
            onRemove: (_) {},
          ),
        ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('upsell-v2-row')), findsOneWidget);
  });
}
