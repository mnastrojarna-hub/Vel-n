import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
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
  int _qty = 1;

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);

    return productsAsync.when(
      data: (products) {
        final product = products.where((p) => p.id == widget.productId).firstOrNull;
        if (product == null) return Scaffold(appBar: AppBar(title: Text(t(context).tr('shop'))), body: Center(child: Text(t(context).tr('error'))));
        return _build(context, product);
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator(color: MotoGoColors.green))),
      error: (_, __) => Scaffold(body: Center(child: Text(t(context).tr('error')))),
    );
  }

  Widget _build(BuildContext context, Product product) {
    final images = product.images.isNotEmpty ? product.images : [product.displayImage];

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: Column(
        children: [
          // Image — takes ALL remaining space after content
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  itemCount: images.length,
                  onPageChanged: (i) => setState(() => _imageIndex = i),
                  itemBuilder: (_, i) => CachedNetworkImage(
                    imageUrl: images[i], fit: BoxFit.cover, width: double.infinity,
                    errorWidget: (_, __, ___) => Container(color: MotoGoColors.g200),
                  ),
                ),
                Positioned(top: MediaQuery.of(context).padding.top + 8, left: 12,
                  child: GestureDetector(
                    onTap: () => context.pop(),
                    child: Container(width: 36, height: 36,
                      decoration: BoxDecoration(color: MotoGoColors.green, borderRadius: BorderRadius.circular(10)),
                      child: const Center(child: Text('←', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black)))),
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

          // Content — fixed size, image adapts above
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: MotoGoColors.bg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(product.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: MotoGoColors.black), maxLines: 2, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 12),
                    Text('${product.price.toStringAsFixed(0)} Kč', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: MotoGoColors.greenDarker)),
                  ],
                ),

                if (product.description != null) ...[
                  const SizedBox(height: 6),
                  Text(product.description!, style: const TextStyle(fontSize: 12, height: 1.4, color: MotoGoColors.g600), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],

                // Color & material — compact row
                if (product.color != null || product.material != null) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    if (product.color != null) ...[
                      Text('Barva: ', style: const TextStyle(fontSize: 11, color: MotoGoColors.g400)),
                      Text(product.color!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
                      if (product.material != null) const SizedBox(width: 16),
                    ],
                    if (product.material != null) ...[
                      Text('${t(context).tr('material')}: ', style: const TextStyle(fontSize: 11, color: MotoGoColors.g400)),
                      Text(product.material!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
                    ],
                  ]),
                ],

                // Size selector
                if (product.needsSize) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6, runSpacing: 6,
                    children: product.sizes.map((size) {
                      final active = _selectedSize == size;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedSize = size),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: active ? MotoGoColors.green : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: active ? MotoGoColors.green : MotoGoColors.g200, width: 2),
                          ),
                          child: Text(size, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: active ? Colors.black : MotoGoColors.black)),
                        ),
                      );
                    }).toList(),
                  ),
                ],

                // Stock
                if (!product.inStock) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: MotoGoColors.redBg, borderRadius: BorderRadius.circular(8)),
                    child: Text(t(context).tr('soldOut'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.red), textAlign: TextAlign.center),
                  ),
                ],

                // Quantity + Add to cart
                if (product.inStock) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    const Text('Množství', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () { if (_qty > 1) setState(() => _qty--); },
                      child: Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(color: MotoGoColors.g100, borderRadius: BorderRadius.circular(6), border: Border.all(color: MotoGoColors.g200)),
                        child: const Center(child: Text('−', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: MotoGoColors.black))),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('$_qty', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.black)),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _qty++),
                      child: Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(color: MotoGoColors.g100, borderRadius: BorderRadius.circular(6), border: Border.all(color: MotoGoColors.g200)),
                        child: const Center(child: Text('+', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: MotoGoColors.black))),
                      ),
                    ),
                    const Spacer(),
                    Text('${(product.price * _qty).toStringAsFixed(0)} Kč', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: MotoGoColors.greenDarker)),
                  ]),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        if (product.needsSize && _selectedSize == null) {
                          showMotoGoToast(context, icon: '⚠️', title: t(context).tr('sizeLabel'), message: t(context).tr('selectSizeFirst'));
                          return;
                        }
                        final cartId = _selectedSize != null ? '${product.id}-$_selectedSize' : product.id;
                        final cartName = _selectedSize != null ? '${product.name} ($_selectedSize)' : product.name;
                        for (int i = 0; i < _qty; i++) {
                          ref.read(cartProvider.notifier).addItem(cartId, cartName, product.price);
                        }
                        ref.read(cartFabDismissedProvider.notifier).state = false;
                        showMotoGoToast(context, icon: '✓', title: t(context).tr('added'), message: '$_qty× $cartName');
                      },
                      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.add_shopping_cart, size: 16),
                        const SizedBox(width: 8),
                        Text(t(context).tr('addToCart')),
                      ]),
                    ),
                  ),
                ],

                SizedBox(height: MediaQuery.of(context).padding.bottom > 0 ? 4 : 12),
              ],
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
