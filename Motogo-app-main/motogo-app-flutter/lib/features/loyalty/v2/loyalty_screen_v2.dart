import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_chrome_metrics.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/rank/rank_copy.dart';
import '../../../core/v2/rank/rank_frame.dart';
import '../../../core/v2/rank/rank_provider.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart' show MgGradients;
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../../core/widgets/state_views.dart';
import '../loyalty_leaderboard_section.dart';
import '../loyalty_levels_provider.dart';
import '../loyalty_provider.dart';
import 'loyalty_info_sheet_v2.dart';
import 'loyalty_ladder_v2.dart';
import 'loyalty_status_parts_v2.dart';

/// Věrnostní ranky `/loyalty` in the v2 look (PLAN §2.5.2, technique R —
/// reads the same providers as `LoyaltyRanksScreen`): dark rank showcase
/// (exempt from the surface budget), hero with the logo in the tier ring,
/// name, %, tier bar and the status lines, the existing leaderboard (behind
/// its flag), the ladder grouped by tiers in the NEW ramp colours, and the
/// light rules card. The ambient sparks loop becomes the static tier
/// texture of the page (loop budget). Back = today's behaviour.
class LoyaltyScreenV2 extends ConsumerWidget {
  const LoyaltyScreenV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final status = ref.watch(loyaltyStatusProvider).valueOrNull;
    final levelsAsync = ref.watch(loyaltyLevelsProvider);
    final rank = ref.watch(rankTokensProvider);
    final mq = MediaQuery.of(context);
    void back() {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    }

    final top = Padding(
      padding: EdgeInsets.fromLTRB(12, mq.padding.top + 8, 16, 0),
      child: Row(children: [
        MgV2Back(onTap: back, style: MgBackStyle.dark),
        const SizedBox(width: 10),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(tr.tr('loyaltyRanksTitle'), style: MgType.section.copyWith(color: MgColors.onDark)),
          ),
        ),
      ]),
    );

    final List<Widget> body = levelsAsync.when(
      loading: () => const [
        Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator(color: MgColors.neon))),
      ],
      error: (e, _) => [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: MgErrorView(
            compact: true,
            error: e,
            what: tr.tr('eoLoyaltyLoadFail'),
            onRetry: () => ref.invalidate(loyaltyLevelsProvider),
          ),
        ),
      ],
      data: (levels) => [
        _Hero(status: status),
        const LoyaltyLeaderboardSection(),
        const SizedBox(height: 16),
        LoyaltyLadderV2(levels: levels, current: status?.level ?? 0),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: MgCard(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              MgWordFit(minScale: 0.75, child: Text(tr.tr('loyaltyInfoTitle'), style: MgType.section.copyWith(color: MgColors.ink))),
              const SizedBox(height: 8),
              LoyaltyRulesList(rules: [
                for (final k in const [
                  'loyaltyRulePoints',
                  'loyaltyRuleLong',
                  'loyaltyRuleLevel',
                  'loyaltyRuleGear',
                  'loyaltyRuleAppOnly',
                  'loyaltyRuleCombo',
                ])
                  tr.tr(k),
              ]),
            ]),
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: MgColors.night,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: MgGradients.hero(rank.aura)),
        child: ListView(
          padding: EdgeInsets.only(bottom: MgChrome.bottomObstruction(context)),
          children: [top, ...body],
        ),
      ),
    );
  }
}

/// Removes emoji the old motivation copy carries (v2: no emoji in bodies).
String _noEmoji(String s) => s.replaceAll(RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]', unicode: true), '').trim();

class _Hero extends ConsumerWidget {
  final LoyaltyStatus? status;
  const _Hero({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final s = status;
    final rank = ref.watch(rankTokensProvider);
    final name = s == null ? RankCopy.name(tr, 1) : RankCopy.name(tr, s.level, s.rankName);
    return MgEnter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        decoration: BoxDecoration(
          color: MgColors.white(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: MgColors.neonA(0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: MgWordFit(
                minScale: 0.7,
                child: Text((s == null ? tr.tr('loyaltyInfoTitle') : tr.tr('loyaltyMyRank')).toUpperCase(),
                    style: MgType.eyebrow.copyWith(color: MgColors.onDarkSecondary)),
              ),
            ),
            Semantics(
              button: true,
              child: MgPress(
                onTap: () => showLoyaltyInfoSheetV2(context),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const MgIcon(MgIcons.info, size: 16, color: MgColors.neonText),
                    const SizedBox(width: 4),
                    Text(tr.tr('loyaltyInfoBtn'), style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.neonText)),
                  ]),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: RankFrame(
                size: 72,
                rank: rank,
                semanticLabel: s == null ? null : RankCopy.aria(tr, s.level, name, s.percent),
                child: Image.asset('assets/logo.webp',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const ColoredBox(
                        color: MgColors.night, child: Center(child: MgIcon(MgIcons.moto, size: 32, color: MgColors.neon)))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                MgWordFit(
                  minScale: 0.7,
                  child: Text(name, style: MgType.h2.copyWith(color: rank.isBrand ? MgColors.onDark : rank.accentOnDark)),
                ),
                const SizedBox(height: 4),
                Text('${s?.percent ?? 0} %', style: MgType.tab(MgType.display.copyWith(color: MgColors.onDark))),
              ]),
            ),
          ]),
          if (s != null) ...[
            const SizedBox(height: 16),
            RankTierBarV2(rank: rank, points: s.qualifyingCount),
            RankTierBarLabelsV2(rank: rank, points: s.qualifyingCount),
            RankStatusLinesV2(status: s),
          ] else ...[
            const SizedBox(height: 12),
            Text(tr.tr('loyaltyAppOnly'), style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDark)),
          ],
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: MgColors.white(0.1)))),
            child: Text(_noEmoji(tr.tr('loyaltyClimbMotivation')),
                style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDarkBody)),
          ),
        ]),
      ),
    );
  }
}
