import 'package:flutter/material.dart';

import '../features/booking/booking_models.dart';
import '../features/booking/booking_ui_helpers.dart';
import 'i18n/i18n_provider.dart';

/// Price breakdown summary card inside the booking form.
class BookingFormPriceSection extends StatelessWidget {
  const BookingFormPriceSection({
    super.key,
    required this.draft,
    required this.bd,
    required this.dayCount,
  });

  final BookingDraft draft;
  final PriceBreakdown bd;
  final int dayCount;

  @override
  Widget build(BuildContext context) {
    final dc = dayCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t(context).priceSummary,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 10),
            bookingPriceRow(
              '${t(context).motorcycle} × $dc ${dc == 1 ? t(context).tr("day1") : dc < 5 ? t(context).tr("days24") : t(context).tr("days5")}',
              '${bd.basePrice.toStringAsFixed(0)} Kč',
            ),
            for (final e in draft.extras)
              bookingPriceRow(
                e.name,
                '+${(e.price * e.quantity).toStringAsFixed(0)} Kč',
              ),
            if (bd.pickupDeliveryFee > 0)
              bookingPriceRow(
                t(context).tr('deliveryFee'),
                '+${bd.pickupDeliveryFee.toStringAsFixed(0)} Kč',
              ),
            if (bd.returnDeliveryFee > 0)
              bookingPriceRow(
                t(context).tr('returnFee'),
                '+${bd.returnDeliveryFee.toStringAsFixed(0)} Kč',
              ),
            if (bd.discountTotal > 0)
              bookingPriceRow(
                t(context).tr('discountLabel'),
                '−${bd.discountTotal.toStringAsFixed(0)} Kč',
                color: const Color(0xFF1A8A18),
              ),
            bookingPriceRow('✓ ${t(context).tr('depositNotCharged')}', '0 Kč', subtle: true),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(color: Color(0xFFD4E8E0), height: 1),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  t(context).totalFinal,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    decoration: TextDecoration.none,
                  ),
                ),
                Text(
                  '${bd.total.toStringAsFixed(0)} Kč',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1A8A18),
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              t(context).tr('priceVatNote'),
              style: TextStyle(
                fontSize: 9,
                color: Color(0xFF8AAB99),
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
