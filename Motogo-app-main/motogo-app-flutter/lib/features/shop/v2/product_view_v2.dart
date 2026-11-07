import 'package:flutter/material.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_dock.dart';
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/chrome/mg_status_bar.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_chips.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_photo.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../shop_models.dart';
import 'product_desc_v2.dart';
import 'qty_stepper_v2.dart';

/// v2 look of the product page (Profil board S11 product sheet, kept as
/// the existing route — OD-PS-09): a scrolling page with the 4:3 photo
/// pager (swipe = next photo, dots, photo-style ‹ = the screen's back),
/// name + price, colour / material tiles, description (3 lines + "Více"),
/// size chips ≥ 44, the inline "Nejdřív vyber velikost" where the old
/// toast fired ([sizeHint] — the screen's flag), the 44 px stepper and the
/// dock "PŘIDAT DO KOŠÍKU · {total}" running the screen's own add action.
class ProductViewV2 extends StatelessWidget {
  final Product product;
  final int imageIndex;
  final ValueChanged<int> onPage;
  final String? selectedSize;
  final ValueChanged<String> onSize;
  final bool sizeHint;
  final int qty;
  final VoidCallback? onMinus;
  final VoidCallback onPlus;
  final VoidCallback onAdd;
  final VoidCallback onBack;

  const ProductViewV2({
    super.key,
    required this.product,
    required this.imageIndex,
    required this.onPage,
    required this.selectedSize,
    required this.onSize,
    required this.sizeHint,
    required this.qty,
    required this.onMinus,
    required this.onPlus,
    required this.onAdd,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final lang = tr.lang;
    final images = product.images.isNotEmpty ? product.images : [product.displayImage];
    final top = MediaQuery.paddingOf(context).top;
    final photo = MgStatusBar(
      dark: true,
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Stack(fit: StackFit.expand, children: [
          ColoredBox(
            color: MgColors.well,
            child: PageView.builder(
              itemCount: images.length,
              onPageChanged: onPage,
              itemBuilder: (_, i) => MgPhoto(url: images[i], thumbWidth: 1000, glyph: MgIcons.bag),
            ),
          ),
          Positioned(top: top + 8, left: 16, child: MgV2Back(onTap: onBack, style: MgBackStyle.photo)),
          if (images.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Semantics(
                label: tr.trArgs('v2UxCorePhotoOf', {'n': imageIndex + 1, 'm': images.length}),
                excludeSemantics: true,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < images.length; i++)
                    AnimatedContainer(
                      duration: MgMotion.of(context, MgMotion.color),
                      width: i == imageIndex ? 18 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i == imageIndex ? MgColors.neon : MgColors.white(0.6),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ]),
              ),
            ),
        ]),
      ),
    );
    final color = product.colorFor(lang);
    final material = product.materialFor(lang);
    final desc = product.descriptionFor(lang);
    Widget tile(String label, String value) => Expanded(
          child: MgWell(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label.toUpperCase(), style: MgType.eyebrow.copyWith(color: MgColors.meta)),
              const SizedBox(height: 2),
              Text(value, style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.ink)),
            ]),
          ),
        );
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(MgSpace.gutter, MgSpace.s16, MgSpace.gutter, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          header: true,
          child: MgWordFit(minScale: 0.8, child: Text(product.nameFor(lang), style: MgType.h3.copyWith(color: MgColors.ink))),
        ),
        const SizedBox(height: 4),
        Text(Money.czk(product.price), style: MgType.tab(MgType.h3.copyWith(color: MgColors.price))),
        if (color != null || material != null) ...[
          const SizedBox(height: MgSpace.s16),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (color != null) tile(tr.tr('sdColor'), color),
              if (color != null && material != null) const SizedBox(width: MgSpace.s8),
              if (material != null) tile(tr.tr('material'), material),
            ]),
          ),
        ],
        if (desc != null) ...[const SizedBox(height: MgSpace.s12), ProductDescV2(text: desc)],
        if (product.needsSize) ...[
          const SizedBox(height: MgSpace.s16),
          Text(tr.tr('sizeLabel'), style: MgType.title.copyWith(color: MgColors.ink)),
          const SizedBox(height: MgSpace.s8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in product.sizes)
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 52),
                child: MgChoiceChip(label: s, selected: selectedSize == s, onTap: () => onSize(s)),
              ),
          ]),
          if (sizeHint && selectedSize == null) ...[
            const SizedBox(height: MgSpace.s10),
            MgEnter(
              child: MgStateBanner(key: const ValueKey('shop-v2-size-hint'), tone: MgTone.warn, title: tr.tr('v2UxPsPickSize')),
            ),
          ],
        ],
        if (!product.inStock) ...[
          const SizedBox(height: MgSpace.s16),
          MgStateBanner(tone: MgTone.err, icon: MgIcons.ban, title: tr.tr('soldOut')),
        ],
        if (product.inStock) ...[
          const SizedBox(height: MgSpace.s16),
          Row(children: [
            Flexible(child: MgWordFit(minScale: 0.8, child: Text(tr.tr('quantityLabel'), style: MgType.title.copyWith(color: MgColors.ink)))),
            const SizedBox(width: MgSpace.s12),
            QtyStepperV2(qty: qty, onMinus: onMinus, onPlus: onPlus),
            const SizedBox(width: MgSpace.s8),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: MgBump(
                    trigger: qty,
                    child: Text(Money.czk(product.price * qty), style: MgType.tab(MgType.title.copyWith(color: MgColors.price))),
                  ),
                ),
              ),
            ),
          ]),
        ],
      ]),
    );
    return MgPage(
      sections: [photo, body],
      overlapHero: false,
      pinnedBack: onBack,
      pinnedTitle: product.nameFor(lang),
      dock: product.inStock
          ? MgDock(
              child: MgCta(
                key: const ValueKey('shop-v2-add'),
                label: tr.tr('addToCart'),
                price: Money.czk(product.price * qty).replaceAll(' ', '\u00A0'),
                leadingIcon: MgIcons.bag,
                onTap: onAdd,
                size: MgCtaSize.md56,
              ),
            )
          : null,
    );
  }
}
