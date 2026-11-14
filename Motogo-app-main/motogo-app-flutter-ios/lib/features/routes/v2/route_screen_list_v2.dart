import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/v2/chrome/mg_status_bar.dart';
import '../../../core/v2/gestures/mg_zone_snap.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../routes_model.dart';
import '../routes_provider.dart' show lastOpenedRouteProvider;
import 'route_card_photos_v2.dart';

/// Gap between two full-screen route cards (as the bikes).
const double kRouteScreenGap = 8;

/// Builds the card of route [index]; [open] = the list's open.
typedef RouteScreenCardBuilder = Widget Function(BuildContext context, int index, VoidCallback open);

/// The Trasy list as one route per screen (owner 5.0.1, "stejně jako
/// motorky"): each card [height] tall + [kRouteScreenGap] in the [zone]
/// the page physics snap on (one route per swipe), a night status-bar
/// region per card. While a detail opened from HERE covers the list it
/// follows [lastOpenedRouteProvider] (the detail's own sideways swipe
/// writes it): Back lands on the route seen last. Every card that builds
/// warms the photos of the NEXT route only ([precacheRouteCard]).
class RouteScreenList extends ConsumerStatefulWidget {
  final List<RouteItem> routes;
  final MgSnapZone zone;
  final double height;
  final ValueChanged<int> onOpen;
  final RouteScreenCardBuilder card;

  const RouteScreenList({
    super.key,
    required this.routes,
    required this.zone,
    required this.height,
    required this.onOpen,
    required this.card,
  });

  @override
  ConsumerState<RouteScreenList> createState() => _RouteScreenListState();
}

class _RouteScreenListState extends ConsumerState<RouteScreenList> {
  ModalRoute<dynamic>? _route;
  final Set<String> _warm = {};

  /// The tapped route: its own first write must not move the list.
  String? _skip;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  void _open(int i) {
    _skip = widget.routes[i].id;
    widget.onOpen(i);
  }

  void _follow(String? id) {
    final skip = id == _skip;
    _skip = null;
    if (id == null || skip || !mounted) return;
    // After the frame: "Od zvolené trasy" re-sorts the list on the same
    // write, so the index is looked up in the order the list shows then.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final route = _route;
      // Only while covered (a detail on top), never under the finger.
      if (!mounted || route == null || route.isCurrent || !route.isActive) return;
      final i = widget.routes.indexWhere((r) => r.id == id);
      final pos = Scrollable.maybeOf(context)?.position;
      if (i < 0 || pos == null || !pos.hasPixels || !pos.hasContentDimensions) return;
      // Equal cards → the lazy list's estimated extent is exact.
      pos.jumpTo(widget.zone.offsetOf(i).clamp(pos.minScrollExtent, pos.maxScrollExtent));
    });
  }

  void _warmNext(int i) {
    final next = i + 1;
    if (next >= widget.routes.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && next < widget.routes.length) precacheRouteCard(context, widget.routes[next], _warm);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(lastOpenedRouteProvider, (_, id) => _follow(id));
    final routes = widget.routes;
    return MgSnapZoneSliver(
      zone: widget.zone,
      extent: widget.height + kRouteScreenGap,
      count: routes.length,
      reduced: MgMotion.reduced(context),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            _warmNext(i);
            Widget card = MgStatusBar(dark: true, child: widget.card(context, i, () => _open(i)));
            // The first two cards reveal once per session.
            if (i < 2) card = MgReveal(index: i, sessionKey: 'routes-screen-${routes[i].id}', child: card);
            return Padding(
              key: ValueKey('route-screen-${routes[i].id}'),
              padding: const EdgeInsets.only(bottom: kRouteScreenGap),
              child: card,
            );
          },
          childCount: routes.length,
          findChildIndexCallback: (key) {
            if (key is! ValueKey<String>) return null;
            final i = routes.indexWhere((r) => 'route-screen-${r.id}' == key.value);
            return i < 0 ? null : i;
          },
        ),
      ),
    );
  }
}
