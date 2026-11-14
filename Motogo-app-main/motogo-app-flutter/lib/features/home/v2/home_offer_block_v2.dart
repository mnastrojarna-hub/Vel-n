import 'package:flutter/material.dart';

import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';

/// White row: dark icon tile + title + sub + chevron (min 64).
class HomeLinkRow extends StatelessWidget {
  final String icon;
  final String title;
  final String? sub;
  final VoidCallback onTap;
  final Widget? leading;
  const HomeLinkRow({super.key, required this.icon, required this.title, this.sub, required this.onTap, this.leading});

  @override
  Widget build(BuildContext context) {
    // Řádek s šipkou vpravo = tap zóna pro AI tlačítko.
    return MgFabAvoid(kind: MgAvoidKind.tap, child: Semantics(
      button: true,
      label: sub == null ? title : '$title, $sub',
      excludeSemantics: true,
      child: MgPress(
        scale: 0.99,
        onTap: onTap,
        child: Container(
          color: Colors.transparent,
          constraints: const BoxConstraints(minHeight: 64),
          // Same inset as the rows above it (v5.0.1: tiles in one line).
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(children: [
            leading ?? MgIconTileDark(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink, height: 1.3)),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(sub!, style: MgType.small.copyWith(color: MgColors.meta)),
                ],
              ]),
            ),
            const SizedBox(width: 8),
            const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.lead),
          ]),
        ),
      ),
    ));
  }
}
