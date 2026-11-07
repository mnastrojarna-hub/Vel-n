import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/motion/mg_motion.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_space.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_word_fit.dart';
import '../../booking_models.dart';
import '../booking_v2_parts.dart';

/// Sub line of an extra row — the old tile's rule: chosen size, a missing
/// size prompt, else the description (boots: informal copy).
String? bkExtraSub(AppTranslations tr, ExtraCatalogItem item, {String? size, required bool needSize}) {
  if (size != null) return '${tr.tr('sizeLabel')}: ${extraSizeLabel(tr.tr, size)}';
  if (needSize) return tr.tr('v2BkPickSize');
  if (extraDescKeys[item.id] == 'extraBootsDesc') return tr.tr('v2BkBootsDesc');
  return extraDescription(tr.tr, item.id, item.description);
}

/// Size row of the basic free gear (v2 look of `bookingGearRow`): label +
/// size chips; tapping the chosen size clears it — exactly the old row's
/// `onChanged(a ? null : s)`.
class BookingGearRowV2 extends StatelessWidget {
  final String label;
  final String? selected;
  final ValueChanged<String?> onChanged;
  final List<String> sizes;

  const BookingGearRowV2({
    super.key,
    required this.label,
    required this.selected,
    required this.onChanged,
    required this.sizes,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink))),
          if (selected != null)
            Text(selected!, style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.link))),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in sizes)
            BkSizeChip(
              label: s,
              selected: selected == s,
              semanticLabel: tr.trArgs('v2BkSizeA11y', {'item': label, 'size': s}),
              onTap: () => onChanged(selected == s ? null : s),
            ),
        ]),
      ]),
    );
  }
}

/// One extra (v2 look of the old extras tile): check box, icon, name, sub
/// (size / "Vyber velikost" / description), price or "Zdarma" (+ struck
/// list price when the rank made it free). [onTap] = the section's EXISTING
/// tap closure (remove, passenger sheet, size dialog or add).
/// [opensSheet] = an extra with sizes (passenger, boots): once chosen, a
/// tap opens its sizes sheet ("Odebrat" inside) — no toggle, so screen
/// readers hear "selected" + the change / remove hint instead of "checked".
///
/// Layout never squeezes the text column under its longest word: the
/// price column sits on the right only when the text keeps that width;
/// otherwise it moves under the text (rank badge, struck, price in one
/// wrap). A narrow row (< 300 dp) or large text also drops the icon.
class BookingExtraRowV2 extends StatelessWidget {
  final String icon;
  final String title;
  final String? sub;
  final bool needSize;
  final String price;
  final String? struck;
  final bool freeWithRank;
  final bool selected;
  final bool opensSheet;
  final VoidCallback onTap;

  const BookingExtraRowV2({
    super.key,
    required this.icon,
    required this.title,
    required this.sub,
    required this.needSize,
    required this.price,
    required this.selected,
    required this.onTap,
    this.struck,
    this.freeWithRank = false,
    this.opensSheet = false,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final dur = MgMotion.of(context, MgMotion.color);
    final subText = sub == null || sub!.isEmpty ? null : sub!;
    final titleStyle = MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink, height: 1.3);
    final subStyle = MgType.small
        .copyWith(fontWeight: needSize ? FontWeight.w800 : FontWeight.w600, color: needSize ? MgColors.warn : MgColors.lead);
    final badgeText = tr.tr('v2BkFreeWithRank');
    final badgeStyle = MgType.micro.copyWith(fontWeight: FontWeight.w800, color: MgColors.onTintOk);
    final struckStyle = MgType.tab(
        MgType.meta.copyWith(color: MgColors.meta, decoration: TextDecoration.lineThrough, decorationColor: MgColors.meta));
    final priceStyle = MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.price));
    final struckText = struck == null ? null : bkNbAmounts(struck!);
    final priceText = bkNbAmounts(price);
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: MgColors.tintOk,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: MgColors.tintOkBorder),
      ),
      child: MgWordFit(fitLines: 1, child: Text(badgeText, style: badgeStyle)),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        checked: opensSheet && selected ? null : selected,
        selected: opensSheet && selected ? true : null,
        hint: opensSheet && selected ? '${tr.tr('v2BkChange')}, ${tr.tr('removeBtn')}' : null,
        label: [title, if (subText != null) subText, price].join(', '),
        excludeSemantics: true,
        onTap: onTap,
        child: MgPress(
          onTap: onTap,
          child: AnimatedContainer(
            duration: dur,
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: MgColors.surface,
              borderRadius: BorderRadius.circular(MgRadius.button),
              border: Border.all(
                color: needSize ? MgColors.warnBorder : (selected ? MgColors.tintOkBorder : MgColors.line),
                width: selected || needSize ? 1.5 : 1,
              ),
            ),
            child: LayoutBuilder(builder: (context, c) {
              final row = c.maxWidth;
              final compact = row < 300 || bkLargeText(context);
              var need = math.max(120.0, bkWordWidth(context, title, titleStyle));
              if (subText != null) need = math.max(need, bkWordWidth(context, subText, subStyle) + (needSize ? 18 : 0));
              if (freeWithRank) need = math.max(need, bkWordWidth(context, badgeText, badgeStyle) + 18);
              final priceW = math.max(bkLineWidth(context, priceText, priceStyle),
                  struckText == null ? 0.0 : bkLineWidth(context, struckText, struckStyle));
              final side = !compact && row - 34 - 30 - 8 - priceW >= need;
              return Row(children: [
                AnimatedContainer(
                  duration: dur,
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: selected ? MgColors.neon : MgColors.surface,
                    borderRadius: BorderRadius.circular(MgRadius.tag),
                    border: Border.all(color: selected ? MgColors.neonLo : MgColors.lineInput, width: 1.5),
                  ),
                  child: selected
                      ? MgPop(trigger: selected, child: Center(child: MgIcon(MgIcons.check, size: 15, color: MgColors.onNeon, stroke: 2.6)))
                      : null,
                ),
                const SizedBox(width: 10),
                if (!compact) ...[MgIcon(icon, size: 20, color: MgColors.link), const SizedBox(width: 10)],
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    MgWordFit(child: Text(title, style: titleStyle)),
                    if (subText != null) ...[
                      const SizedBox(height: 2),
                      Row(children: [
                        if (needSize) ...[MgIcon(MgIcons.warn, size: 14, color: MgColors.warn), const SizedBox(width: 4)],
                        Flexible(child: MgWordFit(child: Text(subText, style: subStyle))),
                      ]),
                    ],
                    if (side && freeWithRank) ...[const SizedBox(height: 4), badge],
                    if (!side) ...[
                      const SizedBox(height: 4),
                      Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        if (freeWithRank) badge,
                        if (struckText != null) Text(struckText, style: struckStyle),
                        Text(priceText, style: priceStyle),
                      ]),
                    ],
                  ]),
                ),
                if (side) ...[
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    if (struckText != null) Text(struckText, style: struckStyle),
                    Text(priceText, style: priceStyle),
                  ]),
                ],
              ]);
            }),
          ),
        ),
      ),
    );
  }
}
