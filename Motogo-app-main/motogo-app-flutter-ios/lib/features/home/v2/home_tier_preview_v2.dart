import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/rank/mg_logo_ring.dart';
import '../../../core/v2/rank/rank_copy.dart';
import '../../../core/v2/rank/rank_provider.dart';
import '../../../core/v2/rank/rank_tokens.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_sheet.dart';

/// League rail tap → light sheet "Takhle bude vypadat tvoje appka" (board
/// Main "Klepni a ukážeme ti vzhled", V2 §2.5): a dark sample block with the
/// logo ring, the tier chip, a sample CTA and the nav pill in the RankTokens
/// of [level] (the tier's first level). Pure preview — no data, no action
/// (the sample CTA is inert and hidden from screen readers).
Future<void> showTierPreviewSheet(BuildContext context, int level) {
  final tr = t(context);
  final rank = rankTokensForLevel(level);
  return showMgSheet<void>(
    context,
    title: tr.tr('v2UxShTierTitle'),
    builder: (_) => TierPreviewV2(rank: rank),
  );
}

class TierPreviewV2 extends StatelessWidget {
  final RankTokens rank;
  const TierPreviewV2({super.key, required this.rank});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final tier = RankCopy.tierName(tr, rank.tier);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        key: const ValueKey('tier-preview'),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: MgGradients.hero(rank.aura),
          boxShadow: MgShadows.dark,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            MgLogoRing(size: 48, showBadge: false, rank: rank),
            const SizedBox(width: 12),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: rank.chipBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: rank.chipBorder),
                ),
                child: Text(tier,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MgType.meta.copyWith(fontWeight: FontWeight.w800, color: rank.chipText)),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          ExcludeSemantics(
            child: IgnorePointer(
              child: MgCta(label: tr.tr('v2HomeCtaReserve'), onTap: () {}, rank: rank, arrow: true, size: MgCtaSize.sm48),
            ),
          ),
          const SizedBox(height: 14),
          Center(child: ExcludeSemantics(child: _NavPillSample(rank: rank, label: tr.tr('home')))),
        ]),
      ),
      const SizedBox(height: 12),
      Text(tr.tr('v2UxShTierNote'), style: MgType.small.copyWith(color: MgColors.meta)),
    ]);
  }
}

/// The active nav tab of [rank] (pill material + icon + label) on the
/// night nav colour.
class _NavPillSample extends StatelessWidget {
  final RankTokens rank;
  final String label;
  const _NavPillSample({required this.rank, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(color: MgColors.night, borderRadius: BorderRadius.circular(18)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56,
            height: 30,
            padding: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: rank.edgeGradient,
              boxShadow: rank.softGlow(),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), gradient: rank.ctaGradient),
              child: Center(child: MgIcon(MgIcons.home, size: 18, color: rank.ctaLabel)),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: MgType.navActive.copyWith(color: MgColors.onDark)),
        ]),
      );
}
