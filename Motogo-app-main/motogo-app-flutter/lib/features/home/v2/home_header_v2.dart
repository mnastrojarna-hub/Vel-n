import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/banner_provider.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/router.dart';
import '../../../core/v2/chrome/mg_nav_helpers.dart';
import '../../../core/v2/chrome/mg_top_banner.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/rank/rank_copy.dart';
import '../../../core/v2/rank/rank_frame.dart';
import '../../../core/v2/rank/rank_hero.dart';
import '../../../core/v2/rank/rank_marks.dart';
import '../../../core/v2/rank/rank_provider.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_chips.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../auth/auth_provider.dart';
import '../../loyalty/loyalty_provider.dart';
import '../../loyalty/loyalty_ranks_screen.dart';
import '../../messages/messages_provider.dart';
import '../../sos/sos_provider.dart';
import '../nickname_provider.dart';
import 'home_header_note.dart';
import 'home_state.dart';

/// Home header (DESIGN_V22 §2.4 #1, Main `.hd`): compact dark rank band —
/// logo in the tier ring (→ ranks), SOS pill (only during a rental), bell
/// with unread count (→ Zprávy), greeting + rank chip, motto, concierge note
/// and the Velín banner as its last line. The hero below overlaps it −24.
class HomeHeaderV2 extends ConsumerWidget {
  final HomeSnapshot snap;
  const HomeHeaderV2({super.key, required this.snap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final rank = ref.watch(rankTokensProvider);
    final status = ref.watch(loyaltyStatusProvider).valueOrNull;
    final unread = ref.watch(adminUnreadCountProvider);
    final sos = ref.watch(hasActiveRentalProvider);
    final fullName = ref.watch(profileProvider).valueOrNull?['full_name'] as String?;
    final nick = ref.watch(nicknameProvider) ?? extractFirstName(fullName);
    final banner = ref.watch(bannerProvider).valueOrNull;
    final rankName = RankCopy.name(tr, rank.level, status?.rankName);
    final pct = status?.percent ?? rank.level;
    final motto = RankCopy.motto(tr, rank.level);

    return MgRankHero(
      rank: rank,
      ambientKey: 'home',
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (context, c) {
          final narrow = c.maxWidth < 356;
          return Row(children: [
            Expanded(child: _LogoRow(narrow: c.maxWidth < 323)),
            if (sos) ...[
              _SosPill(compact: narrow, label: tr.tr('homeSosTitle')),
              const SizedBox(width: 8),
            ],
            MgIconButton(
              icon: MgIcons.bell,
              badge: unread,
              semanticLabel: unread > 0
                  ? '${tr.tr('v2HomeBell')}, ${tr.trArgs('v2NavUnread', {'n': unread})}'
                  : tr.tr('v2HomeBell'),
              onTap: () => mgPushOrGo(context, Routes.messages),
            ),
          ]);
        }),
        const SizedBox(height: 12),
        // Pozdrav na JEDEN řádek (zmenší se, nikdy se nezalomí); když se
        // s rankem nevejde, rank čip sjede pod pozdrav (V22 §2.4 #1).
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              button: true,
              hint: tr.tr('editNickname'),
              child: MgPress(
                onTap: () => showNicknameDialog(context, ref, fullName: fullName),
                child: MgEnter(
                  child: MgWordFit(
                    minScale: 0.7,
                    child: Text(homeGreeting(tr, nick, DateTime.now()),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: MgType.h3.copyWith(color: MgColors.onDark, height: 1.2)),
                  ),
                ),
              ),
            ),
            if (status != null)
              MgRankChip(
                label: RankCopy.chip(tr, rankName, pct),
                semanticLabel: RankCopy.aria(tr, rank.level, rankName, pct),
                onTap: () => openLoyaltyRanks(context),
              ),
          ],
        ),
        if (motto.isNotEmpty) ...[
          const SizedBox(height: 6),
          Semantics(
            label: RankCopy.mottoAria(tr, rank, rankName),
            excludeSemantics: true,
            child: Row(children: [
              RankMarks(
                rank: rank,
                litColor: rank.accentOnDark,
                dimColor: rank.accentOnDark.withValues(alpha: 0.3),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(motto,
                    maxLines: 2,
                    style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: rank.accentOnDark)),
              ),
            ]),
          ),
        ],
        HomeHeaderNote(snap: snap, nick: nick),
        // Velín banner = poslední JEDEN řádek hlavičky: marquee, při omezení
        // pohybu statický s „…"; klepnutí ukáže celý text (V22 §2.4 #2).
        if (banner != null && banner.enabled && banner.text.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          MgTopBanner(text: banner.text.trim()),
        ],
      ]),
    );
  }
}

/// "Dobré ráno / dopoledne / odpoledne, Dobrý večer, {nick}".
String homeGreeting(AppTranslations tr, String nick, DateTime now) {
  final h = now.hour;
  final key = h >= 5 && h < 9
      ? 'v2HomeGreetMorning'
      : h >= 9 && h < 12
          ? 'v2HomeGreetForenoon'
          : h >= 12 && h < 18
              ? 'v2HomeGreetAfternoon'
              : 'v2HomeGreetEvening';
  return tr.trArgs(key, {'nick': nick});
}

/// Logo in the tier ring (tap → ranks, as today's LogoRow) + wordmark.
class _LogoRow extends ConsumerWidget {
  final bool narrow;
  const _LogoRow({required this.narrow});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final status = ref.watch(loyaltyStatusProvider).valueOrNull;
    Widget frame = RankFrame(
      size: 56,
      semanticLabel: status == null
          ? null
          : RankCopy.aria(tr, status.level, RankCopy.name(tr, status.level, status.rankName), status.percent),
      child: Image.asset(
        'assets/logo.webp',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const ColoredBox(
          color: MgColors.neon,
          child: Center(child: MgIcon(MgIcons.moto, size: 28, color: MgColors.onNeon)),
        ),
      ),
    );
    if (status != null) frame = MgPress(onTap: () => openLoyaltyRanks(context), child: frame);
    return Row(children: [
      Padding(padding: const EdgeInsets.all(6), child: frame),
      const SizedBox(width: 6),
      Flexible(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('MOTO GO 24',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
              style: TextStyle(
                  fontSize: narrow ? 17 : 21,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  height: 1.1,
                  color: MgColors.onDark)),
          const SizedBox(height: 2),
          Text(tr.tr('logoSubtitle'),
              maxLines: 2,
              style: MgType.micro.copyWith(letterSpacing: 0.8, color: MgColors.onDarkMeta)),
        ]),
      ),
    ]);
  }
}

/// Red SOS pill (V22 Main `.sos`; round 44 when the row is narrow).
class _SosPill extends StatelessWidget {
  final bool compact;
  final String label;
  const _SosPill({required this.compact, required this.label});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: MgPress(
        onTap: () => mgPushOrGo(context, Routes.sos),
        child: Container(
          width: compact ? 44 : 76,
          height: 44,
          decoration: BoxDecoration(
            color: MgColors.sos,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: MgColors.white(0.18)),
            boxShadow: [BoxShadow(color: MgColors.sos.withValues(alpha: 0.6), blurRadius: 22, offset: const Offset(0, 8), spreadRadius: -8)],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (!compact) ...[
              const MgIcon(MgIcons.sos, size: 16, color: MgColors.onDark, stroke: 2.4),
              const SizedBox(width: 6),
            ],
            Text('SOS',
                style: (compact ? MgType.micro : MgType.ctaCompact)
                    .copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.8, color: MgColors.onDark)),
          ]),
        ),
      ),
    );
  }
}
