import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/gestures/mg_zone_snap.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/widgets/mg_skeleton.dart';
import '../../../core/widgets/state_views.dart';
import '../../catalog/widgets/moto_filter_panel.dart';
import '../../reservations/reservation_models.dart';
import '../../reservations/reservation_provider.dart';
import '../../reservations/widgets/res_rating_card.dart';
import '../home_actions.dart';
import 'home_bike_list_v2.dart';
import 'home_bookings_v2.dart';
import 'home_calc_row_v2.dart';
import 'home_funnel_parts.dart' show homeFilterCardKey;
import 'home_funnel_photo.dart' show homeFunnelPhotoGuess;
import 'home_funnel_v2.dart';
import 'home_header_v2.dart';
import 'home_rank_card_v2.dart';
import 'home_record_row_v2.dart';
import 'home_review_card_v2.dart' show homeHiddenReviewsProvider;
import 'home_state.dart';

/// Domů v2 = the old `HomeScreen` in the v2 look (owner 2026-11-07 "jen
/// upgrade vzhledu"): the SAME blocks in the SAME order — header, rank card,
/// active bookings (+ SOS), the bike filter with the calendar, the count
/// and the FULL sorted bike list, scroll-to-top, pull-to-refresh and the
/// routes warm-up (PM-8). Kept v2 additions, each an explicit owner request:
/// the booking funnel hero when there is NO paid active / upcoming booking
/// (V21 #3, after a ride with the review card first — V21 #4/#5), the price
/// calculator row (V21 #2) and "Zaznamenat jízdu" (R3). The AI button is
/// the shell's (Domů only, as the old Home). Old `HomeScreen` stays
/// untouched and is used when the `app_v2_ui` flag is off.
class HomeScreenV2 extends ConsumerStatefulWidget {
  const HomeScreenV2({super.key});

  @override
  ConsumerState<HomeScreenV2> createState() => _HomeScreenV2State();
}

class _HomeScreenV2State extends ConsumerState<HomeScreenV2> {
  final ScrollController _scroll = ScrollController();

  /// The page's "back to the top" arrow is shown (the bike captions ride
  /// above its slot meanwhile).
  final ValueNotifier<bool> _topShown = ValueNotifier(false);

  /// One bike per screen: the bike list the page scroll settles on.
  final MgSnapZone _zone = MgSnapZone();

  @override
  void initState() {
    super.initState();
    // Warm-up tabu „Trasy" — stejné zpoždění i kontrola jako stará Domů.
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      warmUpRoutes(ref);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _topShown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final resAsync = ref.watch(reservationsProvider);
    final hidden = ref.watch(homeHiddenReviewsProvider);
    final all = resAsync.valueOrNull ?? const <Reservation>[];
    // Jako stará Domů: jen zaplacené aktivní / nadcházející (apiGetActiveLoan).
    final active = all.where((r) {
      final st = r.displayStatus;
      return (st == ResStatus.aktivni || st == ResStatus.nadchazejici) && r.paymentStatus == 'paid';
    }).toList();
    final loadingRes = resAsync.isLoading && !resAsync.hasValue;
    final failed = resAsync.hasError && !resAsync.hasValue;
    // V21 #3: bez placené aktivní / nadcházející rezervace = rezervační hero.
    final funnel = !loadingRes && active.isEmpty;
    final snap = deriveHomeState(reservations: all, hiddenReviews: hidden);

    final hero = <Widget>[];
    if (loadingRes) {
      hero.add(const _HeroSkeleton());
    } else if (funnel) {
      if (snap.ticket == HomeTicket.s10 && snap.review != null) {
        final r = snap.review!;
        hero
          ..add(ResRatingCard(
            key: ValueKey('home-review-${r.id}'),
            res: r,
            look: RatingLook.light,
            onHide: () => ref.read(homeHiddenReviewsProvider.notifier).hide(r.id),
          ))
          ..add(const SizedBox(height: 16));
      }
      hero.add(const HomeFunnelV2());
    }
    final overlap = hero.isNotEmpty;

    final page = MgPage(
      tabIndex: 0,
      controller: _scroll,
      onRefresh: () => refreshHome(ref),
      overlapHero: false,
      snap: _zone,
      // Jako stará Domů: šipka nahoru po odrolování o 600 px (v5.0.1 vpravo
      // dole vedle AI tlačítka, `MgToTopLayer`).
      toTop: true,
      toTopShown: _topShown,
      sections: [
        HomeHeroStack(
          overlap: overlap,
          header: HomeHeaderV2(overlap: overlap),
          children: [
            ...hero,
            const HomeRankCardV2(),
            HomeBookingsV2(
              active: active,
              error: failed
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: MgErrorView(
                        error: resAsync.error,
                        what: tr.tr('v2HomeResFail'),
                        compact: true,
                        onRetry: () => ref.invalidate(reservationsProvider),
                      ),
                    )
                  : null,
            ),
            HomeCalcRowV2(funnel: funnel),
            const HomeRecordRowV2(),
            // Stará Domů: MotoFilterPanel(showDates: true) — jeho v2 vzhled
            // (sbalená karta, TERMÍN + kalendář, obsah filtru) je v panelu.
            KeyedSubtree(key: homeFilterCardKey, child: const MotoFilterPanel(showDates: true)),
            const HomeBikeCountV2(),
          ],
        ),
      ],
      slivers: [
        ValueListenableBuilder<bool>(
          valueListenable: _topShown,
          builder: (_, top, __) => HomeBikeListV2(heroes: !funnel, zone: _zone, toTop: top),
        ),
      ],
    );

    return page;
  }
}

/// Header, then the content; with [overlap] the content is pulled up by
/// 24 px so the hero card sits on the header's rounded bottom (drawn after
/// the header → on top of it).
class HomeHeroStack extends StatelessWidget {
  final Widget header;
  final List<Widget> children;
  final bool overlap;
  const HomeHeroStack({super.key, required this.header, required this.children, this.overlap = true});

  @override
  Widget build(BuildContext context) {
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      if (overlap) Transform.translate(offset: const Offset(0, -24), child: body) else body,
    ]);
  }
}

/// Dark hero placeholder while the bookings load (never the funnel first —
/// it would flash before a ticket), in the funnel's own geometry (SH-23,
/// design M5): photo of the same height, top row, title, sub line, the two
/// date chips + calendar, the 60 px CTA — no jump when the content lands.
class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.sizeOf(context).height;
    final short = screenH < 700;
    final photoH = homeFunnelPhotoGuess(context);
    final chipH = short ? 52.0 : 56.0;
    return Container(
      key: const ValueKey('home-hero-skeleton'),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: MgColors.panel,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MgSkeleton(height: photoH, radius: 0, dark: true),
        Padding(
          padding: EdgeInsets.fromLTRB(16, short ? 8 : 14, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(
              height: 36,
              child: Align(alignment: Alignment.centerLeft, child: MgSkeleton(width: 150, height: 28, dark: true, radius: 999)),
            ),
            SizedBox(height: short ? 2 : 6),
            const MgSkeleton(width: 230, height: 26, dark: true),
            const SizedBox(height: 8),
            const MgSkeleton(width: 190, height: 14, dark: true),
            SizedBox(height: short ? 10 : 14),
            Row(children: [
              Expanded(child: MgSkeleton(height: chipH * 1.2, dark: true, radius: 14)),
              const SizedBox(width: 8),
              Expanded(child: MgSkeleton(height: chipH * 1.2, dark: true, radius: 14)),
              const SizedBox(width: 8),
              MgSkeleton(width: 52, height: chipH * 1.2, dark: true, radius: 14),
            ]),
            SizedBox(height: short ? 6 : 10),
            const MgSkeleton(height: 60, dark: true, radius: 16),
          ]),
        ),
      ]),
    );
  }
}
