import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../booking/booking_models.dart';
import '../shop_models.dart';
import '../shop_provider.dart';

/// Promo / voucher code input card.
/// Supports multiple codes (percentage + fixed), shows applied codes with
/// individual remove buttons.
class CheckoutPromoCard extends ConsumerWidget {
  final TextEditingController promoCtrl;
  final bool promoLoading;
  final String? promoError;
  final String? promoSuccess;
  final VoidCallback onApply;
  final VoidCallback onRemoveCode;

  const CheckoutPromoCard({
    super.key,
    required this.promoCtrl,
    required this.promoLoading,
    this.promoError,
    this.promoSuccess,
    required this.onApply,
    required this.onRemoveCode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appliedCodes = ref.watch(shopAppliedCodesProvider);

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
        Text('🏷️ ${t(context).tr('discountCode').toUpperCase()} / ${t(context).tr('giftVoucher').toUpperCase()}',
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: MotoGoColors.g400,
                letterSpacing: 0.5)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: promoCtrl,
              decoration: InputDecoration(
                hintText: t(context).tr('discountCode'),
                isDense: true,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(MotoGoTheme.radiusSm),
                  borderSide: BorderSide(
                      color: promoError != null
                          ? MotoGoColors.red
                          : MotoGoColors.g200,
                      width: 2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(MotoGoTheme.radiusSm),
                  borderSide: BorderSide(
                      color: promoError != null
                          ? MotoGoColors.red
                          : MotoGoColors.g200,
                      width: 2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(MotoGoTheme.radiusSm),
                  borderSide: const BorderSide(
                      color: MotoGoColors.green,
                      width: 2),
                ),
              ),
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => onApply(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: promoLoading ? null : onApply,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: MotoGoColors.green,
                borderRadius:
                    BorderRadius.circular(MotoGoTheme.radiusSm),
              ),
              child: promoLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : Text(t(context).tr('apply'),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.black)),
            ),
          ),
        ]),
        if (promoError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(promoError!,
                style: const TextStyle(
                    fontSize: 11, color: MotoGoColors.red)),
          ),
        if (promoSuccess != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('✓ $promoSuccess',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: MotoGoColors.greenDarker)),
          ),
        if (appliedCodes.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...appliedCodes.map((d) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: MotoGoColors.greenPale,
                    borderRadius:
                        BorderRadius.circular(MotoGoTheme.radiusSm),
                    border: Border.all(
                        color: MotoGoColors.green.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    Text(
                      d.type == DiscountType.percent
                          ? '🏷️ ${d.code} (−${d.value.toStringAsFixed(0)}%)'
                          : '🎁 ${d.code} (−${d.value.toStringAsFixed(0)} Kč)',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: MotoGoColors.greenDarker),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        final updated = ref
                            .read(shopAppliedCodesProvider)
                            .where((c) => c.code != d.code)
                            .toList();
                        ref
                            .read(shopAppliedCodesProvider.notifier)
                            .state = updated;
                        onRemoveCode();
                      },
                      child: const Text('✕',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: MotoGoColors.red)),
                    ),
                  ]),
                ),
              )),
        ],
      ]),
    );
  }
}
