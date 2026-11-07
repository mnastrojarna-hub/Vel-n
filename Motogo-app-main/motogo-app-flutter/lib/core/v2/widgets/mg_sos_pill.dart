import 'package:flutter/material.dart';

import '../icons/mg_icon.dart';
import '../motion/mg_anim.dart';
import '../motion/mg_haptic.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_type.dart';

/// The red SOS pill (V22 Main `.sos`): 76 × 44 `#D92D20` with the SOS glyph,
/// round 44 when [compact]. A plain tap that runs [onTap] (the caller's
/// existing "open /sos"), with a heavy haptic (V2 §4.3 — the ONLY heavy one).
class MgSosPill extends StatelessWidget {
  final VoidCallback onTap;
  final bool compact;
  final String? label;
  const MgSosPill({super.key, required this.onTap, this.compact = false, this.label});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label ?? 'SOS',
      excludeSemantics: true,
      child: MgPress(
        haptic: false,
        onTap: () {
          MgHaptic.sos();
          onTap();
        },
        child: Container(
          width: compact ? 44 : 76,
          height: 44,
          decoration: BoxDecoration(
            color: MgColors.sos,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: MgColors.white(0.18)),
            boxShadow: [BoxShadow(color: MgColors.sos.withValues(alpha: 0.6), blurRadius: 22, offset: const Offset(0, 8), spreadRadius: -8)],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (!compact) ...[
              const MgIcon(MgIcons.sos, size: 16, color: MgColors.onDark, stroke: 2.4),
              const SizedBox(width: 6),
            ],
            Text('SOS',
                style: (compact ? MgType.micro : MgType.ctaCompact)
                    .copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.8, color: MgColors.onDark)),
          ]),
        ),
      ),
    );
  }
}
