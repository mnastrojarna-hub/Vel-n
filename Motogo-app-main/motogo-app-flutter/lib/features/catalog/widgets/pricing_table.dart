import 'package:flutter/material.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/theme.dart';
import '../moto_model.dart';

/// 7-day pricing table shown on the moto detail screen.
class PricingTable extends StatelessWidget {
  final DayPrices prices;
  const PricingTable({super.key, required this.prices});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: MotoGoColors.black.withValues(alpha: 0.06),
            blurRadius: 12,
          )
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          children: List.generate(7, (i) {
            final price = prices.asList[i];
            final isWeekend = i >= 4; // Pá, So, Ne
            return Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: isWeekend
                      ? const Color(0xFF2D1A1A)
                      : MotoGoColors.dark,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(children: [
                  Text(
                    DayPrices.dayLabels[i].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Colors.white54,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    price > 0 ? '${price.toStringAsFixed(0)}' : '–',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    t(context).tr('pricingCurrencyPerDay'),
                    style: const TextStyle(fontSize: 8, color: Colors.white38),
                  ),
                ]),
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
        Text(
          t(context).tr('pricingNote'),
          style: const TextStyle(fontSize: 10, color: MotoGoColors.g400),
        ),
      ]),
    );
  }
}
