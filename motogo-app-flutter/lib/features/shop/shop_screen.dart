import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import 'shop_models.dart';
import 'shop_provider.dart';

/// Shop product grid — mirrors s-merch from templates-shop.js.
class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider);
    final cart = ref.watch(cartProvider);
    final cartCount = ref.read(cartProvider.notifier).itemCount;

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 20, 16),
              decoration: const BoxDecoration(
                color: MotoGoColors.dark,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('🛍️ MotoGo Shop', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                      Text('Oblečení, výbava a dárkové poukazy', style: TextStyle(fontSize: 12, color: Colors.white54)),
                    ],
                  ),
                  // Cart badge
                  GestureDetector(
                    onTap: () => context.push(Routes.cart),
                    child: Stack(
                      children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                          child: const Center(child: Text('🛒', style: TextStyle(fontSize: 20))),
                        ),
                        if (cartCount > 0)
                          Positioned(
                            right: 0, top: 0,
                            child: Container(
                              width: 18, height: 18,
                              decoration: const BoxDecoration(color: MotoGoColors.green, shape: BoxShape.circle),
                              child: Center(child: Text('$cartCount', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white))),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Voucher banner
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: GestureDetector(
                onTap: () => context.push(Routes.voucher),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [MotoGoColors.dark, Color(0xFF2D4A35)]),
                    borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
                  ),
                  child: const Row(
                    children: [
                      Text('🎁', style: TextStyle(fontSize: 28)),
                      SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Dárkové poukazy', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
                          Text('Libovolná částka · elektronický nebo tištěný', style: TextStyle(fontSize: 11, color: Colors.white54)),
                        ],
                      )),
                      Text('›', style: TextStyle(fontSize: 20, color: MotoGoColors.green)),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Products grid
          productsAsync.when(
            data: (products) => SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.7,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _ProductCard(
                    product: products[i],
                    onTap: () => context.push('/shop/${products[i].id}'),
                  ),
                  childCount: products.length,
                ),
              ),
            ),
            loading: () => const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: MotoGoColors.green))),
            error: (_, __) => const SliverFillRemaining(child: Center(child: Text('Chyba načítání'))),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  const _ProductCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
          boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.08), blurRadius: 16)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(MotoGoTheme.radiusLg)),
                child: CachedNetworkImage(
                  imageUrl: product.displayImage, fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(color: MotoGoColors.g200, child: const Center(child: Text('🛍️', style: TextStyle(fontSize: 32)))),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: MotoGoColors.black), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${product.price.toStringAsFixed(0)} Kč', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: MotoGoColors.greenDarker)),
                      if (!product.inStock)
                        const Text('Vyprodáno', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: MotoGoColors.red)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
