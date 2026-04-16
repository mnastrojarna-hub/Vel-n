import 'package:flutter/material.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/theme.dart';
import '../moto_model.dart';

/// Price footer card showing price-from and optional total for selected dates.
class PriceFooter extends StatelessWidget {
  final DayPrices? prices;
  final double totalPrice;
  final int dayCount;
  const PriceFooter({
    super.key,
    this.prices,
    required this.totalPrice,
    required this.dayCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MotoGoColors.g100,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              t(context).tr('priceFrom'),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: MotoGoColors.g400,
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${prices?.cheapest.toStringAsFixed(0) ?? '–'} Kč',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: MotoGoColors.black,
                  ),
                ),
                Text(
                  t(context).tr('pricePerDay'),
                  style: const TextStyle(fontSize: 13, color: MotoGoColors.g400),
                ),
              ],
            ),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              t(context).tr('priceDeposit'),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: MotoGoColors.g400,
              ),
            ),
            Row(children: [
              Text(
                t(context).tr('priceNoDeposit'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: MotoGoColors.greenDark,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.check_circle, size: 16, color: MotoGoColors.greenDark),
            ]),
          ]),
        ]),
        // Total price for selected dates
        if (dayCount > 0 && totalPrice > 0) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${t(context).tr('priceTotalFor')}$dayCount ${dayCount == 1 ? t(context).tr('day1') : dayCount < 5 ? t(context).tr('days24') : t(context).tr('days5')}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: MotoGoColors.black,
                  ),
                ),
                Text(
                  '${totalPrice.toStringAsFixed(0)} Kč',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: MotoGoColors.greenDarker,
                  ),
                ),
              ],
            ),
          ),
        ],
      ]),
    );
  }
}
