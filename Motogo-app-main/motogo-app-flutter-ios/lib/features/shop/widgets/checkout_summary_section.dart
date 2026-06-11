import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../shop_models.dart';

/// Order summary — cart items, shipping cost, discount, and total.
class CheckoutSummarySection extends StatelessWidget {
  final List<CartItem> cart;
  final bool digitalOnly;
  final ShipMode shipMode;
  final double shipping;
  final double discount;
  final double total;

  const CheckoutSummarySection({
    super.key,
    required this.cart,
    required this.digitalOnly,
    required this.shipMode,
    required this.shipping,
    required this.discount,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MotoGoColors.g100,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
      ),
      child: Column(children: [
        // Each cart item
        for (final item in cart)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${item.name}${item.qty > 1 ? ' ×${item.qty}' : ''}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: MotoGoColors.g600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text('${item.total.toStringAsFixed(0)} Kč',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: MotoGoColors.black)),
                ]),
          ),
        // Shipping
        if (!digitalOnly)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    shipMode == ShipMode.post
                        ? t(context).tr('shippingPost')
                        : t(context).tr('shippingPickup'),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: MotoGoColors.g600),
                  ),
                  Text(
                    shipping > 0
                        ? '+${shipping.toStringAsFixed(0)} Kč'
                        : t(context).tr('free'),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: MotoGoColors.black),
                  ),
                ]),
          ),
        // Discount
        if (discount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(t(context).tr('discountLabel'),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: MotoGoColors.greenDarker)),
                  Text('−${discount.toStringAsFixed(0)} Kč',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: MotoGoColors.greenDarker)),
                ]),
          ),
        const Divider(height: 12, color: MotoGoColors.g200),
        // Total
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(t(context).tr('total'),
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: MotoGoColors.black)),
          Text('${total.toStringAsFixed(0)} Kč',
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: MotoGoColors.green)),
        ]),
      ]),
    );
  }
}
