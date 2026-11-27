import 'package:flutter/material.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_skeleton.dart';
import '../../catalog/v2/bike_screen_card_parts_v2.dart' show BikeCardSpecChip;
import '../../catalog/v2/catalog_price.dart' show CatCardPrice;
import '../shop_models.dart';

// Pieces of the full-screen product card (`ProductCardFullV2`) and of the
// product photo hero, split out so the files stay under the size rule.

/// The card price in the bike card's words (`BikeCardPriceBlock`): "CENA",
/// the amount, "Skladem" / "Vyprodáno" under it. Display only.
CatCardPrice productCardPrice(AppTranslations tr, Product p) => CatCardPrice(
      label: tr.tr('shopListPrice'),
      value: Money.czk(p.price),
      sub: tr.tr(p.inStock ? 'shopListInStock' : 'soldOut'),
      grid: '',
    );

/// "2 / 6" — which product of the list is on screen (dark pill, as the
/// bike detail's pager). Hidden for a single product.
class ShopPosPillV2 extends StatelessWidget {
  final int index;
  final int total;
  const ShopPosPillV2({super.key, required this.index, required this.total});

  @override
  Widget build(BuildContext context) => Semantics(
        label: t(context).trArgs('shopListPosAria', {'n': index + 1, 'total': total}),
        excludeSemantics: true,
        child: ShopDarkPillV2(text: '${index + 1} / $total'),
      );
}

/// Dark pill over a photo (`.8` night + white ring): position, photo
/// counter, "● Skladem".
class ShopDarkPillV2 extends StatelessWidget {
  final String text;
  final String? icon;

  /// A neon dot before the text (in stock).
  final bool dot;
  const ShopDarkPillV2({super.key, required this.text, this.icon, this.dot = false});

  @override
  Widget build(BuildContext context) => Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: MgColors.nightA(0.8),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: MgColors.white(0.22)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot) ...[
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: MgColors.neon, shape: BoxShape.circle)),
            const SizedBox(width: 7),
          ],
          if (icon != null) ...[MgIcon(icon!, size: 15, color: MgColors.neon), const SizedBox(width: 6)],
          Text(text,
              style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark, height: 1))),
        ]),
      );
}

/// Photo segments of a product with several photos (the bike card's bars).
class ShopPhotoSegmentsV2 extends StatelessWidget {
  final int count;
  final int index;
  const ShopPhotoSegmentsV2({super.key, required this.count, required this.index});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Row(children: [
          for (var i = 0; i < count; i++)
            Expanded(
              child: Container(
                height: 3,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: i == index ? MgColors.onDark : MgColors.white(0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ]),
      );
}

/// "Velikost  S  M  L  XL" — the sizes the product is sold in (a hint; the
/// size is picked on the product page).
class ProductSizeChipsV2 extends StatelessWidget {
  final List<String> sizes;
  const ProductSizeChipsV2({super.key, required this.sizes});

  @override
  Widget build(BuildContext context) {
    final label = t(context).tr('sizeLabel');
    return Semantics(
      label: '$label: ${sizes.join(', ')}',
      excludeSemantics: true,
      child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Text(label, style: MgType.meta.copyWith(color: MgColors.onDarkMeta)),
        ),
        for (final s in sizes) BikeCardSpecChip(s),
      ]),
    );
  }
}

/// The product list while it loads: night skeletons in the final card
/// geometry (one product per screen) — no jump when the cards arrive.
class ShopListSkeletonV2 extends StatelessWidget {
  final double cardHeight;
  const ShopListSkeletonV2({super.key, required this.cardHeight});

  /// Text + pills + CTA block under the photo band.
  static const double body = 160;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < 2; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ColoredBox(
              color: MgColors.night,
              child: MgSkeletonPhotoCard(
                photoHeight: cardHeight - body,
                dark: true,
                radius: 0,
                pills: const [72, 40, 40, 40],
                ctaHeight: 52,
              ),
            ),
          ),
      ]);
}
