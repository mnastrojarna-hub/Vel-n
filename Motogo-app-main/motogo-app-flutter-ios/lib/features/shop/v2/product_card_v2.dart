import 'package:flutter/material.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_chips.dart';
import '../../../core/v2/widgets/mg_photo.dart';
import '../../../core/v2/widgets/mg_skeleton.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../shop_models.dart';

/// Product card of the v2 shop grid (Profil board S11): white r16 + line,
/// photo inset 8 in a fixed square box (`MgPhoto`: thumb, well
/// placeholder, fade), "Vyprodáno" tag on the photo, name 13/800 (wraps,
/// never cut mid-word), price 12.5/800 green. Tap = the screen's own
/// product route (press .97 + selection haptic).
class ProductCardV2 extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  const ProductCardV2({super.key, required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final name = product.nameFor(tr.lang);
    final price = Money.czk(product.price);
    return Semantics(
      button: true,
      label: '$name, $price${product.inStock ? '' : ', ${tr.tr('soldOut')}'}',
      excludeSemantics: true,
      onTap: onTap,
      child: MgPress(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: MgColors.surface,
            borderRadius: BorderRadius.circular(MgRadius.card),
            border: Border.all(color: MgColors.line),
            boxShadow: MgShadows.card,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Stack(children: [
              MgPhoto(
                url: product.displayImage,
                thumbWidth: 500,
                aspectRatio: 1,
                glyph: MgIcons.bag,
                borderRadius: BorderRadius.circular(MgRadius.action),
              ),
              if (!product.inStock)
                Positioned(
                  left: 8,
                  top: 8,
                  child: MgTag(tr.tr('soldOut'), background: MgColors.errBg, foreground: MgColors.err),
                ),
            ]),
            const SizedBox(height: MgSpace.s8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: MgWordFit(minScale: 0.85, child: Text(name, style: MgType.body.copyWith(fontSize: 13, fontWeight: FontWeight.w800, color: MgColors.ink))),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 4, 2, 2),
              child: Text(price, style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.price))),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Two cards per row with the same height (the taller name wins), 12 px
/// gaps — no fixed cell height, so a long name or large text never clips.
class ProductRowV2 extends StatelessWidget {
  final Widget left;
  final Widget? right;
  const ProductRowV2({super.key, required this.left, this.right});

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: left),
          const SizedBox(width: MgSpace.s12),
          Expanded(child: right ?? const SizedBox.shrink()),
        ]),
      );
}

/// Loading grid in the final card geometry (2 × 2).
class ProductGridSkeletonV2 extends StatelessWidget {
  const ProductGridSkeletonV2({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - MgSpace.s12) / 2;
        Widget card() => MgSkeletonPhotoCard(photoHeight: w - 16, lines: 2);
        return Column(children: [
          for (var i = 0; i < 2; i++) ...[
            if (i > 0) const SizedBox(height: MgSpace.s12),
            Row(children: [
              Expanded(child: card()),
              const SizedBox(width: MgSpace.s12),
              Expanded(child: card()),
            ]),
          ],
        ]);
      });
}
