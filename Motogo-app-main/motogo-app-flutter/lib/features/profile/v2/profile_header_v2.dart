import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/router.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/rank/rank_copy.dart';
import '../../../core/v2/rank/rank_frame.dart';
import '../../../core/v2/rank/rank_hero.dart';
import '../../../core/v2/rank/rank_provider.dart';
import '../../../core/v2/rank/rank_tokens.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../documents/docs_gate_provider.dart';
import '../../home/nickname_provider.dart';
import '../../loyalty/loyalty_provider.dart';
import '../../loyalty/loyalty_ranks_screen.dart' show openLoyaltyRanks;
import '../../loyalty/v2/loyalty_info_sheet_v2.dart';
import '../../loyalty/v2/loyalty_status_parts_v2.dart';

/// Profil header "Můj klub" (V21 §1.2, V22 §2.4): dark rank hero — avatar in
/// the tier ring + arc (→ ranks), gear (→ Nastavení), name, nickname chip
/// (→ the existing nickname dialog), glass rank strip (→ ranks, ⓘ program
/// sheet) and, while documents are incomplete, the screen's ONE looping
/// CTA "NAHRÁT DOKLADY" as the last row (rank CTA on a dark carrier).
class ProfileHeaderV2 extends ConsumerWidget {
  final Map<String, dynamic>? profile;
  final VoidCallback onSettings;
  const ProfileHeaderV2({super.key, required this.profile, required this.onSettings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final rank = ref.watch(rankTokensProvider);
    final status = ref.watch(loyaltyStatusProvider).valueOrNull;
    final docs = ref.watch(docsFabStatusProvider).valueOrNull;
    final fullName = profile?['full_name'] as String?;
    final name = (fullName == null || fullName.trim().isEmpty) ? tr.tr('pilot') : fullName;

    Widget avatar = RankFrame(
      size: 64,
      circle: true,
      rank: rank,
      semanticLabel: status == null ? null : RankCopy.aria(tr, status.level, status.rankNameFor(tr), status.percent),
      child: const ColoredBox(
        color: MgColors.panel,
        child: Center(child: MgIcon(MgIcons.person, size: 30, color: MgColors.neon)),
      ),
    );
    if (status != null) avatar = MgPress(onTap: () => openLoyaltyRanks(context), child: avatar);

    return MgRankHero(
      rank: rank,
      ambientKey: 'profile',
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Padding(padding: const EdgeInsets.all(8), child: avatar),
          const Spacer(),
          MgIconButton(icon: MgIcons.gear, semanticLabel: tr.tr('settings'), onTap: onSettings),
        ]),
        const SizedBox(height: 12),
        MgEnter(child: MgEyebrow(tr.tr('v2PfClub'))),
        const SizedBox(height: 4),
        MgEnter(
          delay: const Duration(milliseconds: 80),
          child: Semantics(
            header: true,
            child: Text(name, style: MgType.h2.copyWith(color: MgColors.onDark, letterSpacing: -0.2)),
          ),
        ),
        const SizedBox(height: 4),
        Align(alignment: AlignmentDirectional.centerStart, child: _NickChip(fullName: fullName, rank: rank)),
        if (status != null) _RankStrip(status: status, rank: rank),
        if (docs != null && !docs.isComplete) _DocsCta(docs: docs),
      ]),
    );
  }
}

/// "PILOT: {přezdívka} ✎" in the rank chip material → the shared dialog.
class _NickChip extends ConsumerWidget {
  final String? fullName;
  final RankTokens rank;
  const _NickChip({required this.fullName, required this.rank});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final display = ref.watch(nicknameProvider) ?? extractFirstName(fullName);
    final label = '${tr.tr('homePilotLabel').trim()} $display';
    return Semantics(
      button: true,
      label: label,
      hint: tr.tr('editNickname'),
      excludeSemantics: true,
      child: MgPress(
        onTap: () => showNicknameDialog(context, ref, fullName: fullName),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Align(
            widthFactor: 1,
            alignment: Alignment.centerLeft,
            child: Container(
              height: 32,
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
              decoration: BoxDecoration(
                color: rank.chipBg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: rank.chipBorder),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: rank.hex, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: MgType.meta.copyWith(fontWeight: FontWeight.w800, height: 1, color: rank.chipText)),
                ),
                const SizedBox(width: 6),
                MgIcon(MgIcons.edit, size: 16, color: rank.chipText.withValues(alpha: 0.8)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Glass rank strip (tap → /loyalty; ⓘ → program sheet). Same texts as
/// today's `LoyaltyRankCard`.
class _RankStrip extends StatelessWidget {
  final LoyaltyStatus status;
  final RankTokens rank;
  const _RankStrip({required this.status, required this.rank});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final rankName = status.rankNameFor(tr);
    return MgReveal(
      index: 2,
      sessionKey: 'pf-strip',
      child: Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        decoration: BoxDecoration(
          color: MgColors.white(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MgColors.neonA(0.18)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(tr.tr('loyaltyMyRank').toUpperCase(),
                  style: MgType.eyebrow.copyWith(color: MgColors.onDarkSecondary)),
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
                    Text(tr.tr('loyaltyInfoBtn'),
                        style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.neonText)),
                  ]),
                ),
              ),
            ),
          ]),
          Semantics(
            button: true,
            label: RankCopy.aria(tr, status.level, rankName, status.percent),
            excludeSemantics: true,
            child: MgPress(
              onTap: () => openLoyaltyRanks(context),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(children: [
                  RankEmblemV2(rank: rank),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text(rankName, style: MgType.section.copyWith(color: rank.accentOnDark)),
                      Container(
                        height: 24,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: rank.chipBg,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: rank.chipBorder),
                        ),
                        child: Center(
                          widthFactor: 1,
                          child: Text('${status.percent} %',
                              style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w900, color: rank.chipText))),
                        ),
                      ),
                    ]),
                  ),
                  const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.neonText),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 12),
          RankTierBarV2(rank: rank, points: status.qualifyingCount),
          RankTierBarLabelsV2(rank: rank, points: status.qualifyingCount),
          RankStatusLinesV2(status: status),
        ]),
      ),
    );
  }
}

/// Amber glass card with the rank CTA (only while documents are incomplete).
class _DocsCta extends StatelessWidget {
  final DocsScreenStatus docs;
  const _DocsCta({required this.docs});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final items = <String>[];
    final gate = docs.gate;
    if (gate != null && !gate.ok) {
      items.addAll(docsGateMissingLabels(context, gate));
    } else {
      if (!docs.hasIdOrPassport) items.add(tr.tr('idOrPassport'));
      if (!docs.hasLicense) items.add(tr.tr('driversLicense').toLowerCase());
    }
    return MgReveal(
      index: 3,
      sessionKey: 'pf-docs',
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: MgColors.warnDarkBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MgColors.warnDark.withValues(alpha: 0.45)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: MgColors.warnDark.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(child: MgIcon(MgIcons.idCard, size: 22, color: MgColors.warnDark)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr.tr('docsNotVerified'), style: MgType.title.copyWith(color: MgColors.onDark)),
                if (items.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('${tr.tr('missing')}: ${items.join(', ')}',
                      style: MgType.small.copyWith(color: MgColors.onDarkLead)),
                ],
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          MgCta(label: tr.tr('docsBlockingBtn'), loop: true, onTap: () => context.push(Routes.docs)),
        ]),
      ),
    );
  }
}
