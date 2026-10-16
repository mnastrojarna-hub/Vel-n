import 'package:flutter/material.dart';

import '../icons/mg_icon.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_shadows.dart';
import '../tokens/mg_type.dart';
import 'mg_word_fit.dart';

/// Section-leading feature icon on light: 40 px (rows 36) r12 `#0E2A1C`
/// tile with a neon icon (11.55 : 1).
class MgIconTileDark extends StatelessWidget {
  final String icon;
  final double size;
  const MgIconTileDark(this.icon, {super.key, this.size = 40});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: MgColors.panel,
          borderRadius: BorderRadius.circular(12),
          boxShadow: MgShadows.icon,
        ),
        child: Center(child: MgIcon(icon, size: size * 0.5, color: MgColors.neon)),
      );
}

/// List-row icon on light: 36 px r10 well tile, `#0D6E0D` icon (6.45 : 1).
class MgIconTileLight extends StatelessWidget {
  final String icon;
  final double size;
  final Color? color;
  const MgIconTileLight(this.icon, {super.key, this.size = 36, this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: MgColors.well,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: MgColors.line),
        ),
        child: Center(child: MgIcon(icon, size: size * 0.55, color: color ?? MgColors.link)),
      );
}

/// Section eyebrow on light: dark pill `#0E2A1C`, neon 11.5/800 caps.
class MgEyebrowDark extends StatelessWidget {
  final String text;
  final String? icon;
  const MgEyebrowDark(this.text, {super.key, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: MgColors.panel,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[MgIcon(icon!, size: 14, color: MgColors.neon), const SizedBox(width: 6)],
          // Krátký štítek: jeden řádek, raději menší než rozdělený („CHOISIS…").
          Flexible(
            child: MgWordFit(
              minScale: 0.7,
              child: Text(text.toUpperCase(),
                  maxLines: 2, style: MgType.eyebrow.copyWith(color: MgColors.neon)),
            ),
          ),
        ]),
      );
}

/// Eyebrow as plain caps text (on dark: neon text; on light: `#0D6E0D`).
class MgEyebrow extends StatelessWidget {
  final String text;
  final bool dark;
  const MgEyebrow(this.text, {super.key, this.dark = true});

  @override
  Widget build(BuildContext context) => MgWordFit(
        minScale: 0.7,
        child: Text(
          text.toUpperCase(),
          style: MgType.eyebrow.copyWith(color: dark ? MgColors.neonText : MgColors.link),
        ),
      );
}
