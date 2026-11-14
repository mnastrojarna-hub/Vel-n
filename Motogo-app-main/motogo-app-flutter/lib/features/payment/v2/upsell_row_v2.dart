import 'package:flutter/material.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_chips.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/widgets/mg_photo.dart';
import '../../../core/v2/widgets/mg_skeleton.dart';
import '../../../core/v2/widgets/mg_emoji_map.dart' show mgStripEmoji;
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../shop/shop_models.dart';
import 'pay_parts_v2.dart' show PayCardV2;

/// v2 look of `UpsellSection` (PS-07, flag `reservation_upsell`): the old
/// card "Doporučujeme k rezervaci" with the featured products (max 3) ONE
/// UNDER ANOTHER, all visible and tappable at once (owner 2026-11-07 "jen
/// upgrade vzhledu"). Pure view —
/// selection, sizes, add / remove are the section's own callbacks with the
/// old tile's tap rules (row tap: chosen → remove, no size → add; size chip:
/// chosen → remove, else replace).
class UpsellRowV2 extends StatelessWidget {
  /// null = still loading.
  final List<Product>? products;
  final bool Function(String id) isSelected;
  final String? Function(String id) sizeOf;
  final void Function(Product product, String? size) onToggle;
  final void Function(Product product) onRemove;

  const UpsellRowV2({
    super.key,
    required this.products,
    required this.isSelected,
    required this.sizeOf,
    required this.onToggle,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final list = products;
    if (list != null && list.isEmpty) return const SizedBox.shrink();
    return PayCardV2(
      key: const ValueKey('upsell-v2'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          MgIcon(MgIcons.star, size: 18, color: MgColors.link),
          const SizedBox(width: 6),
          Expanded(child: Text(tr.tr('recommendForBooking'), style: MgType.title.copyWith(color: MgColors.ink))),
        ]),
        const SizedBox(height: MgSpace.s8),
        Text(tr.tr('upsellFromShop'), style: MgType.meta.copyWith(color: MgColors.meta)),
        const SizedBox(height: MgSpace.s8),
        if (list == null)
          const MgSkeletonRow(thumb: 56, lines: 2)
        else
          for (var i = 0; i < list.length; i++) ...[
            if (i > 0) const SizedBox(height: MgSpace.s8),
            _UpsellCardV2(
              key: ValueKey('upsell-v2-${list[i].id}'),
              product: list[i],
              selected: isSelected(list[i].id),
              size: sizeOf(list[i].id),
              onToggle: (s) => onToggle(list[i], s),
              onRemove: () => onRemove(list[i]),
            ),
          ],
      ]),
    );
  }
}

class _UpsellCardV2 extends StatelessWidget {
  final Product product;
  final bool selected;
  final String? size;
  final ValueChanged<String?> onToggle;
  final VoidCallback onRemove;

  const _UpsellCardV2({
    super.key,
    required this.product,
    required this.selected,
    required this.size,
    required this.onToggle,
    required this.onRemove,
  });

  /// The old tile's row tap.
  VoidCallback? get _rowTap => selected ? onRemove : (product.needsSize ? null : () => onToggle(null));

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final name = product.nameFor(tr.lang);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: selected ? MgColors.tintOk : MgColors.well,
        borderRadius: BorderRadius.circular(MgRadius.action),
        border: Border.all(color: selected ? MgColors.tintOkBorder : MgColors.line, width: selected ? 1.5 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MgPress(
          onTap: _rowTap,
          child: Row(children: [
            MgPhoto(
              url: product.displayImage,
              thumbWidth: 200,
              width: 56,
              height: 56,
              glyph: MgIcons.bag,
              borderRadius: BorderRadius.circular(MgRadius.action),
            ),
            const SizedBox(width: MgSpace.s10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                MgWordFit(
                  minScale: 0.85,
                  child: Text(name, style: MgType.body.copyWith(fontSize: 13, fontWeight: FontWeight.w800, color: MgColors.ink)),
                ),
                const SizedBox(height: 2),
                Text(Money.czk(product.price),
                    style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.price))),
              ]),
            ),
          ]),
        ),
        if (!product.needsSize || selected) ...[
          const SizedBox(height: MgSpace.s8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: MgPop(
              trigger: selected,
              child: MgFilterChip(
                key: ValueKey('upsell-v2-toggle-${product.id}'),
                label: selected ? mgStripEmoji(tr.tr('addedCheck')) : tr.tr('addLabel'),
                icon: selected ? MgIcons.check : MgIcons.plus,
                selected: selected,
                style: MgFilterChipStyle.tab,
                onTap: _rowTap,
              ),
            ),
          ),
        ],
        if (product.needsSize) ...[
          const SizedBox(height: MgSpace.s8),
          Text(tr.tr('sizeLabel'), style: MgType.meta.copyWith(color: MgColors.meta)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in product.sizes)
              MgChoiceChip(
                label: s,
                selected: size == s,
                onTap: () {
                  if (size == s) {
                    onRemove();
                  } else {
                    // The old tile: drop the previous size, then add the new one.
                    onRemove();
                    onToggle(s);
                  }
                },
              ),
          ]),
        ],
      ]),
    );
  }
}
