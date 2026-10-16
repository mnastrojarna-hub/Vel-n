import 'package:flutter/material.dart';

import '../tokens/mg_colors.dart';
import '../tokens/mg_space.dart';
import '../tokens/mg_type.dart';
import 'mg_buttons.dart';
import 'mg_icon_tile.dart';

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
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  dark ? MgEyebrow(eyebrow!) : MgEyebrowDark(eyebrow!, icon: eyebrowIcon),
                  const SizedBox(height: 8),
                ],
                Semantics(
                  header: true,
                  child: Text(title,
                      style: MgType.section.copyWith(color: dark ? MgColors.onDark : MgColors.ink)),
                ),
              ],
            ),
          ),
          if (trailingLabel != null) ...[
            const SizedBox(width: 8),
            MgBtnText(label: trailingLabel!, onTap: onTrailing, dark: dark),
          ],
        ],
      ),
    );
  }
}
