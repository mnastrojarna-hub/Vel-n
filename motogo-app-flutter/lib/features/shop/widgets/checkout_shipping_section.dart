import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../shop_models.dart';
import '../shop_provider.dart';
import 'ship_card.dart';

/// Shipping method selector + delivery address fields (for post).
/// Only shown when the cart is NOT digital-only.
class CheckoutShippingSection extends ConsumerWidget {
  final TextEditingController nameCtrl;
  final TextEditingController streetCtrl;
  final TextEditingController zipCtrl;
  final TextEditingController cityCtrl;

  const CheckoutShippingSection({
    super.key,
    required this.nameCtrl,
    required this.streetCtrl,
    required this.zipCtrl,
    required this.cityCtrl,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shipMode = ref.watch(shipModeProvider);

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
        Text('📦 ${t(context).tr('deliveryDetails').toUpperCase()}',
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: MotoGoColors.g400,
                letterSpacing: 0.5)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: ShipCard(
              icon: '📮',
              label: t(context).tr('shippingByPost'),
              sublabel: t(context).tr('shippingPostInfo'),
              active: shipMode == ShipMode.post,
              onTap: () =>
                  ref.read(shipModeProvider.notifier).state = ShipMode.post,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ShipCard(
              icon: '🏪',
              label: t(context).tr('personalPickup'),
              sublabel: t(context).tr('personalPickupInfo'),
              active: shipMode == ShipMode.pickup,
              onTap: () =>
                  ref.read(shipModeProvider.notifier).state = ShipMode.pickup,
            ),
          ),
        ]),
        // Address fields (only for post)
        if (shipMode == ShipMode.post) ...[
          const SizedBox(height: 12),
          const Divider(height: 1, color: MotoGoColors.g100),
          const SizedBox(height: 12),
          Text('📋 ${t(context).tr('deliveryDetails')}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
              controller: nameCtrl,
              decoration:
                  InputDecoration(labelText: t(context).tr('fullNameLabel'))),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              flex: 2,
              child: TextField(
                  controller: cityCtrl,
                  decoration:
                      InputDecoration(labelText: t(context).tr('city'))),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: zipCtrl,
                decoration: InputDecoration(labelText: t(context).tr('zip')),
                keyboardType: TextInputType.number,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          TextField(
              controller: streetCtrl,
              decoration: InputDecoration(labelText: t(context).tr('streetShort'))),
        ],
      ]),
    );
  }
}
