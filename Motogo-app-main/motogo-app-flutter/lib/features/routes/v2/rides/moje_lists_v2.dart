import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../rt_v2_text.dart';
import '../../../../core/v2/widgets/mg_surfaces.dart';
import '../../../../core/v2/widgets/mg_row.dart';
import '../../../../core/v2/gestures/mg_swipe_switcher.dart';
import '../../../../core/v2/gestures/mg_swipe.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_format.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_segmented.dart';
import '../../../../core/v2/widgets/mg_skeleton.dart';
import '../../../../core/v2/widgets/mg_word_fit.dart';
import '../../../../core/widgets/state_views.dart' show MgErrorView;
import '../../active_ride_provider.dart' show ActiveRide;
import '../../ride_model.dart';
import '../../ride_trip.dart';
import 'moje_cards_v2.dart';
import 'moje_tabs_v2.dart';
import 'moje_tracks_v2.dart';
import 'moje_view_v2.dart' show MojeViewV2;
import 'ride_card_v2.dart';
import 'ride_merge_v2.dart' show openRideMergeV2;
import 'ride_trip_card_v2.dart';
import 'trip_detail_screen_v2.dart' show openTripDetailV2;

/// The body of the selected Moje sub-screen as one sliver: the same lists,
/// states and actions as the old tabs (login prompt for account data,
/// loading, "what failed + Zkusit znovu", empty texts).
class MojeListsV2 extends StatelessWidget {
  final MojeSub sub;
  final MojeViewV2 data;
  final List<UserRide> rides;
  final List<ActiveRide> historyItems;
  final RideFilter filter;
  final ValueChanged<RideFilter> onFilter;
  final bool hintOpen;
  final VoidCallback onHint;
  final VoidCallback onOpenRecorder;
  final VoidCallback onHistoryTab;

  /// Last sub-tab change (−1 / +1) and the body swipe (F-15).
  final int direction;
  final ValueChanged<MojeSub>? onSwipe;

  /// "Na mapě · 12 míst ›" (F-38) = the header's map action.
  final VoidCallback? onPlacesMap;

  const MojeListsV2({
    super.key,
    required this.sub,
    required this.data,
    required this.rides,
    required this.historyItems,
    required this.filter,
    required this.onFilter,
    required this.hintOpen,
    required this.onHint,
    required this.onOpenRecorder,
    required this.onHistoryTab,
    this.direction = 0,
    this.onSwipe,
    this.onPlacesMap,
  });

  @override
  Widget build(BuildContext context) {
    final children = switch (sub) {
      MojeSub.rides => data.loggedIn ? _rides(context) : [_locked(context)],
      MojeSub.saved => data.loggedIn ? _saved(context) : [_locked(context)],
      MojeSub.places => data.loggedIn ? _places(context) : [_locked(context)],
      MojeSub.history => _history(context),
    };
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.list(
        children: [
          // F-15: the body follows the finger (×.35) and switches to the
          // neighbour sub-tab (tap twin = the chips); the new content slides
          // in from the side it came from.
          MgSwipeSegments<MojeSub>(
            values: MojeSub.values,
            value: sub,
            enabled: onSwipe != null,
            onChanged: (s) => onSwipe?.call(s),
            child: MgSwipeSwitcher(
              switchKey: sub,
              direction: direction,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        ],
      ),
    );
  }

  static const _gap = SizedBox(height: 10);

  // F-18: rows in the final geometry (thumb-left cards), not photo cards.
  List<Widget> _skeletons() => const [
        MgSkeletonRow(thumb: 72),
        SizedBox(height: 16),
        MgSkeletonRow(thumb: 72),
        SizedBox(height: 16),
        MgSkeletonRow(thumb: 72),
      ];

  Widget _reveal(int i, String key, Widget child) =>
      MgReveal(index: i < 6 ? i : 0, sessionKey: 'moje-$key', child: child);

  Widget _locked(BuildContext context) {
    final tr = t(context);
    return MojeEmptyV2(
      icon: MgIcons.lock,
      title: tr.tr('v2RideLockTitle'),
      text: tr.tr('v2RideLockSub'),
      action: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MgBtnInk(label: tr.tr('loginBtn'), neonLabel: true, onTap: data.onLogin),
        const SizedBox(height: 4),
        MgBtnText(label: tr.tr('v2RideLockHistory'), icon: MgIcons.history, onTap: onHistoryTab),
      ]),
    );
  }

  /// Rides of an item (a trip = its rides, newest first like the list).
  static List<UserRide> _members(RideListItem i) => switch (i) {
        RideListItemRide(:final ride) => [ride],
        RideListItemTrip(:final trip) => trip.rides.reversed.toList(),
      };

  List<Widget> _rides(BuildContext context) {
    final tr = t(context);
    final rec = data.rec;
    // Jízdy seskupené do cest (sloučené jezdcem / jedna výpůjčka).
    final items = groupRides(rides);
    final mg = items.where((i) => _members(i).any((r) => r.bookingId != null)).toList();
    final pv = items.where((i) => _members(i).any((r) => r.bookingId == null)).toList();
    final shown = switch (filter) {
      RideFilter.all => items,
      RideFilter.motogo => mg,
      RideFilter.private => pv,
    };
    final shownRides = [for (final i in shown) ..._members(i)];
    final ids = [for (final r in shownRides) r.id];
    return [
      if (rec.recording && rec.gpsLost) ...[const MojeGpsLostV2(), _gap],
      MojeRecordRowV2(
        rec: rec,
        hintOpen: hintOpen,
        onHint: onHint,
        onEnabled: data.onAutoRecord,
        onOpen: onOpenRecorder,
      ),
      const SizedBox(height: 12),
      if (data.rides.isLoading && !data.rides.hasValue)
        ..._skeletons()
      else if (rides.isEmpty)
        MojeEmptyV2(icon: MgIcons.bike, title: tr.tr('v2RideEmptyTitle'), text: tr.tr('v2RideEmptySub'))
      else ...[
        // F-16 (board): one line, dark thumb, inline neon count.
        MgSegmented<RideFilter>(
          value: filter,
          onChanged: onFilter,
          inlineCount: true,
          inkThumb: true,
          counts: {RideFilter.all: items.length, RideFilter.motogo: mg.length, RideFilter.private: pv.length},
          segments: [
            MgSegment(value: RideFilter.all, label: tr.tr('v2RideFilterAll')),
            MgSegment(value: RideFilter.motogo, label: tr.tr('v2RideFilterMg')),
            MgSegment(value: RideFilter.private, label: tr.tr('v2RideFilterPriv')),
          ],
        ),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          MojeEmptyV2(icon: MgIcons.filter, title: tr.tr('v2RideEmptyFilter'))
        else ...[
          // Tmavý hrdina segmentu: všechny jízdy filtru na jedné mapě.
          MojeTracksV2(rides: shownRides, siblingIds: ids),
          const SizedBox(height: 12),
          // Sloučit jízdy do cesty — jen když to server umí a je co slučovat.
          if (rideTripsAvailable(rides, items)) ...[
            MojeMergeRowV2(onTap: () => openRideMergeV2(context)),
            const SizedBox(height: 12),
          ],
          for (var i = 0; i < shown.length; i++) ...[
            // F-33 (board): month head "ŘÍJEN 2026 · 1 · 96 km" when the
            // month changes (display only — from the items shown).
            if (i == 0 || _monthOf(shown[i]) != _monthOf(shown[i - 1])) _monthHead(context, shown, i),
            _reveal(
              i,
              'ride-${_members(shown[i]).first.id}',
              switch (shown[i]) {
                RideListItemRide(:final ride) => RideCardV2(ride: ride, siblingIds: ids),
                RideListItemTrip(:final trip) => RideTripCardV2(trip: trip, onTap: () => openTripDetailV2(context, trip)),
              },
            ),
          ],
        ],
      ],
    ];
  }

  static DateTime _startOf(RideListItem i) => switch (i) {
        RideListItemRide(:final ride) => ride.startedAt.toLocal(),
        RideListItemTrip(:final trip) => trip.from.toLocal(),
      };

  static int _monthOf(RideListItem i) {
    final d = _startOf(i);
    return d.year * 12 + d.month;
  }

  Widget _monthHead(BuildContext context, List<RideListItem> shown, int at) {
    final tr = t(context);
    final m = _monthOf(shown[at]);
    final group = [for (final i in shown) if (_monthOf(i) == m) i];
    final km = group.fold<double>(0, (s, i) => s + _members(i).fold<double>(0, (a, r) => a + r.distanceKm));
    final d = _startOf(shown[at]);
    final label = '${tr.tr('v2CalMonth${d.month}')} ${d.year}'.toUpperCase();
    return Padding(
      padding: EdgeInsets.fromLTRB(4, at == 0 ? 2 : 10, 4, 8),
      child: Semantics(
        header: true,
        child: Row(children: [
          Expanded(child: Text(label, style: MgType.eyebrow.copyWith(color: MgColors.meta))),
          const MgIcon(MgIcons.bike, size: 14, color: MgColors.meta),
          const SizedBox(width: 4),
          Text('${group.length} · ${mgKm(km, tr.lang)}', style: MgType.tab(MgType.meta.copyWith(color: MgColors.meta))),
        ]),
      ),
    );
  }

  List<Widget> _saved(BuildContext context) {
    final tr = t(context);
    return data.routes.when(
      loading: _skeletons,
      // Chyba ≠ „nic tu není": důvod + Zkusit znovu (jako staré Moje).
      error: (e, _) => [
        MgErrorView(compact: true, error: e, what: tr.tr('eoSavedRoutesFail'), onRetry: data.onRetrySaved),
      ],
      data: (routes) => routes.isEmpty
          ? [MojeEmptyV2(icon: MgIcons.bookmark, title: tr.tr('myExpEmptyRoutes'), text: tr.tr('v2RideSavedEmptySub'))]
          : [
              for (var i = 0; i < routes.length; i++)
                _reveal(
                  i,
                  'saved-${routes[i].id}',
                  SavedRouteCardV2(
                    route: routes[i],
                    onOpen: () => data.onOpenSaved(routes[i]),
                    onNavigate: () => data.onNavSaved(routes[i]),
                    onDelete: () => data.onDeleteSaved(routes[i]),
                  ),
                ),
            ],
    );
  }

  List<Widget> _places(BuildContext context) {
    final tr = t(context);
    return data.places.when(
      loading: _skeletons,
      error: (e, _) => [MgErrorView(error: e, what: tr.tr('eoMyPlacesFail'), onRetry: data.onRetryPlaces)],
      data: (places) => places.isEmpty
          ? [MojeEmptyV2(icon: MgIcons.pin, title: tr.tr('myExpEmptyPlaces'), text: tr.tr('myExpEmptyPlacesSub'))]
          : [
              if (onPlacesMap != null) ...[
                MgCard(
                  padding: EdgeInsets.zero,
                  child: MgRow(
                    icon: MgIcons.map,
                    title: tr.tr('placesMapTitle'),
                    trailingValue: rtPlural(tr, 'v2RtPlaces', places.length),
                    chevron: true,
                    onTap: onPlacesMap,
                  ),
                ),
                _gap,
              ],
              for (var i = 0; i < places.length; i++)
                _reveal(
                  i,
                  'place-${places[i].id}',
                  VisitedPlaceCardV2(
                    place: places[i],
                    onOpen: () => data.onOpenPlace(places[i], places),
                    onNavigate: places[i].latLng == null ? null : () => data.onNavPlace(places[i]),
                  ),
                ),
            ],
    );
  }

  List<Widget> _history(BuildContext context) {
    final tr = t(context);
    final items = historyItems;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: Row(children: [
          const MgIcon(MgIcons.history, size: 16, color: MgColors.routeGreen),
          const SizedBox(width: 6),
          Expanded(child: Text(tr.tr('v2RideHistoryNote'), style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.meta))),
        ]),
      ),
      if (items.isEmpty)
        MojeEmptyV2(icon: MgIcons.history, title: tr.tr('myExpHistoryEmpty'), text: tr.tr('myExpHistoryEmptySub'))
      else
        for (var i = 0; i < items.length; i++)
          _reveal(
            i,
            'hist-${items[i].id}',
            HistoryCardV2(
              ride: items[i],
              isActive: data.active != null && i == 0,
              onOpen: () => data.onOpenHistory(items[i], items),
              onGo: () => data.onHistoryGo(items[i], data.active != null && i == 0),
              onDelete: () => data.onHistoryDelete(items[i], data.active != null && i == 0),
            ),
          ),
    ];
  }
}

/// "Sloučit jízdy do cesty" (SPEC §9.2): one light row above the list —
/// a 7-day trip split by nights (older app / server) becomes one trip again.
class MojeMergeRowV2 extends StatelessWidget {
  final VoidCallback onTap;
  const MojeMergeRowV2({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Semantics(
      button: true,
      label: '${tr.tr('v2RpMergeRow')}. ${tr.tr('v2RpMergeRowSub')}',
      excludeSemantics: true,
      child: MgPress(
        scale: 0.98,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            color: MgColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MgColors.line),
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: MgColors.ink, borderRadius: BorderRadius.circular(12)),
              child: const Center(child: MgIcon(MgIcons.route, size: 20, color: MgColors.neon)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                MgWordFit(minScale: 0.8, child: Text(tr.tr('v2RpMergeRow'), style: MgType.title.copyWith(color: MgColors.ink))),
                const SizedBox(height: 2),
                Text(tr.tr('v2RpMergeRowSub'), style: MgType.small.copyWith(color: MgColors.meta)),
              ]),
            ),
            const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.lead),
          ]),
        ),
      ),
    );
  }
}
