import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../booking_models.dart';

/// Price summary card — mirrors the .pr rows from templates-booking-form2.js.
class PriceSummaryCard extends StatelessWidget {
  final PriceBreakdown breakdown;

  const PriceSummaryCard({super.key, required this.breakdown});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
        boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.06), blurRadius: 12)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Shrnutí ceny', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
          const SizedBox(height: 10),

          // Base price
          _PriceRow(
            label: 'Motorka × ${breakdown.days} ${_dayWord(breakdown.days)}',
            value: '${breakdown.basePrice.toStringAsFixed(0)} Kč',
          ),

          // Delivery
          if (breakdown.deliveryFee > 0)
            _PriceRow(
              label: 'Přistavení / vrácení',
              value: '+${breakdown.deliveryFee.toStringAsFixed(0)} Kč',
            ),

          // Extras
          if (breakdown.extrasTotal > 0)
            _PriceRow(
              label: 'Doplňky a výbava',
              value: '+${breakdown.extrasTotal.toStringAsFixed(0)} Kč',
            ),

          // Insurance
          if (breakdown.insuranceFee > 0)
            _PriceRow(
              label: 'Pojištění',
              value: '+${breakdown.insuranceFee.toStringAsFixed(0)} Kč',
            ),

          // Discount
          if (breakdown.discountTotal > 0)
            _PriceRow(
              label: 'Sleva',
              value: '−${breakdown.discountTotal.toStringAsFixed(0)} Kč',
              valueColor: MotoGoColors.greenDarker,
              valueBold: true,
            ),

          // Deposit note
          const _PriceRow(
            label: '✓ Záloha se neúčtuje',
            value: '0 Kč',
            subtle: true,
          ),

          // Divider
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(color: MotoGoColors.g200, height: 1),
          ),

          // Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Celkem (cena konečná)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: MotoGoColors.black),
              ),
              Text(
                '${breakdown.total.toStringAsFixed(0)} Kč',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: MotoGoColors.greenDarker),
              ),
            ],
          ),

          const SizedBox(height: 4),
          const Text(
            'Cena bez DPH, nejsme plátci',
            style: TextStyle(fontSize: 9, color: MotoGoColors.g400),
          ),
        ],
      ),
    );
  }

  String _dayWord(int n) {
    if (n == 1) return 'den';
    if (n < 5) return 'dny';
    return 'dní';
  }
}

class _PriceRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool valueBold;
  final bool subtle;

  const _PriceRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.valueBold = false,
    this.subtle = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: subtle ? FontWeight.w500 : FontWeight.w600,
              color: subtle ? MotoGoColors.g400 : MotoGoColors.g600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: valueBold ? FontWeight.w800 : FontWeight.w600,
              color: valueColor ?? (subtle ? MotoGoColors.g400 : MotoGoColors.black),
            ),
          ),
        ],
      ),
    );
  }
}
