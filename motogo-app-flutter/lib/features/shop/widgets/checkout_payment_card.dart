import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../payment/payment_provider.dart';

/// Payment method card showing card options and saved default card.
class CheckoutPaymentCard extends ConsumerWidget {
  const CheckoutPaymentCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defaultCard = ref.watch(defaultCardProvider);

    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
        boxShadow: [
          BoxShadow(
              color: MotoGoColors.black.withValues(alpha: 0.1),
              blurRadius: 20)
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('💳 ${t(context).tr('payment').toUpperCase()}',
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: MotoGoColors.g400,
                letterSpacing: 0.5)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: MotoGoColors.greenPale,
            borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
            border: Border.all(color: MotoGoColors.green, width: 2),
          ),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: MotoGoColors.green,
                  borderRadius: BorderRadius.circular(8)),
              child: const Center(
                  child: Text('💳', style: TextStyle(fontSize: 16))),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t(context).tr('paymentCard'),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: MotoGoColors.black)),
                    const Text('Visa · Mastercard',
                        style: TextStyle(
                            fontSize: 11, color: MotoGoColors.g400)),
                  ]),
            ),
          ]),
        ),
        // Saved card preview
        if (defaultCard != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: MotoGoColors.greenPale,
              borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
              border: Border.all(color: MotoGoColors.green, width: 2),
            ),
            child: Row(children: [
              const Text('💳', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '•••• ${defaultCard.last4}  ${defaultCard.displayBrand}',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: MotoGoColors.black)),
                    ]),
              ),
              Text('✓ ${t(context).tr('selected')}',
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: MotoGoColors.green)),
            ]),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          t(context).tr('securePayment'),
          style: const
              TextStyle(fontSize: 11, color: MotoGoColors.g400, height: 1.6),
        ),
      ]),
    );
  }
}
