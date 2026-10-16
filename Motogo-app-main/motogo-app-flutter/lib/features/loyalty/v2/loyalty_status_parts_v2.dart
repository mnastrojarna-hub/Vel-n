import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/rank/rank_copy.dart';
import '../../../core/v2/rank/rank_tokens.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../loyalty_provider.dart';

/// Tier progress bar on a dark carrier (board `.rk-bar`): one segment = one
/// point of the current tier (2 points per level), filled in the rank
/// accent. Legenda = one full segment. Fills once (700 ms); reduced → static.
class RankTierBarV2 extends StatelessWidget {
  final RankTokens rank;
  final int points;
  const RankTierBarV2({super.key, required this.rank, required this.points});

  /// (filled, total) segments of the tier for [points] / the reached level.
  static (int, int) segmentsFor(RankTokens r, int points) {
    if (r.isBrand) return (0, 10);
    if (r.tier == RankTier.legend) return (1, 1);
    final total = r.steps * 2;
    final base = 2 * r.tierFrom - 2;
    final byLevel = (r.level - r.tierFrom) * 2;
    final byPoints = points - base;
    final filled = (byPoints > byLevel ? byPoints : byLevel).clamp(0, total);
    return (filled, total);
  }

  @override
  Widget build(BuildContext context) {
    final (filled, total) = segmentsFor(rank, points);
    Widget bar(double t) => Row(children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) SizedBox(width: i.isEven ? 6 : 3),
            Expanded(
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: i < (filled * t).round() ? rank.accentOnDark : MgColors.white(0.14),
                ),
              ),
            ),
          ],
        ]);
    if (MgMotion.reduced(context)) return bar(1);
    return MgProgressOnce(
      duration: MgMotion.connector,
      delay: const Duration(milliseconds: 250),
      builder: (_, t) => bar(t),
    );
  }
}

/// Labels under the tier bar: "Silnice · 5 / 10" and "Kovová liga · od 10
/// bodů" (next tier start, 2 × level − 2 points; none at Legenda).
class RankTierBarLabelsV2 extends StatelessWidget {
  final RankTokens rank;
  final int points;
  const RankTierBarLabelsV2({super.key, required this.rank, required this.points});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final (filled, total) = RankTierBarV2.segmentsFor(rank, points);
    final left = '${RankCopy.tierName(tr, rank.tier)} · $filled / $total';
    String? right;
    if (!rank.isBrand && rank.tier != RankTier.legend) {
      final next = RankTokens.forLevel(rank.tierTo + 1);
      right = '${RankCopy.tierName(tr, next.tier)} · '
          '${tr.tr('loyaltyFromBooking').replaceAll('{n}', '${2 * next.level - 2}')}';
    }
    final style = MgType.tab(MgType.micro.copyWith(color: MgColors.onDarkMeta));
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text(left, style: style)),
        if (right != null) ...[
          const SizedBox(width: 8),
          Flexible(child: Text(right, textAlign: TextAlign.end, style: style)),
        ],
      ]),
    );
  }
}

/// The three status lines of today's rank card (same keys): level · points,
/// next rank / max rank, ★ app only.
class RankStatusLinesV2 extends StatelessWidget {
  final LoyaltyStatus status;
  final bool showAppOnly;
  const RankStatusLinesV2({super.key, required this.status, this.showAppOnly = true});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final s = status;
    final level = '${tr.tr('loyaltyLevelOf').replaceAll('{lvl}', '${s.level}').replaceAll('{max}', '${s.maxLevel}')}'
        ' · ${tr.tr('loyaltyBookingsCount').replaceAll('{n}', '${s.qualifyingCount}')}';
    final next = (!s.isMax && s.nextRankName != null && s.bookingsToNext != null)
        ? tr
            .tr('loyaltyNextRank')
            .replaceAll('{n}', '${s.bookingsToNext}')
            .replaceAll('{next}', RankCopy.name(tr, s.level + 1, s.nextRankName))
            .replaceAll('{pct}', '${s.nextPercent ?? ''}')
        : tr.tr('loyaltyMaxRank');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 10),
      Text(level, style: MgType.tab(MgType.small.copyWith(color: MgColors.onDarkLead))),
      const SizedBox(height: 2),
      Text(next, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark)),
      if (showAppOnly) ...[
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const MgIcon(MgIcons.star, size: 16, color: MgColors.star),
          const SizedBox(width: 6),
          Expanded(
            child: Text(tr.tr('loyaltyAppOnly'), style: MgType.meta.copyWith(color: MgColors.onDarkMeta)),
          ),
        ]),
      ],
    ]);
  }
}

/// 40 px tier emblem (CTA material disc + tier icon) — dark carriers only.
class RankEmblemV2 extends StatelessWidget {
  final RankTokens rank;
  final double size;
  const RankEmblemV2({super.key, required this.rank, this.size = 40});

  static String iconFor(RankTokens r) => switch (r.tier) {
        RankTier.road => MgIcons.tierRoad,
        RankTier.metal => MgIcons.tierMetal,
        RankTier.jewel => MgIcons.tierJewel,
        RankTier.vip => MgIcons.crown,
        RankTier.legend => MgIcons.laurel,
      };

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: rank.ctaGradient,
          border: Border.all(color: rank.ctaEdge.first, width: 1),
          boxShadow: rank.softGlow(blur: 14, dy: 4),
        ),
        child: Center(child: MgIcon(iconFor(rank), size: size * 0.5, color: rank.ctaLabel)),
      );
}
