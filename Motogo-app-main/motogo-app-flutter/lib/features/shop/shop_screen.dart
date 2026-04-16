import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import 'shop_models.dart';
import 'shop_provider.dart';

/// Shop product grid — mirrors s-merch from templates-shop.js.
class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider);
    final cart = ref.watch(cartProvider);
    final cartCount = cart.fold<int>(0, (sum, item) => sum + item.qty);

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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.asset('assets/logo.png', width: 28, height: 28, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(width: 28, height: 28, decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.motorcycle, size: 16, color: Colors.black))),
                        ),
                        const SizedBox(width: 8),
                        Text(t(context).tr('shopTitle'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                      ]),
                      Text(t(context).tr('shopSubtitle'), style: const TextStyle(fontSize: 12, color: Colors.white54)),
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
                              child: Center(child: Text('$cartCount', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.black))),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Voucher banner — prominent card
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: GestureDetector(
                onTap: () => context.push(Routes.voucher),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [MotoGoColors.dark, Color(0xFF2D4A35)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
                    boxShadow: [BoxShadow(color: MotoGoColors.dark.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Visual header with motorcycle icon
                      Container(
                        height: 100,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [MotoGoColors.dark, const Color(0xFF1A3A22).withValues(alpha: 0.9)],
                            begin: Alignment.centerLeft, end: Alignment.centerRight,
                          ),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(MotoGoTheme.radiusLg)),
                        ),
                        child: Stack(
                          children: [
                            Positioned(right: 16, top: 12, child: Icon(Icons.motorcycle, size: 60, color: MotoGoColors.green.withValues(alpha: 0.15))),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(4)),
                                      child: Text(t(context).tr('giftVoucher').toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: 1)),
                                    ),
                                    const SizedBox(width: 8),
                                    Text('MOTO GO 24', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.5), letterSpacing: 2)),
                                  ]),
                                  const SizedBox(height: 8),
                                  Text(t(context).tr('giftVoucherTitle'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Info row
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                        child: Row(
                          children: [
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t(context).tr('voucherDesc'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70)),
                                const SizedBox(height: 2),
                                Text(t(context).tr('voucherType'), style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4))),
                              ],
                            )),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(50)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.card_giftcard, size: 14, color: Colors.black),
                                const SizedBox(width: 6),
                                Text(t(context).tr('buyVoucher'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.black)),
                              ]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Products grid
          productsAsync.when(
            data: (products) => products.isEmpty
                ? SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('🛍️', style: TextStyle(fontSize: 36)),
                          const SizedBox(height: 12),
                          Text(t(context).tr('shopEmpty'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: MotoGoColors.g400)),
                        ],
                      ),
                    ),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.82,
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
            error: (_, __) => SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('⚠️', style: TextStyle(fontSize: 36)),
                    const SizedBox(height: 12),
                    Text(t(context).tr('loadingError'), style: const TextStyle(color: MotoGoColors.red)),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => ref.invalidate(productsProvider),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text(t(context).tr('retry')),
                    ),
                  ],
                ),
              ),
            ),
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
                        Text(t(context).tr('soldOut'), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: MotoGoColors.red)),
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
