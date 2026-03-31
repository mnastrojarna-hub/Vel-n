import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
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
        title: const Text('🛒 Košík'),
        backgroundColor: MotoGoColors.dark,
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () { notifier.clear(); showMotoGoToast(context, icon: '✓', title: 'Košík', message: 'Vyprázdněn'); },
              child: const Text('Vyprázdnit', style: TextStyle(color: MotoGoColors.g400, fontSize: 12)),
            ),
        ],
      ),
      body: items.isEmpty
          ? const Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('🛒', style: TextStyle(fontSize: 48)),
                SizedBox(height: 12),
                Text('Košík je prázdný', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
                Text('Přidejte produkty z obchodu', style: TextStyle(fontSize: 12, color: MotoGoColors.g400)),
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
                  padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, -4))],
                  ),
                  child: Column(
                    children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('Mezisoučet', style: TextStyle(fontSize: 12, color: MotoGoColors.g400)),
                        Text('${subtotal.toStringAsFixed(0)} Kč', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.black)),
                      ]),
                      if (!digitalOnly && shipping > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            const Text('Doprava', style: TextStyle(fontSize: 12, color: MotoGoColors.g400)),
                            Text('${shipping.toStringAsFixed(0)} Kč', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.black)),
                          ]),
                        ),
                      if (discount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            const Text('Sleva', style: TextStyle(fontSize: 12, color: MotoGoColors.g400)),
                            Text('−${discount.toStringAsFixed(0)} Kč', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.greenDarker)),
                          ]),
                        ),
                      const Divider(height: 16),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('Celkem', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
                        Text('${total.toStringAsFixed(0)} Kč', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: MotoGoColors.greenDarker)),
                      ]),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => context.push(Routes.checkout),
                        style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                        child: Text('K pokladně · ${total.toStringAsFixed(0)} Kč →'),
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
