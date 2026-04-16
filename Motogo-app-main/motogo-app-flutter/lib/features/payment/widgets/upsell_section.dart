import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../shop/shop_models.dart';
import '../../shop/shop_provider.dart';
import '../booking_upsell_provider.dart';

/// Upsell/cross-sell section for the payment summary screen.
/// Shows featured shop products and optional insurance add-on.
/// Products are added to bookingUpsellProvider (NOT the cart)
/// so the cart FAB never appears.
class UpsellSection extends ConsumerWidget {
  final double? insurancePrice;
  final bool insuranceSelected;
  final ValueChanged<bool> onInsuranceChanged;

  const UpsellSection({
    super.key,
    this.insurancePrice,
    required this.insuranceSelected,
    required this.onInsuranceChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider);
    final upsellItems = ref.watch(bookingUpsellProvider);

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
          const Row(children: [
            Icon(Icons.star, size: 16, color: MotoGoColors.green),
            SizedBox(width: 6),
            Text(
              'DOPORUČUJEME K REZERVACI',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: MotoGoColors.dark,
              ),
            ),
          ]),
          const SizedBox(height: 12),

          // Insurance add-on
          if (insurancePrice != null && insurancePrice! > 0)
            _InsuranceTile(
              price: insurancePrice!,
              selected: insuranceSelected,
              onChanged: onInsuranceChanged,
            ),

          if (insurancePrice != null && insurancePrice! > 0)
            const SizedBox(height: 10),

          // Featured shop products (max 3)
          productsAsync.when(
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

/// Insurance add-on toggle tile.
class _InsuranceTile extends StatelessWidget {
  final double price;
  final bool selected;
  final ValueChanged<bool> onChanged;

  const _InsuranceTile({
    required this.price,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!selected),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? MotoGoColors.greenPale : MotoGoColors.g100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? MotoGoColors.green : MotoGoColors.g200,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: selected
                  ? MotoGoColors.green.withValues(alpha: 0.2)
                  : MotoGoColors.g200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.shield,
              size: 20,
              color: selected ? MotoGoColors.greenDarker : MotoGoColors.g400,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Rozšířené pojištění',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: MotoGoColors.black,
                  ),
                ),
                Text(
                  'Snížená spoluúčast při nehodě',
                  style: TextStyle(
                    fontSize: 10,
                    color: MotoGoColors.g400,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '+${price.toStringAsFixed(0)} Kč',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: selected ? MotoGoColors.greenDarker : MotoGoColors.black,
            ),
          ),
        ]),
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
                      ? CachedNetworkImage(
                          imageUrl: product.displayImage,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _placeholder(),
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
                        '${product.price.toStringAsFixed(0)} Kč',
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
                    selected ? '✓ PŘIDÁNO' : 'PŘIDAT',
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
