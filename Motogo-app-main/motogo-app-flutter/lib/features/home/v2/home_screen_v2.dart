import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/pending_booking_fab_provider.dart';
import '../../../core/pending_sos_fab_provider.dart';
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/widgets/mg_skeleton.dart';
import '../../../core/widgets/state_views.dart';
import '../../documents/docs_gate_provider.dart';
import '../../reservations/reservation_models.dart';
import '../../reservations/reservation_provider.dart';
import '../../reservations/widgets/res_rating_card.dart';
import '../home_actions.dart';
import 'home_bikes_for_you_v2.dart';
import 'home_branches_v2.dart';
import 'home_club_card_v2.dart';
import 'home_experiences_band_v2.dart';
import 'home_funnel_v2.dart';
import 'home_header_v2.dart';
import 'home_line_card_v2.dart';
import 'home_message_row_v2.dart';
import 'home_next_pill_v2.dart';
import 'home_offer_block_v2.dart';
import 'home_review_card_v2.dart';
import 'home_routes_v2.dart';
import 'home_state.dart';
import 'home_ticket_v2.dart';

/// Domů v2 (PLAN §2.1, technique R): the same providers as today's Home,
/// recomposed — rank header, then the ticket (a booking needs you / is
/// coming) or the booking funnel (no booking; after a ride with the review
/// card first), then the light sections. Pull-to-refresh and the routes
/// warm-up are the existing PM-8 actions. Old `HomeScreen` stays untouched
/// and is used when the `app_v2_ui` flag is off.
class HomeScreenV2 extends ConsumerStatefulWidget {
  const HomeScreenV2({super.key});

  @override
  ConsumerState<HomeScreenV2> createState() => _HomeScreenV2State();
}

class _HomeScreenV2State extends ConsumerState<HomeScreenV2> {
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
  Widget build(BuildContext context) {
    final tr = t(context);
    final resAsync = ref.watch(reservationsProvider);
    final sos = ref.watch(pendingSosFabProvider).valueOrNull;
    final pending = ref.watch(pendingBookingFabProvider).valueOrNull;
    final docsOk = ref.watch(docsFabStatusProvider).valueOrNull?.isComplete;
    final hidden = ref.watch(homeHiddenReviewsProvider);
    final snap = deriveHomeState(
      reservations: resAsync.valueOrNull ?? const <Reservation>[],
      sos: sos,
      pending: pending,
      docsComplete: docsOk,
      hiddenReviews: hidden,
    );
    final loadingRes = resAsync.isLoading && !resAsync.hasValue && sos == null && pending == null;

    final hero = <Widget>[];
    if (loadingRes) {
      hero.add(const _HeroSkeleton());
    } else if (snap.hasTicket) {
      hero.add(HomeTicketV2(snap: snap));
      if (snap.moreCount > 0) {
        // Old Home: the first 2 paid bookings, each one tap — a ticket that
        // is not one of them (SOS / unpaid) leaves room for a second line.
        final others = snap.active.where((r) => r.id != snap.res?.id).toList();
        final ticketPaid = snap.active.any((r) => r.id == snap.res?.id);
        hero.add(HomeMoreBookingsRowV2(
            count: snap.moreCount,
            next: others.firstOrNull,
            second: ticketPaid || others.length < 2 ? null : others[1]));
      }
      hero.add(const HomeNextPillV2());
    } else {
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
      if (resAsync.hasError && !resAsync.hasValue) {
        hero
          ..add(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: MgErrorView(
              error: resAsync.error,
              what: tr.tr('v2HomeResFail'),
              compact: true,
              onRetry: () => ref.invalidate(reservationsProvider),
            ),
          ))
          ..add(const SizedBox(height: 16));
      }
      hero
        ..add(const HomeFunnelV2())
        ..add(const HomeOfferBlockV2());
    }

    // Header + everything below in ONE box: the hero overlaps the header
    // by −24 (V22 R5.3) and must paint above it — slivers paint earlier
    // ones on top, so the overlap cannot be split across slivers.
    return MgPage(
      tabIndex: 0,
      onRefresh: () => refreshHome(ref),
      overlapHero: false,
      sections: [
        HomeHeroStack(
          header: HomeHeaderV2(snap: snap),
          children: [
            ...hero,
            const HomeMessageRowV2(),
            const HomeClubCardV2(),
            const HomeExperiencesBandV2(),
            const HomeRoutesV2(),
            if (snap.hasTicket) const HomeBikesForYouV2(),
            const HomeBranchesV2(),
            const HomeLineCardV2(),
          ],
        ),
      ],
    );
  }
}

/// Header, then the content pulled up by 24 px so the hero card sits on
/// the header's rounded bottom (drawn after the header → on top of it).
class HomeHeroStack extends StatelessWidget {
  final Widget header;
  final List<Widget> children;
  const HomeHeroStack({super.key, required this.header, required this.children});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        Transform.translate(
          offset: const Offset(0, -24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ]);
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
    final bigText = MediaQuery.textScalerOf(context).scale(10) > 10.5;
    final photoH = screenH >= 800 ? 200.0 : (short && !bigText ? 124.0 : 150.0);
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
