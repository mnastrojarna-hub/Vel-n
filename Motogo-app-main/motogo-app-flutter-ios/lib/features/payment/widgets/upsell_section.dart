import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/net_image.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../shop/shop_models.dart';
import '../../shop/shop_provider.dart';
import '../booking_upsell_provider.dart';
import '../../../core/currency.dart';

/// Upsell/cross-sell section for the payment summary screen.
/// Shows featured shop products.
/// Products are added to bookingUpsellProvider (NOT the cart)
/// so the cart FAB never appears.
class UpsellSection extends ConsumerWidget {
  /// Doprodej (e-shopové produkty) — řízeno feature flagem reservation_upsell.
  final bool showProducts;

  const UpsellSection({
    super.key,
    this.showProducts = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider);
    final upsellItems = ref.watch(bookingUpsellProvider);
    // Když je doprodej vypnutý, sekci vůbec nevykreslíme.
    if (!showProducts) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoRadius.card),
        boxShadow: MotoGoShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.star, size: 16, color: MotoGoColors.green),
            const SizedBox(width: 6),
            Text(
              t(context).tr('recommendForBooking'),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: MotoGoColors.dark,
              ),
            ),
          ]),
          const SizedBox(height: 12),

          // Featured shop products (max 3) — jen když je doprodej zapnutý
          if (showProducts) productsAsync.when(
            data: (products) {
              final featured = products.take(3).toList();
              if (featured.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Z e-shopu MotoGo24',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: MotoGoColors.g400,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...featured.map((p) {
                    final notifier =
                        ref.read(bookingUpsellProvider.notifier);
                    final selected = notifier.isProductSelected(p.id);
                    final chosenSize = notifier.selectedSize(p.id);
                    return _ProductTile(
                      product: p,
                      selected: selected,
                      chosenSize: chosenSize,
                      onToggle: (size) => ref
                          .read(bookingUpsellProvider.notifier)
                          .toggle(p.id, p.name, p.price, size: size),
                      onRemove: () => ref
                          .read(bookingUpsellProvider.notifier)
                          .removeProduct(p.id),
                    );
                  }),
                ],
              );
            },
            loading: () => const SizedBox(
              height: 40,
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: MotoGoColors.green,
                ),
              ),
            ),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// Compact product tile for upsell — toggles selection on/off.
/// Shows inline size picker when the product requires a size.
class _ProductTile extends StatelessWidget {
  final Product product;
  final bool selected;
  final String? chosenSize;
  final ValueChanged<String?> onToggle;
  final VoidCallback onRemove;

  const _ProductTile({
    required this.product,
    required this.selected,
    required this.chosenSize,
    required this.onToggle,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected ? MotoGoColors.greenPale : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? MotoGoColors.green : Colors.transparent,
            width: selected ? 1.5 : 0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product row (image + name + button)
            GestureDetector(
              onTap: () {
                if (selected) {
                  onRemove();
                } else if (!product.needsSize) {
                  onToggle(null);
                }
                // If needs size & not selected → do nothing (user picks size below)
              },
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: product.displayImage.isNotEmpty
                      ? MgImage(
                          product.displayImage,
                          thumbWidth: 150,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          error: _placeholder(),
                        )
                      : _placeholder(),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: MotoGoColors.black,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${Money.czk(product.price)}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: MotoGoColors.g400,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: selected
                        ? MotoGoColors.green
                        : MotoGoColors.greenPale,
                    borderRadius:
                        BorderRadius.circular(MotoGoRadius.pill),
                    border: Border.all(color: MotoGoColors.green),
                  ),
                  child: Text(
                    selected ? t(context).tr('addedCheck') : t(context).tr('addLabel').toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: selected
                          ? Colors.black
                          : MotoGoColors.greenDarker,
                    ),
                  ),
                ),
              ]),
            ),

            // Inline size picker (visible when product needs size)
            if (product.needsSize) ...[
              const SizedBox(height: 6),
              const Text(
                'Velikost:',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: MotoGoColors.g400,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: product.sizes.map((size) {
                  final active = chosenSize == size;
                  return GestureDetector(
                    onTap: () {
                      if (active) {
                        onRemove();
                      } else {
                        // Remove previous size variant then add new one
                        onRemove();
                        onToggle(size);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: active
                            ? MotoGoColors.green
                            : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: active
                              ? MotoGoColors.green
                              : MotoGoColors.g200,
                          width: active ? 2 : 1,
                        ),
                      ),
                      child: Text(
                        size,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: active
                              ? Colors.white
                              : MotoGoColors.black,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 44,
        height: 44,
        color: MotoGoColors.g100,
        child: const Icon(Icons.shopping_bag,
            size: 20, color: MotoGoColors.g400),
      );
}
