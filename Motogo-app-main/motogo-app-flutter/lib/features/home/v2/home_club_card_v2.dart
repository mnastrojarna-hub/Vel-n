import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/rank/rank_copy.dart';
import '../../../core/v2/rank/rank_provider.dart';
import '../../../core/v2/rank/rank_tokens.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_sheet.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../loyalty/loyalty_provider.dart';
import '../../loyalty/loyalty_ranks_screen.dart';
import '../../reservations/reservation_models.dart';
import '../../reservations/reservation_provider.dart';
import 'home_club_parts.dart';
import 'home_reveal.dart';

/// "Tvůj klub" (V22 §2.4 #8 / R5.7): the rank on a white card — emblem,
/// name in ink, tier progress on a well (1 segment = 1 point), next-rank
/// line, privileges, savings so far (real Kč only), the 5 leagues as dark
/// mini discs and the program rules sheet. Replaces Home's LoyaltyRankCard
/// (same facts + the same rules); hidden when loyalty is unavailable.
class HomeClubCardV2 extends ConsumerWidget {
  const HomeClubCardV2({super.key});

  static const _tierStartPts = [0, 10, 18, 32, 38];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(loyaltyStatusProvider).valueOrNull;
    if (status == null) return const SizedBox.shrink();
    final tr = t(context);
    final rank = ref.watch(rankTokensProvider);
    final name = status.rankNameFor(tr);
    final tier = rank.tierIndex;
    final from = _tierStartPts[tier];
    final to = tier < 4 ? _tierStartPts[tier + 1] : from + 1;
    final pts = status.qualifyingCount;
    final inTier = (pts - from).clamp(0, to - from);
    final saved = (ref.watch(reservationsProvider).valueOrNull ?? const <Reservation>[])
        .where((r) => r.displayStatus != ResStatus.cancelled)
        .fold<double>(0, (s, r) => s + (r.loyaltyDiscountAmount ?? 0));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: HomeReveal(
        index: 3,
        sessionKey: 'home-club',
        child: MgCard(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              ClubEmblem(rank: rank, onTap: () => openLoyaltyRanks(context), label: RankCopy.aria(tr, status.level, name, status.percent)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr.tr('v2HomeClubKicker').toUpperCase(), style: MgType.eyebrow.copyWith(color: MgColors.meta)),
                  Text(name, style: MgType.h3.copyWith(color: MgColors.ink)),
                  Text(RankCopy.levelLine(tr, status.level, status.percent),
                      style: MgType.small.copyWith(color: MgColors.lead)),
                ]),
              ),
              MgIconButton(
                icon: MgIcons.info,
                style: MgIconButtonStyle.light,
                iconColor: MgColors.link,
                semanticLabel: tr.tr('loyaltyInfoBtn'),
                onTap: () => showClubRulesSheet(context),
              ),
            ]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: MgColors.well,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MgColors.line),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                ClubTierBar(rank: rank, segments: to - from, filled: inTier, full: status.isMax),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: Text(
                      tr.trArgs('v2HomeClubTierPts', {
                        'tier': RankCopy.tierName(tr, rank.tier),
                        'x': inTier,
                        'y': to - from,
                        'points': RankCopy.points(tr, to - from),
                      }),
                      style: MgType.tab(MgType.meta.copyWith(color: MgColors.lead)),
                    ),
                  ),
                  if (tier < 4)
                    Text(
                      tr.trArgs('v2HomeClubNextTier', {
                        'tier': RankCopy.tierName(tr, RankTier.values[tier + 1]),
                        'n': to,
                        'points': RankCopy.points(tr, to),
                      }),
                      style: MgType.tab(MgType.meta.copyWith(color: MgColors.lead)),
                    ),
                ]),
              ]),
            ),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: MgIcon(MgIcons.up, size: 18, color: MgColors.link),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  !status.isMax && status.nextRankName != null && status.bookingsToNext != null
                      ? tr.tr('loyaltyNextRank')
                          .replaceAll('{n}', '${status.bookingsToNext}')
                          .replaceAll('{next}', status.nextRankNameFor(tr)!)
                          .replaceAll('{pct}', '${status.nextPercent ?? ''}')
                      : tr.tr('loyaltyMaxRank'),
                  style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              '${tr.tr('loyaltyLevelOf').replaceAll('{lvl}', '${status.level}').replaceAll('{max}', '${status.maxLevel}')}'
              ' · ${tr.tr('loyaltyBookingsCount').replaceAll('{n}', '${status.qualifyingCount}')}',
              style: MgType.tab(MgType.meta.copyWith(color: MgColors.meta)),
            ),
            const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  child: ClubPerk(
                    big: '−${status.percent} %',
                    label: tr.tr('v2HomeClubPerkPct'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ClubPerk(
                    icon: status.level >= 3 ? MgIcons.helmet : MgIcons.lock,
                    label: RankCopy.gearLine(tr, status.level),
                    locked: status.level < 3,
                  ),
                ),
              ]),
            ),
            if (saved > 0) ...[
              const SizedBox(height: 10),
              Text(tr.trArgs('v2HomeClubSaved', {'amount': Money.czk(saved)}),
                  style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.body2))),
            ],
            const SizedBox(height: 16),
            Text(tr.tr('v2HomeClubRail').toUpperCase(), style: MgType.eyebrow.copyWith(color: MgColors.meta)),
            const SizedBox(height: 8),
            ClubTierRail(current: tier),
            const SizedBox(height: 10),
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
              child: HomeTextLink(label: tr.tr('v2HomeClubAll'), onTap: () => openLoyaltyRanks(context)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The program rules (same keys as the old LoyaltyRankCard sheet) in a
/// light v2 sheet.
void showClubRulesSheet(BuildContext context) {
  final tr = t(context);
  final rules = [
    tr.tr('loyaltyRulePoints'),
    tr.tr('loyaltyRuleLong'),
    tr.tr('loyaltyRuleLevel'),
    tr.tr('loyaltyRuleAppOnly'),
    tr.tr('loyaltyRuleCombo'),
  ];
  showMgSheet<void>(
    context,
    title: tr.tr('loyaltyInfoTitle'),
    builder: (_) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      for (final r in rules)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: MgIcon(MgIcons.checkCircle, size: 18, color: MgColors.link),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(r, style: MgType.body.copyWith(color: MgColors.body2))),
          ]),
        ),
    ]),
  );
}
