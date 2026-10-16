import 'package:flutter/material.dart';

import '../../i18n/i18n_provider.dart';
import '../icons/mg_icon.dart';
import '../motion/mg_anim.dart';
import '../motion/mg_motion.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_shadows.dart';
import '../tokens/mg_space.dart';
import '../tokens/mg_type.dart';

/// Price block: "Tvoje cena" label + value (neon on dark / `#0D6E0D` on
/// light) + struck list price + optional delta chip. Values come formatted
/// from the caller (existing `Money` / price helpers) — never computed here.
class MgPrice extends StatelessWidget {
  final String value;
  final String? label;
  final String? struck;
  final String? suffix;
  final Widget? chip;
  final bool dark;
  final bool large;
  const MgPrice({
    super.key,
    required this.value,
    this.label,
    this.struck,
    this.suffix,
    this.chip,
    this.dark = false,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final valueStyle = MgType.tab((large ? MgType.h2 : MgType.section)
        .copyWith(fontWeight: FontWeight.w900, color: dark ? MgColors.neon : MgColors.price));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (label != null)
        Text(label!, style: MgType.meta.copyWith(color: dark ? MgColors.onDarkMeta : MgColors.meta)),
      Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 8, runSpacing: 4, children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: value, style: valueStyle),
          if (suffix != null)
            TextSpan(
              text: ' $suffix',
              style: MgType.small.copyWith(color: dark ? MgColors.onDarkSecondary : MgColors.lead),
            ),
        ])),
        if (struck != null)
          Text(struck!,
              style: MgType.tab(MgType.small.copyWith(
                decoration: TextDecoration.lineThrough,
                color: dark ? MgColors.white(0.5) : MgColors.meta,
              ))),
        if (chip != null) chip!,
      ]),
    ]);
  }
}

/// Dark total box (`gDarkCta`, r14): "TVOJE CENA · n dny" eyebrow, value
/// 32/900 neon (bumps when it changes), avg / day line, rank savings chip,
/// "Rozpis ▾" toggle owned by the caller.
class MgTotalBox extends StatelessWidget {
  final String eyebrow;
  final String value;
  final String? sub;
  final Widget? savingsChip;
  final VoidCallback? onBreakdown;
  final bool breakdownOpen;
  final Widget? breakdown;
  final Widget? trailing;

  const MgTotalBox({
    super.key,
    required this.eyebrow,
    required this.value,
    this.sub,
    this.savingsChip,
    this.onBreakdown,
    this.breakdownOpen = false,
    this.breakdown,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Container(
      padding: const EdgeInsets.all(MgSpace.card),
      decoration: BoxDecoration(
        gradient: MgGradients.darkCta,
        borderRadius: BorderRadius.circular(MgRadius.button),
        border: Border.all(color: MgColors.neonA(0.25)),
        boxShadow: MgShadows.dark,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(eyebrow.toUpperCase(), style: MgType.eyebrow.copyWith(color: MgColors.neonText)),
              const SizedBox(height: 6),
              MgBump(
                trigger: value,
                child: Text(value,
                    style: MgType.tab(MgType.display.copyWith(
                      color: MgColors.neon,
                      shadows: [Shadow(color: MgColors.neonA(0.35), blurRadius: 18)],
                    ))),
              ),
              if (sub != null) ...[
                const SizedBox(height: 4),
                Text(sub!, style: MgType.small.copyWith(color: MgColors.onDarkLead)),
              ],
            ]),
          ),
          if (trailing != null) trailing!,
        ]),
        if (savingsChip != null || onBreakdown != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: savingsChip ?? const SizedBox.shrink(),
              ),
            ),
            if (onBreakdown != null)
              Semantics(
                button: true,
                expanded: breakdownOpen,
                child: InkWell(
                  onTap: onBreakdown,
                  borderRadius: BorderRadius.circular(MgRadius.action),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(tr.tr('v2Breakdown'),
                            style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.neonText)),
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: breakdownOpen ? 0.5 : 0,
                          duration: MgMotion.of(context, MgMotion.color),
                          child: MgIcon(MgIcons.chevronDown, size: 16, color: MgColors.neonText),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ],
        if (breakdown != null)
          AnimatedSize(
            duration: MgMotion.of(context, MgMotion.sheet),
            alignment: Alignment.topCenter,
            child: breakdownOpen
                ? Padding(padding: const EdgeInsets.only(top: 10), child: breakdown)
                : const SizedBox(width: double.infinity),
          ),
      ]),
    );
  }
}
