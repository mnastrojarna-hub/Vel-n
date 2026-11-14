import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/banner_provider.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/router.dart';
import '../../../core/v2/chrome/mg_top_banner.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/rank/mg_logo_ring.dart';
import '../../../core/v2/rank/rank_hero.dart';
import '../../../core/v2/rank/rank_provider.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_chips.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../auth/auth_provider.dart';
import '../../loyalty/loyalty_provider.dart';
import '../../loyalty/loyalty_ranks_screen.dart';
import '../nickname_provider.dart';

/// Home header = the old `HomeHeader` in the v2 look (owner 2026-11-07
/// "jen upgrade vzhledu"; rank colours R1): logo in the tier ring (→ ranks,
/// as the old LogoRow) over the full width, then the pilot badge (nickname,
/// tap = edit it) and the search field (→ Rezervovat). No profile button
/// (owner 2026-11-14: it doubled the Profil tab of the bottom menu, which
/// keeps the unread badge). The Velín banner is its last line (the
/// v2 shell leaves it out on Domů). [overlap] = a hero card sits on the
/// header's rounded bottom (−24), so the header keeps room for it.
class HomeHeaderV2 extends ConsumerWidget {
  final bool overlap;
  const HomeHeaderV2({super.key, this.overlap = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final rank = ref.watch(rankTokensProvider);
    final fullName = ref.watch(profileProvider).valueOrNull?['full_name'] as String?;
    final nick = ref.watch(nicknameProvider) ?? extractFirstName(fullName);
    final banner = ref.watch(bannerProvider).valueOrNull;
    final hasBanner = banner != null && banner.enabled && banner.text.trim().isNotEmpty;
    final router = GoRouter.maybeOf(context);
    final pilot = '${tr.tr('homePilotLabel')}$nick';
    final search = tr.tr('efoHomeSearch').replaceAll('\n', ' ');

    return MgRankHero(
      rank: rank,
      ambientKey: 'home',
      padding: EdgeInsets.fromLTRB(16, 8, 16, overlap ? (hasBanner ? 28 : 32) : 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // The logo row has the full width: no profile button up here (owner
        // 2026-11-14 — Profil and its unread badge are in the bottom menu).
        // Same wordmark size as before: small only under 271 dp of logo.
        LayoutBuilder(builder: (context, c) => _LogoRow(narrow: c.maxWidth < 271)),
        const SizedBox(height: 10),
        // Pilot (přirozená šířka, max ~45 %) + vyhledávání přes zbytek řádku;
        // nápověda se zmenší na 2 řádky, nikdy se neusekne.
        LayoutBuilder(builder: (context, c) {
          return Row(children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: c.maxWidth * 0.45),
              child: Semantics(
                hint: tr.tr('editNickname'),
                child: MgRankChip(
                  key: const ValueKey('home-pilot'),
                  rank: rank,
                  label: pilot,
                  onTap: () => showNicknameDialog(context, ref, fullName: fullName),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Semantics(
                button: true,
                label: search,
                excludeSemantics: true,
                child: MgPress(
                  key: const ValueKey('home-search'),
                  scale: 0.98,
                  onTap: () => router?.go(Routes.search),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: MgColors.white(0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: MgColors.white(0.08)),
                    ),
                    child: Row(children: [
                      const MgIcon(MgIcons.search, size: 18, color: MgColors.onDarkMeta),
                      const SizedBox(width: 8),
                      Expanded(
                        child: MgWordFit(
                          minScale: 0.75,
                          fitLines: 2,
                          child: Text(search,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: MgType.small.copyWith(color: MgColors.onDarkMeta, height: 1.25)),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ]);
        }),
        // Velín banner = poslední JEDEN řádek hlavičky: marquee, při omezení
        // pohybu statický s „…"; klepnutí ukáže celý text (V22 §2.4 #2).
        if (hasBanner) ...[
          const SizedBox(height: 8),
          MgTopBanner(text: banner.text.trim(), bg: banner.bg, fg: banner.color),
        ],
      ]),
    );
  }
}

/// Logo in the tier ring (tap → ranks, as today's LogoRow) + wordmark.
class _LogoRow extends ConsumerWidget {
  final bool narrow;
  const _LogoRow({required this.narrow});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final status = ref.watch(loyaltyStatusProvider).valueOrNull;
    final frame = MgLogoRing(size: 56, onTap: status == null ? null : () => openLoyaltyRanks(context));
    return Row(children: [
      // 6 nahoře = místo pro korunu VIP rangů; dole jen 2 (značky ringu).
      Padding(padding: const EdgeInsets.fromLTRB(6, 6, 6, 2), child: frame),
      const SizedBox(width: 6),
      Flexible(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          // Značka se vždy vejde celá (zmenší se, nikdy se neusekne).
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text('MOTO GO 24',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                    fontSize: narrow ? 17 : 21,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                    height: 1.1,
                    color: MgColors.onDark)),
          ),
          const SizedBox(height: 2),
          MgWordFit(
            minScale: 0.6,
            child: Text(tr.tr('logoSubtitle'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: MgType.micro.copyWith(letterSpacing: 0.8, color: MgColors.onDarkMeta)),
          ),
        ]),
      ),
    ]);
  }
}
