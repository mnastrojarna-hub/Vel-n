import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feature_flags.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/rank/rank_tokens.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_inputs.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../loyalty_leaderboard_provider.dart';
import '../loyalty_leaderboard_section.dart' show loyaltyLeaderboardSubLabel;
import '../loyalty_provider.dart';

/// v2 look of `LoyaltyLeaderboardSection` ("Žebříček jezdců" on the dark
/// `/loyalty` page): the SAME flag, providers, conditions, texts, podium /
/// list split and opt-in action (`setLeaderboardOptIn` + selection click).
/// Dark glass card, line icons instead of emoji; the rank colour appears
/// only on dark carriers (avatar discs, the dot, the podium blocks).
class LoyaltyLeaderboardV2 extends ConsumerWidget {
  const LoyaltyLeaderboardV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(loyaltyLeaderboardEnabledProvider).valueOrNull ?? false;
    if (!enabled) return const SizedBox.shrink();
    final data = ref.watch(loyaltyLeaderboardProvider).valueOrNull;
    final status = ref.watch(loyaltyStatusProvider).valueOrNull;
    if (data == null) return const SizedBox.shrink();
    final tr = t(context);
    final top3 = data.entries.take(3).toList();
    final rest = data.entries.skip(3).toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: MgColors.white(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MgColors.white(0.10)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const MgIconTileDark(MgIcons.trophy, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: MgWordFit(
                minScale: 0.8, child: Text(tr.tr('loyaltyLeaderboardTitle'), style: MgType.section.copyWith(color: MgColors.onDark))),
          ),
        ]),
        const SizedBox(height: 6),
        Text(tr.tr('loyaltyLeaderboardSub'), style: MgType.small.copyWith(color: MgColors.onDarkMeta)),
        const SizedBox(height: 14),
        // Minulý vítěz — motivační banner (jako dnes).
        if (data.lastWinner != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: MgColors.white(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: MgColors.neonA(0.25)),
            ),
            child: Row(children: [
              const MgIcon(MgIcons.crown, size: 20, color: MgColors.star),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr.tr('loyaltyLastWinner').replaceAll('{nick}', data.lastWinner!.nickname).replaceAll('{days}', '${data.lastWinner!.days}'),
                  style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),
        ],
        if (data.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(children: [
              const MgIcon(MgIcons.flag, size: 30, color: MgColors.onDarkMeta),
              const SizedBox(height: 8),
              Text(tr.tr('loyaltyLeaderboardEmpty'),
                  textAlign: TextAlign.center, style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDarkSecondary)),
            ]),
          )
        else ...[
          _PodiumV2(top3: top3),
          if (rest.isNotEmpty) const SizedBox(height: 6),
          for (var i = 0; i < rest.length; i++)
            MgEnter(delay: Duration(milliseconds: 70 * i.clamp(0, 5)), child: _RowV2(entry: rest[i])),
        ],
        const SizedBox(height: 10),
        Container(height: 1, color: MgColors.white(0.12)),
        if (status != null) _OptInV2(status: status),
      ]),
    );
  }
}

/// Rank tokens of a rider (v2.2 ramp) and the ink / white text on its fill.
RankTokens _rt(LeaderboardEntry e) => RankTokens.forLevel(e.level, e.colorHex);
Color _onFill(Color c) => c.computeLuminance() > 0.45 ? MgColors.ink : MgColors.onDark;

class _Avatar extends StatelessWidget {
  final LeaderboardEntry e;
  const _Avatar(this.e);

  @override
  Widget build(BuildContext context) {
    final fill = _rt(e).hex;
    final nick = e.nickname.trim();
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        // „Ty" = neonový prstenec (místo pulzující záře).
        border: e.isMe ? Border.all(color: MgColors.neon, width: 2) : null,
      ),
      alignment: Alignment.center,
      child: Text(nick.isNotEmpty ? nick.substring(0, 1).toUpperCase() : '?',
          style: MgType.title.copyWith(fontWeight: FontWeight.w900, color: _onFill(fill))),
    );
  }
}

class _PodiumV2 extends StatelessWidget {
  final List<LeaderboardEntry> top3;
  const _PodiumV2({required this.top3});

  @override
  Widget build(BuildContext context) {
    LeaderboardEntry? at(int pos) {
      for (final e in top3) {
        if (e.position == pos) return e;
      }
      return null;
    }

    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Expanded(child: _pillar(context, at(2), 64)),
      const SizedBox(width: 8),
      Expanded(child: _pillar(context, at(1), 86)),
      const SizedBox(width: 8),
      Expanded(child: _pillar(context, at(3), 50)),
    ]);
  }

  Widget _pillar(BuildContext context, LeaderboardEntry? e, double height) {
    if (e == null) return const SizedBox.shrink();
    final tr = t(context);
    final accent = _rt(e).accentOnDark;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      MgIcon(e.position == 1 ? MgIcons.crown : MgIcons.trophy,
          size: 18, color: e.position == 1 ? MgColors.star : MgColors.onDarkSecondary),
      const SizedBox(height: 4),
      _Avatar(e),
      const SizedBox(height: 5),
      Text(e.nickname,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: e.isMe ? MgColors.neon : MgColors.onDark)),
      MgWordFit(
        child: Text(loyaltyLeaderboardSubLabel(tr.tr, e),
            textAlign: TextAlign.center, style: MgType.tab(MgType.micro.copyWith(color: MgColors.onDarkMeta))),
      ),
      const SizedBox(height: 6),
      Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [accent.withValues(alpha: 0.32), accent.withValues(alpha: 0.06)],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          border: Border.all(color: e.isMe ? MgColors.neon : accent.withValues(alpha: 0.45)),
        ),
        alignment: Alignment.center,
        child: Text('#${e.position}', style: MgType.tab(MgType.h3.copyWith(fontWeight: FontWeight.w900, color: MgColors.onDark))),
      ),
    ]);
  }
}

class _RowV2 extends StatelessWidget {
  final LeaderboardEntry entry;
  const _RowV2({required this.entry});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final fill = _rt(entry).hex;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: entry.isMe ? MgColors.neonA(0.10) : MgColors.white(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: entry.isMe ? MgColors.neonA(0.45) : MgColors.white(0.08)),
      ),
      child: Row(children: [
        SizedBox(
          width: 28,
          child: Text('${entry.position}.',
              style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w900, color: MgColors.onDarkMeta))),
        ),
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(shape: BoxShape.circle, color: fill),
        ),
        Expanded(
          child: Text(entry.nickname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: entry.isMe ? MgColors.neon : MgColors.onDark)),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(loyaltyLeaderboardSubLabel(tr.tr, entry),
              textAlign: TextAlign.end, style: MgType.tab(MgType.micro.copyWith(color: MgColors.onDarkMeta))),
        ),
      ]),
    );
  }
}

/// "Zobrazit mě v žebříčku" — the SAME opt-in action and texts.
class _OptInV2 extends ConsumerWidget {
  final LoyaltyStatus status;
  const _OptInV2({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final on = status.leaderboardOptIn;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Material(
        type: MaterialType.transparency,
        child: MgSwitchRow(
          dark: true,
          title: tr.tr('loyaltyShowMe'),
          value: on,
          onChanged: (v) {
            HapticFeedback.selectionClick();
            setLeaderboardOptIn(ref, v);
          },
        ),
      ),
      Text(on ? tr.tr('loyaltyShowMeOn') : tr.tr('loyaltyShowMeOff'),
          style: MgType.small.copyWith(color: on ? MgColors.onDarkMeta : MgColors.warnDark)),
      if (on && (status.serverNickname == null || status.serverNickname!.trim().isEmpty)) ...[
        const SizedBox(height: 6),
        Text(tr.tr('loyaltyNeedNickname'), style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.neonText)),
      ],
    ]);
  }
}
