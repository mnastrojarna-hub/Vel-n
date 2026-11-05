import 'package:flutter/material.dart';

import '../icons/mg_icon.dart';
import '../motion/mg_anim.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_space.dart';
import '../tokens/mg_type.dart';

/// Stat tile: value 18/900 tabular + label 11.5/700. Light = well tile,
/// dark = white .06 glass. Optional icon and tap.
class MgStatTile extends StatelessWidget {
  final String value;
  final String label;
  final String? icon;
  final bool dark;
  final VoidCallback? onTap;
  const MgStatTile({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.dark = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dark ? MgColors.white(0.06) : MgColors.well,
        borderRadius: BorderRadius.circular(MgRadius.action),
        border: Border.all(color: dark ? MgColors.white(0.10) : MgColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          MgIcon(icon!, size: 20, color: dark ? MgColors.neon : MgColors.link),
          const SizedBox(height: MgSpace.s6),
        ],
        Text(value,
            style: MgType.tab(MgType.h3.copyWith(
                fontSize: 18, fontWeight: FontWeight.w900, color: dark ? MgColors.onDark : MgColors.ink))),
        const SizedBox(height: 2),
        Text(label, style: MgType.meta.copyWith(color: dark ? MgColors.onDarkMeta : MgColors.meta)),
      ]),
    );
    if (onTap == null) return MergeSemantics(child: tile);
    return Semantics(
      button: true,
      label: '$value, $label',
      excludeSemantics: true,
      onTap: onTap,
      child: MgPress(onTap: onTap, child: tile),
    );
  }
}
