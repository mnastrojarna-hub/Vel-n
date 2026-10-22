import 'package:flutter/material.dart';

import '../tokens/mg_colors.dart';
import '../tokens/mg_space.dart';
import '../tokens/mg_type.dart';
import '../chrome/mg_fab_avoid.dart';
import '../icons/mg_icon.dart';
import '../motion/mg_anim.dart';
import 'mg_icon_tile.dart';
import 'mg_word_fit.dart';

/// Section header on a light page: optional dark eyebrow pill + title
/// 17/800 (wraps, never ellipsizes) + optional trailing text action.
class MgSectionHeader extends StatelessWidget {
  final String title;
  final String? eyebrow;
  final String? eyebrowIcon;
  final String? trailingLabel;
  final VoidCallback? onTrailing;
  final bool dark;
  final EdgeInsetsGeometry padding;

  const MgSectionHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.eyebrowIcon,
    this.trailingLabel,
    this.onTrailing,
    this.dark = false,
    this.padding = const EdgeInsets.fromLTRB(MgSpace.gutter, 0, MgSpace.gutter, MgSpace.s12),
  });

  @override
  Widget build(BuildContext context) {
    final heading = Semantics(
      header: true,
      // Titul se nikdy nedělí uprostřed slova („Des itinéraires…").
      child: MgWordFit(
        minScale: 0.8,
        child: Text(title, style: MgType.section.copyWith(color: dark ? MgColors.onDark : MgColors.ink)),
      ),
    );
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (eyebrow != null) ...[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: dark ? MgEyebrow(eyebrow!) : MgEyebrowDark(eyebrow!, icon: eyebrowIcon),
            ),
            const SizedBox(height: 8),
          ],
          // „Vše ›" na ose titulku (ne výš) a se šipkou — jako HomeTextLink.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: heading),
              if (trailingLabel != null) ...[
                const SizedBox(width: 8),
                MgTextLink(label: trailingLabel!, onTap: onTrailing, dark: dark),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Text link with a trailing chevron ("Vše ›") — the one style for every
/// "see all" on v2 pages (44 px hit area).
class MgTextLink extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool dark;
  const MgTextLink({super.key, required this.label, required this.onTap, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final c = dark ? MgColors.neonText : MgColors.link;
    // Vpravo zarovnaný odkaz = tap zóna (AI tlačítko nad ním jen nakoukne).
    return MgFabAvoid(kind: MgAvoidKind.tap, child: Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: MgPress(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text(label, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: c))),
              const SizedBox(width: 2),
              MgIcon(MgIcons.chevronRight, size: 16, color: c),
            ]),
          ),
        ),
      ),
    ));
  }
}
