import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/rank/mg_club_emblem.dart';
import '../../../core/v2/rank/rank_copy.dart';
import '../../../core/v2/rank/rank_provider.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_section.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../loyalty/loyalty_provider.dart';
import 'home_club_card_v2.dart' show showClubRulesSheet;

/// Domů v2 rank card = the old `LoyaltyRankCard` (owner 2026-11-07 "jen
/// upgrade vzhledu"): the SAME facts in the SAME order — "MŮJ RANK", rank
/// name + discount on the dark band, level progress (1 segment = 1 level),
/// "Level n z 20 · n rezervací", the next rank (or max rank), the app-only
/// note and the program rules — in the v2 look (rank colours, R1). Hidden
/// while the backend returns no rank, exactly like the old card.
class HomeRankCardV2 extends ConsumerWidget {
  const HomeRankCardV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(loyaltyStatusProvider).valueOrNull;
    if (status == null) return const SizedBox.shrink();
    final tr = t(context);
    final rank = ref.watch(rankTokensProvider);
    final name = RankCopy.name(tr, status.level, status.rankName);
    final next = !status.isMax && status.nextRankName != null && status.bookingsToNext != null
        ? tr
            .tr('loyaltyNextRank')
            .replaceAll('{n}', '${status.bookingsToNext}')
            .replaceAll('{next}', RankCopy.name(tr, status.level + 1, status.nextRankName))
            .replaceAll('{pct}', '${status.nextPercent ?? ''}')
        : null;

    return Padding(
      key: const ValueKey('home-rank-card'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(tr.tr('loyaltyMyRank').toUpperCase(), style: MgType.eyebrow.copyWith(color: MgColors.meta)),
        ),
        MgCard(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Tmavý pruh ranku (stará karta: tmavá pilulka s názvem a %).
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
              decoration: BoxDecoration(
                color: MgColors.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: rank.chipBorder, width: 1.2),
                boxShadow: [BoxShadow(color: rank.glowColor.withValues(alpha: rank.row.glowAlpha * 0.6), blurRadius: 14)],
              ),
              child: Row(children: [
                MgIcon(mgClubTierIcon(rank.tier), size: 20, color: rank.accentOnDark),
                const SizedBox(width: 10),
                Expanded(
                  child: MgWordFit(
                    minScale: 0.7,
                    child: Text(name.toUpperCase(),
                        style: MgType.title.copyWith(fontWeight: FontWeight.w900, color: rank.accentOnDark)),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${status.percent} %',
                    key: const ValueKey('home-rank-pct'),
                    style: MgType.tab(MgType.h3.copyWith(fontWeight: FontWeight.w900, color: rank.accentOnDark))),
              ]),
            ),
            const SizedBox(height: 12),
            MgClubTierBar(rank: rank, segments: status.maxLevel, filled: status.level, full: status.isMax),
            const SizedBox(height: 8),
            Text(
              '${tr.tr('loyaltyLevelOf').replaceAll('{lvl}', '${status.level}').replaceAll('{max}', '${status.maxLevel}')}'
              ' · ${tr.tr('loyaltyBookingsCount').replaceAll('{n}', '${status.qualifyingCount}')}',
              key: const ValueKey('home-rank-level'),
              style: MgType.tab(MgType.meta.copyWith(color: MgColors.lead)),
            ),
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: MgIcon(MgIcons.up, size: 18, color: MgColors.link),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(next ?? tr.tr('loyaltyMaxRank'),
                    style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: next == null ? MgColors.link : MgColors.ink)),
              ),
            ]),
            const SizedBox(height: 6),
            // POZOR: sleva platí jen pro rezervace vytvořené v aplikaci.
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: MgIcon(MgIcons.starFilled, size: 14, color: MgColors.meta),
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(tr.tr('loyaltyAppOnly'), style: MgType.meta.copyWith(color: MgColors.meta))),
            ]),
            Align(
              alignment: Alignment.centerLeft,
              child: MgTextLink(
                key: const ValueKey('home-rank-info'),
                label: tr.tr('loyaltyInfoBtn'),
                onTap: () => showClubRulesSheet(context),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
