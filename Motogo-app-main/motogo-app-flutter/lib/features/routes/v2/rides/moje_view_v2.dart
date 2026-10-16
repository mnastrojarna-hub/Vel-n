import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/feature_flags.dart' show appV2UiProvider;
import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/router.dart' show MotoGoBackNav, Routes;
import '../../../../core/shell_tab_action.dart';
import '../../../../core/v2/chrome/mg_chrome_metrics.dart';
import '../../../../core/v2/chrome/mg_page.dart';
import '../../../../core/v2/chrome/v2_nav_bar.dart';
import '../../../../core/v2/shell/shell_nav_map.dart' show kV2TabRoutes;
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/widgets/mg_back.dart' show mgIsTopmost;
import '../../active_ride_provider.dart' show ActiveRide;
import '../../community_submit.dart' show showCommunityAddMenu;
import '../../my_experiences_provider.dart';
import '../../ride_model.dart';
import '../../ride_recorder.dart' show RideRecorderState;
import '../record_dock_v2.dart';
import '../trasy_hub_header_v2.dart';
import 'moje_lists_v2.dart';
import 'moje_summary_v2.dart';
import 'moje_tabs_v2.dart';
import 'recorder_screen_v2.dart';

/// v2 tab tap from Moje zážitky (outside the shell): the shared PM-1 action
/// (payment-running confirm, Home reset), then the flag's safe point — the
/// same as `AppShellV2._onTab` for a non-root location.
Future<void> mojeNavTab(BuildContext context, WidgetRef ref, int i) async {
  final route = kV2TabRoutes[i];
  final flag = ref.read(appV2UiProvider.notifier);
  await onShellTabTap(context, ref, route: route, isActive: false, isHome: i == 0, location: '/my-experiences');
  flag.applyPendingIfSafe(route);
}

/// v2 "Moje zážitky" (board Zazitky): Trasy hub header (Moje active), white
/// summary, sub-chips Jízdy · Uložené trasy · Objevená místa · Historie
/// navigace (swipe still switches), the record dock and the v2 nav (the
/// route lives outside the shell). A dumb view: data + callbacks from
/// `_MyExperiencesScreenState` (seam); local state = UI only (sub-chip
/// within the old first tab, ride filter, hint open).
class MojeViewV2 extends StatefulWidget {
  final bool loggedIn;
  final int tab;
  final ValueChanged<int> onTab;
  final AsyncValue<List<UserRide>> rides;
  final AsyncValue<List<SavedRoute>> routes;
  final AsyncValue<List<VisitedPlace>> places;
  final ActiveRide? active;
  final List<ActiveRide> history;
  final RideRecorderState rec;
  final int unread;
  final VoidCallback onBack;
  final Future<void> Function() onRefresh;
  final ValueChanged<int> onNavTab;
  final VoidCallback onCreateRoute;
  final VoidCallback onLogin;
  final ValueChanged<bool> onAutoRecord;
  final ValueChanged<SavedRoute> onOpenSaved;
  final ValueChanged<SavedRoute> onNavSaved;
  final ValueChanged<SavedRoute> onDeleteSaved;
  final VoidCallback onRetrySaved;
  final void Function(VisitedPlace place, List<VisitedPlace> all) onOpenPlace;
  final ValueChanged<VisitedPlace> onNavPlace;
  final VoidCallback onRetryPlaces;
  final void Function(ActiveRide ride, List<ActiveRide> all) onOpenHistory;
  final void Function(ActiveRide ride, bool isActive) onHistoryGo;
  final void Function(ActiveRide ride, bool isActive) onHistoryDelete;

  const MojeViewV2({
    super.key,
    required this.loggedIn,
    required this.tab,
    required this.onTab,
    required this.rides,
    required this.routes,
    required this.places,
    required this.active,
    required this.history,
    required this.rec,
    required this.unread,
    required this.onBack,
    required this.onRefresh,
    required this.onNavTab,
    required this.onCreateRoute,
    required this.onLogin,
    required this.onAutoRecord,
    required this.onOpenSaved,
    required this.onNavSaved,
    required this.onDeleteSaved,
    required this.onRetrySaved,
    required this.onOpenPlace,
    required this.onNavPlace,
    required this.onRetryPlaces,
    required this.onOpenHistory,
    required this.onHistoryGo,
    required this.onHistoryDelete,
  });

  @override
  State<MojeViewV2> createState() => _MojeViewV2State();
}

class _MojeViewV2State extends State<MojeViewV2> {
  final MgShellChrome _chrome = MgShellChrome();
  bool _saved = false;
  RideFilter _filter = RideFilter.all;
  bool _hint = false;
  double _dx = 0;

  @override
  void dispose() {
    // The dock / avoid zones unregister in post-frame callbacks (scheduled
    // by the children, which are disposed first) → dispose after them.
    final c = _chrome;
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    super.dispose();
  }

  MojeSub get _sub => switch (widget.tab) {
        0 => _saved ? MojeSub.saved : MojeSub.rides,
        1 => MojeSub.places,
        _ => MojeSub.history,
      };

  void _select(MojeSub s, [RideFilter? f]) {
    setState(() {
      if (s == MojeSub.rides || s == MojeSub.saved) _saved = s == MojeSub.saved;
      if (f != null) _filter = f;
    });
    widget.onTab(switch (s) {
      MojeSub.rides || MojeSub.saved => 0,
      MojeSub.places => 1,
      MojeSub.history => 2,
    });
  }

  void _swipe(int delta) {
    final i = MojeSub.values.indexOf(_sub) + delta;
    if (i < 0 || i >= MojeSub.values.length) return;
    _select(MojeSub.values[i]);
  }

  void _segment(TrasySeg s) {
    // Moje leží mimo shell → na Místa / Trasy vždy `go` (ne pop do Domů).
    if (s == TrasySeg.places) context.go(Routes.routes);
    if (s == TrasySeg.routes) context.go(Routes.routesList);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final rides = w.rides.valueOrNull ?? const <UserRide>[];
    final historyItems = <ActiveRide>[if (w.active != null) w.active!, ...w.history];
    final sub = _sub;
    final lists = MojeListsV2(
      sub: sub,
      data: w,
      rides: rides,
      historyItems: historyItems,
      filter: _filter,
      onFilter: (f) => setState(() => _filter = f),
      hintOpen: _hint,
      onHint: () => setState(() => _hint = !_hint),
      onOpenRecorder: () => openRideRecorderV2(context),
      onHistoryTab: () => _select(MojeSub.history),
    );
    final page = MgPage(
      overlapHero: false,
      onRefresh: w.loggedIn && sub != MojeSub.history ? w.onRefresh : null,
      header: TrasyHubHeaderV2(
        seg: TrasySeg.mine,
        onSegment: _segment,
        onBack: w.onBack,
        onMap: () => context.pushOrGo(Routes.placesMap),
        mapLabel: t(context).tr('placesMapTitle'),
        onAdd: () => showCommunityAddMenu(context),
      ),
      sections: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: MojeSummaryV2(
            loggedIn: w.loggedIn,
            rides: rides,
            savedCount: w.routes.valueOrNull?.length,
            placesCount: w.places.valueOrNull?.length,
            onSub: _select,
            onCreateRoute: w.onCreateRoute,
            onLogin: w.onLogin,
          ),
        ),
        const SizedBox(height: 16),
        MojeSubChipsV2(
          value: sub,
          onChanged: _select,
          counts: {
            MojeSub.rides: w.loggedIn ? w.rides.valueOrNull?.length : null,
            MojeSub.saved: w.loggedIn ? w.routes.valueOrNull?.length : null,
            MojeSub.places: w.loggedIn ? w.places.valueOrNull?.length : null,
            MojeSub.history: historyItems.length,
          },
        ),
        const SizedBox(height: 12),
      ],
      slivers: [lists],
      dock: TrasyRecordDockV2(onOpenRecorder: () => openRideRecorderV2(context)),
    );
    return Scaffold(
      backgroundColor: MgColors.canvas,
      body: MgChromeScope(
        chrome: _chrome,
        navVisible: true,
        fabVisible: false,
        child: GestureDetector(
          // Záložky šly i dřív přepínat swipem do stran.
          onHorizontalDragStart: (_) => _dx = 0,
          onHorizontalDragUpdate: (d) => _dx += d.delta.dx,
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v.abs() < 300 && _dx.abs() < 80) return;
            if (!mgIsTopmost(context)) return;
            _swipe((v.abs() >= 300 ? v < 0 : _dx < 0) ? 1 : -1);
          },
          child: page,
        ),
      ),
      bottomNavigationBar: V2NavBar(activeIndex: 3, onTap: w.onNavTab, profileBadge: w.unread),
    );
  }
}
