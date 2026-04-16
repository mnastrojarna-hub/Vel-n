import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import '../auth/widgets/toast_helper.dart';
import '../booking/booking_provider.dart';
import 'shop_models.dart';
import 'shop_provider.dart';

/// Cart screen — mirrors s-cart from cart-engine.js renderCart().
class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    final shipMode = ref.watch(shipModeProvider);
    final discount = ref.watch(shopDiscountProvider);
    final digitalOnly = isCartDigitalOnly(items);
    final subtotal = notifier.subtotal;
    final shipping = digitalOnly ? 0.0 : (shipMode == ShipMode.post ? shippingCost : 0);
    final total = (subtotal + shipping - discount).clamp(0.0, double.infinity);

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🛒 ${t(context).tr('cartTitle')}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            Text(t(context).tr('orderSummary'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white70)),
          ],
        ),
        backgroundColor: MotoGoColors.dark,
        leading: GestureDetector(
          onTap: () => context.pop(),
          child: Center(
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
              child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black))),
            ),
          ),
        ),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () { notifier.clear(); showMotoGoToast(context, icon: '✓', title: t(context).tr('cartTitle'), message: t(context).tr('emptied')); },
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.delete_outline, size: 14, color: MotoGoColors.g400),
                const SizedBox(width: 4),
                Text(t(context).tr('emptyBtn'), style: const TextStyle(color: MotoGoColors.g400, fontSize: 12)),
              ]),
            ),
        ],
      ),
      body: items.isEmpty
          ? Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🛒', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text(t(context).tr('cartEmpty'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
                const SizedBox(height: 4),
                Text(t(context).tr('addProductsFromShop'), style: const TextStyle(fontSize: 12, color: MotoGoColors.g400)),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () => context.go(Routes.shop),
                  icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                  label: Text(t(context).tr('backToShop')),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ))
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    itemBuilder: (_, i) => _CartItemTile(
                      item: items[i],
                      onPlus: () => notifier.changeQty(items[i].id, 1),
                      onMinus: () => notifier.changeQty(items[i].id, -1),
                      onRemove: () => notifier.removeItem(items[i].id),
                    ),
                  ),
                ),

                // Summary + checkout
                Container(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, MediaQuery.of(context).padding.bottom + 14),
                  decoration: BoxDecoration(
                    color: MotoGoColors.g100,
                    border: const Border(top: BorderSide(color: MotoGoColors.g200)),
                  ),
                  child: Column(
                    children: [
                      // Subtotal
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('${t(context).tr('orderSummary')} (${notifier.itemCount})',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.g600)),
                        Text('${subtotal.toStringAsFixed(0)} Kč',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.black)),
                      ]),
                      const SizedBox(height: 4),
                      // Shipping
                      if (!digitalOnly)
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text(shipMode == ShipMode.post ? t(context).tr('shippingPost') : t(context).tr('shippingPickup'),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.g600)),
                          Text(shipping > 0 ? '+${shipping.toStringAsFixed(0)} Kč' : t(context).tr('free'),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.black)),
                        ]),
                      // Discount
                      if (discount > 0) ...[
                        const SizedBox(height: 4),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text(t(context).tr('discountLabel'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.greenDarker)),
                          Text('−${discount.toStringAsFixed(0)} Kč',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.greenDarker)),
                        ]),
                      ],
                      const SizedBox(height: 6),
                      const Divider(height: 1, color: MotoGoColors.g200),
                      const SizedBox(height: 6),
                      // Total
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text(t(context).tr('totalToPay'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
                        Text('${total.toStringAsFixed(0)} Kč', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: MotoGoColors.greenDarker)),
                      ]),
                      const SizedBox(height: 6),
                      Text(
                        t(context).tr('shopPriceNote'),
                        style: const TextStyle(fontSize: 10, color: MotoGoColors.g400, height: 1.4),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => context.push(Routes.checkout),
                        style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.shopping_cart_checkout, size: 18),
                        const SizedBox(width: 8),
                        Text(t(context).tr('toCheckout')),
                      ]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _CartItemTile extends StatelessWidget {
  final CartItem item;
  final VoidCallback onPlus, onMinus, onRemove;
  const _CartItemTile({required this.item, required this.onPlus, required this.onMinus, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
        boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.05), blurRadius: 8)],
      ),
      child: Row(
        children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
            Text('${item.price.toStringAsFixed(0)} Kč', style: const TextStyle(fontSize: 12, color: MotoGoColors.g400)),
          ])),
          // Qty controls
          Row(children: [
            _QtyBtn(label: '−', onTap: onMinus),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('${item.qty}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black))),
            _QtyBtn(label: '+', onTap: onPlus),
          ]),
          const SizedBox(width: 8),
          Text('${item.total.toStringAsFixed(0)} Kč', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
          const SizedBox(width: 8),
          GestureDetector(onTap: onRemove, child: const Text('🗑️', style: TextStyle(fontSize: 16))),
        ],
      ),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  final String label; final VoidCallback onTap;
  const _QtyBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 28, height: 28,
      decoration: BoxDecoration(color: MotoGoColors.g100, borderRadius: BorderRadius.circular(6), border: Border.all(color: MotoGoColors.g200)),
      child: Center(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black))),
    ),
  );
}
