import 'package:flutter/material.dart';

import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_text_fit.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';

/// v2 look of the address picker's place option ("Na pobočce" /
/// "Přistavení na tvoji adresu"): an MgChoiceCard-style row — title 15/800,
/// sub (branch / fee rule), price right (under the text when a word would
/// break beside it), ink ✓ disc when chosen. Same [onTap] as the old radio.
class AddressOptionV2 extends StatelessWidget {
  final String label;
  final String sublabel;
  final String price;
  final bool selected;
  final VoidCallback onTap;
  const AddressOptionV2({
    super.key,
    required this.label,
    required this.sublabel,
    required this.price,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = MgType.body.copyWith(fontWeight: FontWeight.w800, color: selected ? MgColors.onTintOk : MgColors.ink);
    final sub = MgType.small.copyWith(color: MgColors.meta);
    final priceSt = MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.link));
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $sublabel, $price',
      excludeSemantics: true,
      onTap: onTap,
      child: MgPress(
        onTap: onTap,
        child: AnimatedContainer(
          duration: MgMotion.of(context, MgMotion.color),
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? MgColors.tintOk : MgColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? MgColors.tintOkBorder : MgColors.line, width: selected ? 1.5 : 1),
          ),
          child: LayoutBuilder(builder: (context, c) {
            // Price beside the text while no word of it would break.
            final room = c.maxWidth - 24 - 12 - 12 - mgLineWidth(context, price, priceSt);
            final side = !c.hasBoundedWidth ||
                (mgWordsFit(context, label, title, room) && mgWordsFit(context, sublabel, sub, room));
            return Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  MgWordFit(child: Text(label, style: title)),
                  const SizedBox(height: 2),
                  MgWordFit(child: Text(sublabel, style: sub)),
                  if (!side) ...[const SizedBox(height: 2), Text(price, style: priceSt)],
                ]),
              ),
              if (side) ...[const SizedBox(width: 12), Text(price, style: priceSt)],
              const SizedBox(width: 12),
              SizedBox(
                width: 24,
                height: 24,
                child: selected
                    ? Container(
                        decoration: const BoxDecoration(color: MgColors.ink, shape: BoxShape.circle),
                        child: const Center(child: MgIcon(MgIcons.check, size: 15, color: MgColors.onDark, stroke: 2.6)),
                      )
                    : Container(
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: MgColors.lineInput, width: 1.5)),
                      ),
              ),
            ]);
          }),
        ),
      ),
    );
  }
}
