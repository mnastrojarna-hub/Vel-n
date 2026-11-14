// Safeguards G-267 / G-268 (new look): the price card before paying shows
// the gear sizes, the delivery km detail and the "rank discount only in the
// app" note like the old PriceSummaryCard, and the big total includes the
// bundled e-shop add-ons (= the real charge), in one card.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/core/v2/widgets/mg_price.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/v2/booking_v2_parts.dart' show bkMoney;
import 'package:motogo_app/features/payment/booking_upsell_provider.dart';
import 'package:motogo_app/features/payment/v2/pay_receipt_v2.dart';

import '../support/fakes_booking.dart';
import '../support/v2_harness.dart';

void main() {
  setUpAll(() async {
    await loadMontserrat();
    registerCatalogStrings();
    registerBookingStrings();
  });

  testWidgets('sizes, km detail, loyalty note and total incl. add-ons (G-267/G-268)', (t) async {
    const bd = PriceBreakdown(
      basePrice: 8000,
      extrasTotal: 300,
      pickupDeliveryFee: 1400, // 1000 + 10 km × 40
      returnDeliveryFee: 0,
      discountTotal: 0,
      total: 9000,
      days: 2,
      loyaltyDiscount: 700,
      loyaltyPercent: 7,
      loyaltyLevel: 3,
      loyaltyRankName: 'Jezdec',
    );
    final extras = [SelectedExtra(id: 'extra-boty-ridic', name: 'Boty řidiče', price: 300, size: '43')];
    const upsell = [BookingUpsellItem(id: 'p1', name: 'Kšiltovka MotoGo', price: 450)];
    await pumpV2(
      t,
      SingleChildScrollView(
        child: PayBreakdownV2(draft: BookingDraft(), breakdown: bd, extras: extras, upsell: upsell),
      ),
      size: const Size(412, 2000),
    );
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('(vel. 43)'), findsOneWidget, reason: 'gear size suffix');
    expect(find.textContaining('10 km × 40 + 1 000'), findsOneWidget, reason: 'delivery km detail');
    expect(find.text('Platí jen pro rezervace vytvořené v aplikaci'), findsOneWidget, reason: 'loyaltyAppOnly note');
    expect(find.text('Kšiltovka MotoGo'), findsOneWidget);
    final box = find.byType(MgTotalBox);
    expect(box, findsOneWidget, reason: 'one total, no second summary card');
    expect(find.descendant(of: box, matching: find.text(bkMoney(9450))), findsOneWidget,
        reason: 'the big total = booking total + add-ons = the charge');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  });
}
