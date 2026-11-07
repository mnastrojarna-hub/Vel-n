import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/offline_guard.dart';
import '../../../core/pending_booking_fab_provider.dart';
import '../../../core/router.dart';
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/gestures/mg_swipe.dart';
import '../../../core/v2/gestures/mg_swipe_switcher.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../../core/widgets/state_views.dart';
import '../reservation_models.dart';
import '../booking_restore.dart' show restoreAndPay;
import '../reservation_provider.dart';
import 'page_swipe_v2.dart';
import 'res_card_actions_v2.dart' show resPrimaryCardId;
import 'res_filter_tabs_v2.dart';
import 'res_list_header_v2.dart';
import 'res_skeletons_v2.dart';
import 'res_status_v2.dart';
import 'reservation_card_v2.dart';

/// Cards built eagerly inside the swiping body (≈ 2–3 screenfuls); the
/// rest of the list is a lazy sliver.
const kResSwipeHead = 10;

/// Rezervace tab, v2 look (PLAN §2.4.1, technique R). Same providers and
/// behaviour as `ReservationsScreen`: `filteredReservationsProvider` +
/// `resFilterProvider` (same 5 filters, same horizontal swipe), refresh
/// every 5 s unless offline, stale note when a refresh failed over loaded
/// data, the same loading (never a bare spinner) / error views, card tap →
/// `/reservations/:id`, Upravit → `/reservations/:id/edit`.
class ReservationsScreenV2 extends ConsumerStatefulWidget {
  const ReservationsScreenV2({super.key});

  @override
  ConsumerState<ReservationsScreenV2> createState() => _ReservationsScreenV2State();
}

class _ReservationsScreenV2State extends ConsumerState<ReservationsScreenV2> {
  Timer? _refreshTimer;

  /// Body swipe progress → the filter track's selection follows the finger.
  final _drag = ValueNotifier<double>(0);

  /// Direction of the last filter change (+1 next, −1 previous) for the
  /// in-place content switch.
  int _dir = 0;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      // Offline obnova jen selže — načtený seznam necháme být (jako v1).
      if (OfflineGuard.offlineNow) return;
      ref.invalidate(reservationsProvider);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _drag.dispose();
    super.dispose();
  }

  void _swipeFilter(int direction) => _step(direction);

  /// Neighbour filter (+1 / −1); false at the ends.
  bool _step(int direction) {
    final filter = ref.read(resFilterProvider);
    final idx = kResFilterKeys.indexOf(filter);
    final next = (idx + direction).clamp(0, kResFilterKeys.length - 1);
    if (next == idx) return false;
    _setFilter(kResFilterKeys[next]);
    return true;
  }

  /// The same filter change as a tab tap / ‹ › / swipe (`resFilterProvider`);
  /// only remembers the direction for the content slide.
  void _setFilter(String k) {
    final from = kResFilterKeys.indexOf(ref.read(resFilterProvider));
    final to = kResFilterKeys.indexOf(k);
    setState(() => _dir = (to - from).sign);
    ref.read(resFilterProvider.notifier).state = k;
  }

  /// Pull-to-refresh = the existing retry (invalidate), held until the new
  /// list arrives (max 8 s — offline it just stops).
  Future<void> _refresh() async {
    ref.invalidate(reservationsProvider);
    try {
      await ref.read(reservationsProvider.future).timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final filter = ref.watch(resFilterProvider);
    final reservationsAsync = ref.watch(filteredReservationsProvider);
    final src = ref.watch(reservationsProvider);
    final stale = src.hasError && src.hasValue;
    void retry() => ref.invalidate(reservationsProvider);
    final all = src.valueOrNull ?? const <Reservation>[];
    final counts = <String, int>{
      for (final k in kResFilterKeys)
        k: k == 'all' ? all.length : all.where((r) => r.displayStatus.name == k).length,
    };
    final pending = ref.watch(pendingBookingFabProvider).valueOrNull;

    // Obsah filtru je přepínatelný tahem do stran (board „Přejetím prstem
    // přepneš filtr"): obsah jde s prstem, výběr filtru taky; ‹ › a záložky
    // dělají totéž klepnutím.
    Widget swipeable(Widget content) => MgSwipeSegments<String>(
          values: kResFilterKeys,
          value: filter,
          onChanged: _setFilter,
          progress: _drag,
          child: ConstrainedBox(
            // I krátký seznam má pod sebou plochu pro tah.
            constraints: const BoxConstraints(minHeight: 360),
            child: MgSwipeSwitcher(switchKey: filter, direction: _dir, child: content),
          ),
        );

    Widget? tail;
    final list = reservationsAsync.when<Widget?>(
      data: (reservations) {
        if (reservations.isEmpty) {
          return swipeable(Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: all.isEmpty ? const _EmptyAll() : _EmptyFilter(onShowAll: () => _setFilter('all')),
          ));
        }
        // Jen jedna karta s tmavým pruhem a rank CTA (ta, která čeká na akci).
        final primaryId = resPrimaryCardId(reservations, pending);
        Widget cardAt(int index) {
          final res = reservations[index];
          final card = ReservationCardV2(
            reservation: res,
            payFlag: resPayFlag(res, pending),
            primary: res.id == primaryId,
            onTap: () => context.push('/reservations/${res.id}'),
            onEdit: () => context.push('/reservations/${res.id}/edit'),
            // „Obnovit" = obnovit a zaplatit (D3), stejně jako starý seznam.
            onRestore: () => restoreAndPay(context, ref, res),
          );
          // Only the first screenful reveals, once per app session — a
          // card scrolled back into view never blinks again.
          return Padding(
            key: ValueKey(res.id),
            padding: const EdgeInsets.only(bottom: 12),
            child: index < 6 ? MgReveal(index: index, sessionKey: 'res-list', child: card) : card,
          );
        }

        // The first screenfuls follow the finger + slide in; the rest is a
        // LAZY sliver list (long histories never build / repaint at once) —
        // a swipe there switches through the page-level twin.
        final head = reservations.length < kResSwipeHead ? reservations.length : kResSwipeHead;
        if (reservations.length > head) {
          tail = SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.builder(
              itemCount: reservations.length - head,
              itemBuilder: (context, i) => cardAt(head + i),
            ),
          );
        }
        return swipeable(Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var index = 0; index < head; index++) cardAt(index),
          ]),
        ));
      },
      // Kostra ve tvaru karet (žádný holý spinner, žádný skok po načtení).
      loading: () => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: ResListSkeletonV2(onRetry: retry),
      ),
      error: (_, __) => null,
    );
    final errorSliver = reservationsAsync.whenOrNull<Widget>(
      error: (e, _) => SliverFillRemaining(
        hasScrollBody: false,
        child: MgErrorView(
          error: e,
          what: tr.tr('fxReservationsLoadFail'),
          onRetry: retry,
          onBack: () => context.go(Routes.home),
          contact: false,
        ),
      ),
    );

    final lazyTail = tail;
    return V2PageSwipe(
      // Header, tabs, empty space and the lazy rest switch the filter too
      // (the page-wide swipe of before); the body below follows the finger.
      onStep: _step,
      child: MgPage(
        tabIndex: 2,
        overlapHero: false,
        header: const ResListHeaderV2(),
        onRefresh: _refresh,
        sections: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: ResFilterTabsV2(
              value: filter,
              counts: src.hasValue ? counts : null,
              onSelect: _setFilter,
              onStep: _swipeFilter,
              dragProgress: _drag,
            ),
          ),
          if (stale) MgStaleNote(onRetry: retry),
          if (list != null) list,
        ],
        slivers: [if (lazyTail != null) lazyTail, if (errorSliver != null) errorSliver],
      ),
    );
  }
}

/// No reservation at all: the one dark rank block with the looping CTA.
class _EmptyAll extends StatelessWidget {
  const _EmptyAll();

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return MgDarkHero(
      rankAura: true,
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
      child: Column(children: [
        MgPop(
          playOnMount: true,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: MgColors.neonA(0.12), shape: BoxShape.circle),
            child: const Center(child: MgIcon(MgIcons.calendarCheck, size: 34, color: MgColors.neon)),
          ),
        ),
        const SizedBox(height: 16),
        Text(tr.tr('v2ResEmptyTitle'),
            textAlign: TextAlign.center, style: MgType.h3.copyWith(color: MgColors.onDark)),
        const SizedBox(height: 8),
        Text(tr.tr('v2ResEmptyBody'),
            textAlign: TextAlign.center, style: MgType.body.copyWith(color: MgColors.onDarkLead)),
        const SizedBox(height: 20),
        MgCta(label: tr.tr('noResBookCta'), onTap: () => context.go(Routes.search), loop: true, arrow: true),
      ]),
    );
  }
}

/// The chosen filter has nothing, other filters do → one tap back to "Vše".
class _EmptyFilter extends StatelessWidget {
  final VoidCallback onShowAll;
  const _EmptyFilter({required this.onShowAll});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Semantics(
      button: true,
      label: '${tr.tr('v2ResFilterEmpty')} ${tr.tr('v2ResShowAll')}',
      excludeSemantics: true,
      child: MgPress(
        onTap: onShowAll,
        child: Container(
          constraints: const BoxConstraints(minHeight: 120),
          padding: const EdgeInsets.all(16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: MgColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MgColors.line, width: 1.5),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const MgIcon(MgIcons.filter, size: 24, color: MgColors.meta),
            const SizedBox(height: 8),
            Text(tr.tr('v2ResFilterEmpty'),
                textAlign: TextAlign.center, style: MgType.body.copyWith(color: MgColors.lead)),
            const SizedBox(height: 4),
            Text(tr.tr('v2ResShowAll'),
                textAlign: TextAlign.center,
                style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.link)),
          ]),
        ),
      ),
    );
  }
}
