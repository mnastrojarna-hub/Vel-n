import 'package:flutter/material.dart';

import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';

/// v2 look of `ResLocationRow` (V22 "Kdy a kde" `.lr`): icon tile, label,
/// when (date · time), type + address and the ink navigation disc. The row
/// keeps its own navigation (GPS first, address fallback) — passed in as
/// [onNavigate] only when it has a target, exactly as today.
class ResLocationV2 extends StatelessWidget {
  final String label;
  final String? when;
  final String typeLabel;
  final String? address;
  final bool isDelivery;
  final VoidCallback? onNavigate;
  final String navLabel;

  const ResLocationV2({
    super.key,
    required this.label,
    required this.when,
    required this.typeLabel,
    required this.address,
    required this.isDelivery,
    required this.onNavigate,
    required this.navLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        MgIconTileLight(isDelivery ? MgIcons.truck : MgIcons.pin),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: MgType.meta.copyWith(color: MgColors.meta)),
            if (when != null) ...[
              const SizedBox(height: 2),
              Text(when!, style: MgType.tab(MgType.title.copyWith(color: MgColors.ink))),
            ],
            const SizedBox(height: 2),
            Text(
              address == null ? typeLabel : '$typeLabel · $address',
              style: MgType.small.copyWith(color: MgColors.lead),
            ),
          ]),
        ),
        if (onNavigate != null) ...[
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: navLabel,
            excludeSemantics: true,
            child: MgPress(
              onTap: onNavigate,
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(color: MgColors.ink, shape: BoxShape.circle, boxShadow: MgShadows.icon),
                child: const Center(child: MgIcon(MgIcons.navigate, size: 20, color: MgColors.neon)),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}
