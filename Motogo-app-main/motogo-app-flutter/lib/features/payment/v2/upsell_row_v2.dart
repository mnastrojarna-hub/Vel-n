import 'package:flutter/material.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/gestures/mg_snap_physics.dart';
import '../../../core/v2/icons/mg_icons.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_chips.dart';
import '../../../core/v2/widgets/mg_disclosure.dart';
import '../../../core/v2/widgets/mg_photo.dart';
import '../../../core/v2/widgets/mg_skeleton.dart';
import '../../../core/v2/widgets/mg_emoji_map.dart' show mgStripEmoji;
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../shop/shop_models.dart';
import 'pay_parts_v2.dart' show PayCardV2;

/// v2 look of `UpsellSection` (PS-07, flag `reservation_upsell`): an
/// optional extra → a collapsed card "Doporučujeme k rezervaci ▾" (opens by
/// itself when something is already chosen); inside a row of product cards
/// that snaps to whole cards with a 24 px peek of the next one. Pure view —
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

  static const double peek = 24;

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final list = products;
    if (list != null && list.isEmpty) return const SizedBox.shrink();
    final chosen = list?.where((p) => isSelected(p.id)).length ?? 0;
    return PayCardV2(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: MgDisclosure(
        key: const ValueKey('upsell-v2'),
        label: tr.tr('v2UxPsUpsellTitle'),
        initiallyExpanded: chosen > 0,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr.tr('upsellFromShop'), style: MgType.meta.copyWith(color: MgColors.meta)),
            const SizedBox(height: MgSpace.s8),
            LayoutBuilder(builder: (context, c) {
              final w = c.maxWidth;
              // One whole card + 24 px of the next (a single product = full width).
              final item = list != null && list.length == 1 ? w : w - peek - MgSpace.s12;
              if (list == null) return const MgSkeletonRow(thumb: 56, lines: 2);
              return SingleChildScrollView(
                key: const ValueKey('upsell-v2-row'),
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                physics: MgSnapScrollPhysics(itemExtent: item + MgSpace.s12),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (var i = 0; i < list.length; i++) ...[
                    if (i > 0) const SizedBox(width: MgSpace.s12),
                    SizedBox(
                      width: item,
                      child: _UpsellCardV2(
                        product: list[i],
                        selected: isSelected(list[i].id),
                        size: sizeOf(list[i].id),
                        onToggle: (s) => onToggle(list[i], s),
                        onRemove: () => onRemove(list[i]),
                      ),
                    ),
                  ],
                ]),
              );
            }),
          ]),
        ),
      ),
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
