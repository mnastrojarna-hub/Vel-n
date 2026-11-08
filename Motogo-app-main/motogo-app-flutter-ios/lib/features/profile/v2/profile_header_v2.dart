import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_skeleton.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../home/nickname_provider.dart';
import '../../loyalty/loyalty_provider.dart';
import '../../loyalty/loyalty_ranks_screen.dart' show openLoyaltyRanks;
import '../../loyalty/v2/loyalty_info_sheet_v2.dart';
import '../../loyalty/v2/loyalty_status_parts_v2.dart';
import 'profile_fit.dart';

/// Profil header "Můj klub" (V21 §1.2, V22 §2.4): dark rank hero — avatar in
/// the tier ring + arc (→ ranks), gear (→ Nastavení), name, nickname chip
/// (→ the existing nickname dialog), glass rank strip (→ ranks, ⓘ program
/// sheet) and, while documents are incomplete, the screen's ONE looping
/// CTA "NAHRÁT DOKLADY" as the last row (rank CTA on a dark carrier).
/// [onBack] (Profil pushed from the booking form) = a back disc first.
class ProfileHeaderV2 extends ConsumerWidget {
  final Map<String, dynamic>? profile;
  final VoidCallback? onBack;

  /// First load (no profile yet): name + nickname as dark skeleton bars in
  /// their final size — never the "Pilot" placeholder flashing first.
  final bool loading;
  const ProfileHeaderV2({super.key, required this.profile, this.onBack, this.loading = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final rank = ref.watch(rankTokensProvider);
    final status = ref.watch(loyaltyStatusProvider).valueOrNull;
    final fullName = profile?['full_name'] as String?;
    final name = (fullName == null || fullName.trim().isEmpty) ? tr.tr('pilot') : fullName;

    Widget avatar = RankFrame(
      size: 64,
      circle: true,
      rank: rank,
      semanticLabel: status == null ? null : RankCopy.aria(tr, status.level, RankCopy.name(tr, status.level, status.rankName), status.percent),
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
        // The old header: the always visible back (pushed → back, tab root
        // → `backOr(Domů)` as there); no extra shortcuts.
        Row(children: [
          MgV2Back(
            key: const ValueKey('pf-back'),
            onTap: onBack ?? () => context.backOr(Routes.home),
            style: MgBackStyle.dark,
          ),
          Padding(padding: const EdgeInsets.all(8), child: avatar),
        ]),
        const SizedBox(height: 12),
        MgEnter(child: MgEyebrow(tr.tr('v2PfClub'))),
        const SizedBox(height: 4),
        if (loading) ...[
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              key: ValueKey('pf-header-skeleton'),
              padding: EdgeInsets.symmetric(vertical: 3),
              child: MgSkeleton(width: 160, height: 22, dark: true),
            ),
          ),
          const SizedBox(height: 4),
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: MgSkeleton(width: 110, height: 28, radius: 999, dark: true),
            ),
          ),
        ] else ...[
          MgEnter(
            delay: const Duration(milliseconds: 80),
            child: Semantics(
              header: true,
              child: Text(name, style: MgType.h2.copyWith(color: MgColors.onDark, letterSpacing: -0.2)),
            ),
          ),
          const SizedBox(height: 4),
          Align(alignment: AlignmentDirectional.centerStart, child: _NickChip(fullName: fullName, rank: rank)),
        ],
        if (status != null) _RankStrip(status: status, rank: rank),
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
    final rankName = RankCopy.name(tr, status.level, status.rankName);
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
          _StripTop(eyebrow: tr.tr('loyaltyMyRank').toUpperCase(), info: tr.tr('loyaltyInfoBtn')),
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

/// Eyebrow left, "O programu" right (as designed); when a word of the
/// eyebrow would not fit beside the button (fr / nl / de, large text) the
/// button moves under it instead of the eyebrow breaking in half
/// (verify:render).
class _StripTop extends StatelessWidget {
  final String eyebrow;
  final String info;
  const _StripTop({required this.eyebrow, required this.info});

  static final _eyebrowStyle = MgType.eyebrow.copyWith(color: MgColors.onDarkSecondary);
  static final _infoStyle = MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.neonText);

  @override
  Widget build(BuildContext context) {
    final label = MgWordFit(child: Text(eyebrow, style: _eyebrowStyle));
    final button = Semantics(
      button: true,
      child: MgPress(
        onTap: () => showLoyaltyInfoSheetV2(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const MgIcon(MgIcons.info, size: 16, color: MgColors.neonText),
            const SizedBox(width: 4),
            Text(info, style: _infoStyle),
          ]),
        ),
      ),
    );
    return LayoutBuilder(builder: (context, box) {
      final room = box.maxWidth - 20 - pfLineWidth(context, info, _infoStyle);
      if (pfWordsFit(context, eyebrow, _eyebrowStyle, room)) {
        return Row(children: [Expanded(child: label), button]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [label, button]);
    });
  }
}

