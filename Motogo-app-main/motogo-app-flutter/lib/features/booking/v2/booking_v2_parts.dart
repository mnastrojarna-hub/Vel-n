import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/calendar/trip_day_state.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_animated_size.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_text_fit.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';

/// "3 dny" in the app language.
String bkDays(AppTranslations tr, int n) => '$n ${tr.daysWord(n)}';

/// [text] that never breaks inside (no-break spaces) — dates, amounts.
String bkNb(String text) => text.replaceAll(' ', '\u00A0');

/// "pá 23. 10. – ne 25. 10." (single day = one date); wraps only between
/// the two dates.
String bkRange(AppTranslations tr, DateTime s, DateTime e) => tripSameDay(s, e)
    ? bkNb(tripShortDate(tr, s))
    : '${bkNb(tripShortDate(tr, s))} – ${bkNb(tripShortDate(tr, e))}';

/// Amounts in [text] never split ("1 000 CZK", "40 Kč/km"): no-break
/// spaces between digit groups and before the currency, a word joiner
/// after the "/" of a per-km rate.
String bkNbAmounts(String text) => text
    .replaceAllMapped(RegExp(r'(\d) (?=\d|Kč|CZK|€|EUR|zł|PLN|грн)'), (m) => '${m[1]}\u00A0')
    .replaceAll(RegExp(r'/(?=km|км)'), '/\u2060');

/// Width of the longest unbreakable run of [text] as this context draws
/// it (font, text scale): a column narrower than this splits a word.
double bkWordWidth(BuildContext context, String text, TextStyle style) => mgRunWidths(context, text, style).$1;

/// One-line width of [text] as this context draws it.
double bkLineWidth(BuildContext context, String text, TextStyle style) => mgRunWidths(context, text, style).$2;

/// Large text (system scale over 1.15): rows stack their side columns.
bool bkLargeText(BuildContext context) => MediaQuery.textScalerOf(context).scale(100) > 115;

/// Height change animated (sheet tempo); under reduced motion the child
/// is placed directly (a zero-length AnimatedSize may re-dirty itself
/// during layout).
Widget bkAnimatedSize(BuildContext context, Widget child) =>
    MgAnimatedSize(duration: MgMotion.sheet, curve: MgMotion.out, alignment: Alignment.topCenter, child: child);

/// Money in the chosen currency (the existing formatter).
String bkMoney(num czk) => Money.czk(czk);

/// White section card of the v2 booking form (V22 §2.4 Booking: light
/// cards on canvas): dark icon tile + 17/800 title (+ trailing), content.
class BkCard extends StatelessWidget {
  final String icon;
  final String title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry margin;

  const BkCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
    this.margin = const EdgeInsets.fromLTRB(16, 12, 16, 0),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(MgSpace.card),
      decoration: BoxDecoration(
        color: MgColors.surface,
        borderRadius: BorderRadius.circular(MgRadius.card),
        border: Border.all(color: MgColors.line),
        boxShadow: MgShadows.card,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          MgIconTileDark(icon, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: MgType.section.copyWith(color: MgColors.ink)),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ]),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }
}

/// Small caps label inside a card (`.lb4`).
class BkLabel extends StatelessWidget {
  final String text;
  const BkLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text.toUpperCase(),
            style: MgType.eyebrow.copyWith(color: MgColors.meta, fontSize: 11)),
      );
}

/// Days chip (ink pill, white tabular text) — bumps when the count changes.
class BkDaysChip extends StatelessWidget {
  final int days;
  const BkDaysChip(this.days, {super.key});

  @override
  Widget build(BuildContext context) => MgBump(
        trigger: days,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: MgColors.ink, borderRadius: BorderRadius.circular(999)),
          child: Text(bkDays(t(context), days),
              style: MgType.tab(MgType.meta.copyWith(color: MgColors.onDark))),
        ),
      );
}

/// "½" disc of the late-pickup offer (`.oh`): night disc, neon glyph.
class BkHalfDisc extends StatelessWidget {
  const BkHalfDisc({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        label: t(context).tr('v2BkHalfA11y'),
        child: ExcludeSemantics(
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: MgColors.panel, shape: BoxShape.circle),
            child: Text('½', style: MgType.micro.copyWith(fontWeight: FontWeight.w900, color: MgColors.neon)),
          ),
        ),
      );
}

/// Radio option row on light (handover choices): 44+ tall, ring → ink disc
/// with a neon ✓ when selected (never colour-only), title + sub + trailing
/// price. The price sits on the right only while the text column keeps
/// at least 140 dp and its longest word (and the price at most 35 % of the
/// row); on a narrow row or with large text it moves under the sub line.
/// [onTap] = the section's EXISTING option closure.
class BkOptionRow extends StatelessWidget {
  final String title;
  final String sub;
  final String trailing;
  final bool selected;
  final VoidCallback onTap;

  const BkOptionRow({
    super.key,
    required this.title,
    required this.sub,
    required this.trailing,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dur = MgMotion.of(context, MgMotion.color);
    final titleStyle = MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink, height: 1.3);
    final subStyle = MgType.small.copyWith(color: MgColors.lead);
    final priceStyle =
        MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: selected ? MgColors.link : MgColors.meta));
    final subText = bkNbAmounts(sub);
    final priceText = bkNbAmounts(trailing);
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: '$title, $sub, $trailing',
      excludeSemantics: true,
      onTap: onTap,
      child: MgPress(
        onTap: onTap,
        child: AnimatedContainer(
          duration: dur,
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? MgColors.surface : MgColors.well,
            borderRadius: BorderRadius.circular(MgRadius.button),
            border: Border.all(color: selected ? MgColors.ink : MgColors.line, width: selected ? 1.5 : 1),
          ),
          child: LayoutBuilder(builder: (context, c) {
            final row = c.maxWidth;
            final priceMax = row * 0.35;
            final need = math.max(
                140.0, math.max(bkWordWidth(context, title, titleStyle), bkWordWidth(context, subText, subStyle)));
            final side = row >= 300 &&
                !bkLargeText(context) &&
                bkWordWidth(context, priceText, priceStyle) <= priceMax &&
                row - 36 - 8 - math.min(bkLineWidth(context, priceText, priceStyle), priceMax) >= need;
            final price = MgWordFit(
              alignment: side ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
              child: Text(priceText, maxLines: 2, textAlign: side ? TextAlign.end : TextAlign.start, style: priceStyle),
            );
            return Row(children: [
              AnimatedContainer(
                duration: dur,
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? MgColors.ink : MgColors.surface,
                  border: Border.all(color: selected ? MgColors.ink : MgColors.lineInput, width: 1.5),
                ),
                child: selected
                    ? MgPop(trigger: selected, child: Center(child: MgIcon(MgIcons.check, size: 15, color: MgColors.neon, stroke: 2.6)))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  MgWordFit(child: Text(title, style: titleStyle)),
                  const SizedBox(height: 2),
                  MgWordFit(child: Text(subText, style: subStyle)),
                  if (!side) ...[const SizedBox(height: 4), price],
                ]),
              ),
              if (side) ...[
                const SizedBox(width: 8),
                ConstrainedBox(constraints: BoxConstraints(maxWidth: priceMax), child: price),
              ],
            ]);
          }),
        ),
      ),
    );
  }
}

/// Size / time chip (`.ch2`): well → selected = ink + neon text + ✓ pop.
class BkSizeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? semanticLabel;

  const BkSizeChip({super.key, required this.label, required this.selected, required this.onTap, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      onTap: onTap,
      child: MgPress(
        onTap: onTap,
        child: AnimatedContainer(
          duration: MgMotion.of(context, MgMotion.color),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? MgColors.ink : MgColors.well,
            borderRadius: BorderRadius.circular(MgRadius.action),
            border: Border.all(color: selected ? MgColors.ink : MgColors.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            if (selected) ...[
              MgPop(trigger: selected, child: MgIcon(MgIcons.check, size: 14, color: MgColors.neon, stroke: 2.6)),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: MgType.tab(MgType.small.copyWith(
                    fontWeight: FontWeight.w800, color: selected ? MgColors.neon : MgColors.ink))),
          ]),
        ),
      ),
    );
  }
}
