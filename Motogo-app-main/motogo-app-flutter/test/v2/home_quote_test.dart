// quoteFor (Home funnel / calculator prices) == what /booking shows for the
// same fresh draft (PLAN §5.5): same PriceCalculator inputs, every bike ×
// rank × pickup time × length.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/features/booking/booking_models.dart';
import 'package:motogo_app/features/booking/booking_provider.dart';
import 'package:motogo_app/features/booking/booking_quote.dart';
import 'package:motogo_app/features/loyalty/loyalty_provider.dart';

import 'support/fakes_home.dart';

void main() {
  final start = DateTime(2026, 10, 23); // Friday
  for (final level in [0, 2, 3, 17, 20]) {
    for (final pickup in [null, '12:00']) {
      for (final days in [1, 2, 3, 7]) {
        test('quote parity L$level pickup=$pickup ${days}d', () async {
          final loyalty = level == 0 ? null : loyaltyAt(level);
          for (final m in kMotos) {
            final c = ProviderContainer(overrides: [
              loyaltyStatusProvider.overrideWith((ref) async => loyalty),
            ]);
            addTearDown(c.dispose);
            await c.read(loyaltyStatusProvider.future);
            final end = DateTime(start.year, start.month, start.day + days - 1);
            c.read(bookingMotoProvider.notifier).state = m;
            c.read(bookingDraftProvider.notifier).state = BookingDraft(
              motoId: m.id,
              motoName: m.model,
              startDate: start,
              endDate: end,
              pickupTime: pickup,
            );
            final form = c.read(priceBreakdownProvider);
            final q = quoteFor(m, start, end, pickupTime: pickup, loyalty: loyalty);
            expect(q.total, form.total, reason: '${m.model} L$level $pickup ${days}d');
            expect(q.latePickupDiscount, form.latePickupDiscount);
            expect(q.loyaltyDiscount, form.loyaltyDiscount);
          }
        });
      }
    }
  }

  test('half-day offer only from 2 days and only with 12:00', () {
    final m = kMotos.first;
    final one = quoteFor(m, start, start, pickupTime: '12:00');
    final two = quoteFor(m, start, start.add(const Duration(days: 1)), pickupTime: '12:00');
    expect(one.latePickupDiscount, 0);
    expect(two.latePickupDiscount, greaterThan(0));
    expect(listQuoteFor(m, start, start.add(const Duration(days: 2))).total,
        greaterThanOrEqualTo(quoteFor(m, start, start.add(const Duration(days: 2)), loyalty: loyaltyAt(3)).total));
  });
}
