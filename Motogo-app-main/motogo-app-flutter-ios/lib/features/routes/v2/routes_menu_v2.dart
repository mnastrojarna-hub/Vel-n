import 'package:flutter/material.dart';

import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';

/// One row of the existing Trasy "+" menu in the v2 look (light sheet,
/// dark icon tile, title + hint). Same label / subtitle / onTap as the old
/// ListTile; the old Material icon is mapped to the v2 line icon.
class CommunityMenuRowV2 extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool danger;
  final VoidCallback onTap;

  const CommunityMenuRowV2({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.danger,
    required this.onTap,
  });

  static String _v2Icon(IconData i) {
    if (i == Icons.stop_circle) return MgIcons.stopFilled;
    if (i == Icons.fiber_manual_record) return MgIcons.recordDot;
    if (i == Icons.add_location_alt) return MgIcons.pinPlus;
    if (i == Icons.alt_route) return MgIcons.plus;
    return MgIcons.route;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: subtitle == null ? label : '$label. $subtitle',
      excludeSemantics: true,
      child: MgPress(
        scale: 0.98,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: danger ? MgColors.errBg : MgColors.panel,
                borderRadius: BorderRadius.circular(12),
                border: danger ? Border.all(color: MgColors.errBorder) : null,
              ),
              child: Center(child: MgIcon(_v2Icon(icon), size: 22, color: danger ? MgColors.err : MgColors.neon)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(label, style: MgType.title.copyWith(color: danger ? MgColors.err : MgColors.ink)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: MgType.small.copyWith(color: MgColors.lead)),
                ],
              ]),
            ),
            const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.lead),
          ]),
        ),
      ),
    );
  }
}
