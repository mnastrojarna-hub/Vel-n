import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../auth/widgets/toast_helper.dart';
import 'shop_models.dart';
import 'shop_provider.dart';

/// Product detail — mirrors s-merch-detail from templates-shop-detail.js.
class ProductDetailScreen extends ConsumerStatefulWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});

  @override
  ConsumerState<ProductDetailScreen> createState() => _ProductDetailState();
}

class _ProductDetailState extends ConsumerState<ProductDetailScreen> {
  int _imageIndex = 0;
  String? _selectedSize;

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);

    return productsAsync.when(
      data: (products) {
        final product = products.where((p) => p.id == widget.productId).firstOrNull;
        if (product == null) return Scaffold(appBar: AppBar(title: const Text('Produkt')), body: const Center(child: Text('Nenalezeno')));
        return _build(context, product);
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator(color: MotoGoColors.green))),
      error: (_, __) => Scaffold(body: const Center(child: Text('Chyba'))),
    );
  }

  Widget _build(BuildContext context, Product product) {
    final images = product.images.isNotEmpty ? product.images : [product.displayImage];

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // Image carousel
              SliverToBoxAdapter(
                child: Stack(
                  children: [
                    SizedBox(
                      height: 300,
                      child: PageView.builder(
                        itemCount: images.length,
                        onPageChanged: (i) => setState(() => _imageIndex = i),
                        itemBuilder: (_, i) => CachedNetworkImage(
                          imageUrl: images[i], fit: BoxFit.cover, width: double.infinity,
                          errorWidget: (_, __, ___) => Container(color: MotoGoColors.g200),
                        ),
                      ),
                    ),
                    Positioned(top: MediaQuery.of(context).padding.top + 8, left: 12,
                      child: GestureDetector(
                        onTap: () => context.pop(),
                        child: Container(width: 36, height: 36,
                          decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
                          child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)))),
                      ),
                    ),
                    if (images.length > 1)
                      Positioned(bottom: 8, left: 0, right: 0,
                        child: Row(mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(images.length, (i) => Container(
                            width: i == _imageIndex ? 16 : 6, height: 6, margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(color: i == _imageIndex ? MotoGoColors.green : Colors.white54, borderRadius: BorderRadius.circular(3)),
                          )),
                        ),
                      ),
                  ],
                ),
              ),

              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList.list(children: [
                  Text(product.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
                  const SizedBox(height: 4),
                  Text('${product.price.toStringAsFixed(0)} Kč', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: MotoGoColors.greenDarker)),
                  const SizedBox(height: 12),

                  if (product.description != null)
                    Text(product.description!, style: const TextStyle(fontSize: 13, height: 1.6, color: MotoGoColors.g600)),
                  const SizedBox(height: 12),

                  // Color & material
                  if (product.color != null || product.material != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm)),
                      child: Column(children: [
                        if (product.color != null)
                          _InfoRow(label: 'Barva', value: product.color!),
                        if (product.material != null)
                          _InfoRow(label: 'Materiál', value: product.material!),
                      ]),
                    ),
                  const SizedBox(height: 12),

                  // Size selector
                  if (product.needsSize) ...[
                    const Text('Velikost', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: product.sizes.map((size) {
                        final active = _selectedSize == size;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedSize = size),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: active ? MotoGoColors.green : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: active ? MotoGoColors.green : MotoGoColors.g200, width: 2),
                            ),
                            child: Text(size, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: active ? Colors.white : MotoGoColors.black)),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Stock
                  if (!product.inStock)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(8)),
                      child: const Text('Vyprodáno', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: MotoGoColors.red), textAlign: TextAlign.center),
                    ),

                  const SizedBox(height: 80),
                ]),
              ),
            ],
          ),

          // Add to cart button
          if (product.inStock)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
                decoration: BoxDecoration(color: Colors.white,
                  boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, -4))]),
                child: ElevatedButton(
                  onPressed: () {
                    if (product.needsSize && _selectedSize == null) {
                      showMotoGoToast(context, icon: '⚠️', title: 'Velikost', message: 'Vyberte velikost');
                      return;
                    }
                    final cartId = _selectedSize != null ? '${product.id}-$_selectedSize' : product.id;
                    final cartName = _selectedSize != null ? '${product.name} ($_selectedSize)' : product.name;
                    ref.read(cartProvider.notifier).addItem(cartId, cartName, product.price);
                    showMotoGoToast(context, icon: '✓', title: 'Přidáno', message: cartName);
                  },
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: Text('Přidat do košíku · ${product.price.toStringAsFixed(0)} Kč'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label; final String value;
  const _InfoRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.g400)),
      Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
    ]),
  );
}
