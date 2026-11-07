import 'package:flutter/material.dart';

import '../icons/mg_icon.dart';
import '../motion/mg_anim.dart';
import '../tokens/mg_colors.dart';
import 'rank_tokens.dart';

/// Tier icon of a rank (emblem / rail).
String mgClubTierIcon(RankTier t) => switch (t) {
      RankTier.road => MgIcons.tierRoad,
      RankTier.metal => MgIcons.tierMetal,
      RankTier.jewel => MgIcons.tierJewel,
      RankTier.vip => MgIcons.crown,
      RankTier.legend => MgIcons.laurel,
    };

/// 44 px tier emblem in the rank CTA material (→ ranks screen).
class MgClubEmblem extends StatelessWidget {
  final RankTokens rank;
  final VoidCallback onTap;
  final String label;
  const MgClubEmblem({super.key, required this.rank, required this.onTap, required this.label});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: MgPress(
          scale: 0.92,
          onTap: onTap,
          child: MgPop(
            playOnMount: true,
            child: Container(
              width: 48,
              height: 48,
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: rank.edgeGradient, boxShadow: rank.softGlow(blur: 12)),
              child: DecoratedBox(
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: rank.ctaGradient),
                child: Center(child: MgIcon(mgClubTierIcon(rank.tier), size: 22, color: rank.ctaLabel)),
              ),
            ),
          ),
        ),
      );
}

/// Tier progress on the well: 1 segment = 1 point inside the tier, a wider
/// gap between levels, the next point hatched; fills once in sequence.
class MgClubTierBar extends StatelessWidget {
  final RankTokens rank;
  final int segments;
  final int filled;
  final bool full;
  const MgClubTierBar({super.key, required this.rank, required this.segments, required this.filled, this.full = false});

  @override
  Widget build(BuildContext context) {
    final n = segments < 1 ? 1 : segments;
    return MgProgressOnce(
      duration: Duration(milliseconds: 45 * n + 200),
      delay: const Duration(milliseconds: 300),
      builder: (_, t) {
        final lit = full ? n : (filled * t).round();
        return Row(children: [
          for (var i = 0; i < n; i++) ...[
            if (i > 0) SizedBox(width: i.isEven ? 5 : 2),
            Expanded(
              child: Container(
                height: 8,
                decoration: mgClubTierSegment(rank, lit: i < lit, next: i == filled && !full),
              ),
            ),
          ],
        ]);
      },
    );
  }
}

/// One segment of [MgClubTierBar]: lit = the rank colour; the NEXT point =
/// neutral fill with a 1.5 px rank outline — never an alpha blend of the
/// rank colour on the light well (VIP 17 crimson turned salmon pink, V22
/// §1.2 "reds are never lightened"); the rest = neutral.
BoxDecoration mgClubTierSegment(RankTokens rank, {required bool lit, required bool next}) => BoxDecoration(
      borderRadius: BorderRadius.circular(4),
      color: lit ? rank.uiLight : (next ? MgColors.inkA(0.18) : MgColors.inkA(0.12)),
      border: next && !lit ? Border.all(color: rank.uiLight, width: 1.5) : null,
    );
