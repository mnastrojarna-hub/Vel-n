import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_segmented.dart';
import '../../../../core/v2/widgets/mg_skeleton.dart';
import '../../../../core/widgets/state_views.dart' show MgErrorView;
import '../../active_ride_provider.dart' show ActiveRide;
import '../../ride_model.dart';
import 'moje_cards_v2.dart';
import 'moje_tabs_v2.dart';
import 'moje_view_v2.dart' show MojeViewV2;
import 'ride_card_v2.dart';

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
          KeyedSubtree(
            key: ValueKey(sub),
            child: MgEnter(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
          ),
        ],
      ),
    );
  }

  static const _gap = SizedBox(height: 10);

  List<Widget> _skeletons() => const [
        MgSkeletonCard(imageHeight: 72),
        SizedBox(height: 10),
        MgSkeletonCard(imageHeight: 72),
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

  List<Widget> _rides(BuildContext context) {
    final tr = t(context);
    final rec = data.rec;
    final mg = rides.where((r) => r.bookingId != null).toList();
    final pv = rides.where((r) => r.bookingId == null).toList();
    final shown = switch (filter) {
      RideFilter.all => rides,
      RideFilter.motogo => mg,
      RideFilter.private => pv,
    };
    final ids = [for (final r in shown) r.id];
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
        MgSegmented<RideFilter>(
          value: filter,
          onChanged: onFilter,
          segments: [
            MgSegment(value: RideFilter.all, label: tr.tr('v2RideFilterAll'), sub: '${rides.length}'),
            MgSegment(value: RideFilter.motogo, label: tr.tr('v2RideFilterMg'), sub: '${mg.length}'),
            MgSegment(value: RideFilter.private, label: tr.tr('v2RideFilterPriv'), sub: '${pv.length}'),
          ],
        ),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          MojeEmptyV2(icon: MgIcons.filter, title: tr.tr('v2RideEmptyFilter'))
        else
          for (var i = 0; i < shown.length; i++)
            _reveal(i, 'ride-${shown[i].id}', RideCardV2(ride: shown[i], siblingIds: ids)),
      ],
    ];
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
