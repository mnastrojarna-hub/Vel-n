import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../payment_provider.dart';

/// Displays a preview of the user's saved (default) Stripe card.
class SavedCardPreview extends StatelessWidget {
  final SavedCard card;
  const SavedCardPreview({super.key, required this.card});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MotoGoColors.greenPale,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
        border: Border.all(color: MotoGoColors.green, width: 2),
      ),
      child: Row(children: [
        const Text('\ud83d\udcb3', style: TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '\u2022\u2022\u2022\u2022 ${card.last4}  ${card.displayBrand}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: MotoGoColors.black),
              ),
              Text(
                '${card.displayExpiry}${card.holderName != null ? ' \u00b7 ${card.holderName}' : ''}',
                style: const TextStyle(
                    fontSize: 11, color: MotoGoColors.g400),
              ),
            ],
          ),
        ),
        const Text('Ulo\u017een\u00e1 karta',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: MotoGoColors.greenDarker)),
      ]),
    );
  }
}
