import 'package:flutter/material.dart';

import '../icons/mg_icon.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_space.dart';
import '../tokens/mg_type.dart';
import 'mg_icon_tile.dart';

/// List row (min 56): leading icon tile, title 15/800 (max 2 lines, wraps),
/// sub 12.5/600, trailing value / widget / chevron. Light by default; [dark]
/// for rows inside dark blocks.
class MgRow extends StatelessWidget {
  final String title;
  final String? sub;
  final String? icon;
  final Widget? leading;
  final String? trailingValue;
  final Widget? trailing;
  final bool chevron;
  final VoidCallback? onTap;
  final bool dark;
  final bool divider;
  final Color? titleColor;
  final String? semanticLabel;

  const MgRow({
    super.key,
    required this.title,
    this.sub,
    this.icon,
    this.leading,
    this.trailingValue,
    this.trailing,
    this.chevron = false,
    this.onTap,
    this.dark = false,
    this.divider = false,
    this.titleColor,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final lead = leading ??
        (icon == null
            ? null
            : (dark
                ? Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: MgColors.white(0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(child: MgIcon(icon!, size: 20, color: MgColors.neon)),
                  )
                : MgIconTileLight(icon!)));
    final row = Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(vertical: MgSpace.s10),
      decoration: divider
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: dark ? MgColors.white(0.08) : MgColors.line)),
            )
          : null,
      child: Row(children: [
        if (lead != null) ...[lead, const SizedBox(width: 12)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title,
                maxLines: 2,
                softWrap: true,
                style: MgType.title.copyWith(color: titleColor ?? (dark ? MgColors.onDark : MgColors.ink))),
            if (sub != null) ...[
              const SizedBox(height: 2),
              Text(sub!, style: MgType.small.copyWith(color: dark ? MgColors.onDarkMeta : MgColors.meta)),
            ],
          ]),
        ),
        if (trailingValue != null) ...[
          const SizedBox(width: 8),
          Text(trailingValue!,
              style: MgType.tab(MgType.title.copyWith(color: dark ? MgColors.onDark : MgColors.ink))),
        ],
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        if (chevron) ...[
          const SizedBox(width: 4),
          MgIcon(MgIcons.chevronRight, size: 20, color: dark ? MgColors.onDarkMeta : MgColors.meta),
        ],
      ]),
    );
    if (onTap == null) return MergeSemantics(child: row);
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(MgRadius.action), child: row),
    );
  }
}
