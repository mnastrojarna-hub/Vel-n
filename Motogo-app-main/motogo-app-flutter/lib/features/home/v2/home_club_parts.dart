import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/rank/rank_copy.dart';
import '../../../core/v2/rank/rank_provider.dart';
import '../../../core/v2/rank/rank_tokens.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';

/// Tier icon of a rank (emblem / rail).
String clubTierIcon(RankTier t) => switch (t) {
      RankTier.road => MgIcons.tierRoad,
      RankTier.metal => MgIcons.tierMetal,
      RankTier.jewel => MgIcons.tierJewel,
      RankTier.vip => MgIcons.crown,
      RankTier.legend => MgIcons.laurel,
    };

/// 44 px tier emblem in the rank CTA material (→ ranks screen).
class ClubEmblem extends StatelessWidget {
  final RankTokens rank;
  final VoidCallback onTap;
  final String label;
  const ClubEmblem({super.key, required this.rank, required this.onTap, required this.label});

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
                child: Center(child: MgIcon(clubTierIcon(rank.tier), size: 22, color: rank.ctaLabel)),
              ),
            ),
          ),
        ),
      );
}

/// Tier progress on the well: 1 segment = 1 point inside the tier, a wider
/// gap between levels, the next point hatched; fills once in sequence.
class ClubTierBar extends StatelessWidget {
  final RankTokens rank;
  final int segments;
  final int filled;
  final bool full;
  const ClubTierBar({super.key, required this.rank, required this.segments, required this.filled, this.full = false});

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
                decoration: clubTierSegment(rank, lit: i < lit, next: i == filled && !full),
              ),
            ),
          ],
        ]);
      },
    );
  }
}

/// One segment of [ClubTierBar]: lit = the rank colour; the NEXT point =
/// neutral fill with a 1.5 px rank outline — never an alpha blend of the
/// rank colour on the light well (VIP 17 crimson turned salmon pink, V22
/// §1.2 "reds are never lightened"); the rest = neutral.
BoxDecoration clubTierSegment(RankTokens rank, {required bool lit, required bool next}) => BoxDecoration(
      borderRadius: BorderRadius.circular(4),
      color: lit ? rank.uiLight : (next ? MgColors.inkA(0.18) : MgColors.inkA(0.12)),
      border: next && !lit ? Border.all(color: rank.uiLight, width: 1.5) : null,
    );

/// Privilege tile on the well (big value or icon + label).
class ClubPerk extends StatelessWidget {
  final String? big;
  final String? icon;
  final String label;
  final bool locked;
  const ClubPerk({super.key, this.big, this.icon, required this.label, this.locked = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 84),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MgColors.well,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MgColors.line, style: BorderStyle.solid),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        if (big != null)
          Text(big!, style: MgType.tab(MgType.h2.copyWith(fontWeight: FontWeight.w900, color: MgColors.link)))
        else if (icon != null)
          MgIcon(icon!, size: 22, color: locked ? MgColors.lead : MgColors.link),
        const SizedBox(height: 4),
        Text(label, style: MgType.small.copyWith(fontWeight: FontWeight.w800, height: 1.3, color: MgColors.ink)),
      ]),
    );
  }
}

/// The 5 leagues as dark mini discs carrying the tier material (passed /
/// current ring / locked). Names in semantics + long-press tooltip.
class ClubTierRail extends StatelessWidget {
  final int current;
  const ClubTierRail({super.key, required this.current});

  static const _from = [1, 6, 10, 17, 20];
  static const _pts = [0, 10, 18, 32, 38];

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Row(children: [
      for (var i = 0; i < 5; i++) ...[
        if (i > 0)
          Expanded(
            child: Container(height: 2, color: i <= current ? MgColors.link : MgColors.line),
          ),
        _disc(tr, i),
      ],
    ]);
  }

  Widget _disc(AppTranslations tr, int i) {
    final r = rankTokensForLevel(_from[i]);
    final name = RankCopy.tierName(tr, r.tier);
    final state = i < current
        ? tr.tr('v2HomeClubPassed')
        : i == current
            ? tr.tr('v2HomeClubHere')
            : tr.trArgs('v2HomeClubFrom', {'n': _pts[i], 'points': RankCopy.points(tr, _pts[i])});
    final locked = i > current;
    return Tooltip(
      message: '$name · $state',
      child: Semantics(
        label: '$name, $state',
        excludeSemantics: true,
        child: MgReveal(
          index: i,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: MgColors.panel,
              boxShadow: i == current
                  ? const [BoxShadow(color: MgColors.surface, spreadRadius: 2), BoxShadow(color: MgColors.link, spreadRadius: 4)]
                  : [BoxShadow(color: MgColors.inkA(0.14), spreadRadius: 1)],
            ),
            padding: const EdgeInsets.all(8),
            child: Opacity(
              opacity: locked ? 0.55 : 1,
              child: DecoratedBox(
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: r.ctaGradient),
                child: Center(
                  child: MgIcon(locked ? MgIcons.lock : clubTierIcon(r.tier), size: 13, color: r.ctaLabel),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
