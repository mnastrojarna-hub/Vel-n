import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/v2/chrome/mg_chrome_metrics.dart';
import '../../../core/v2/chrome/mg_status_bar.dart';
import '../../../core/v2/gestures/mg_zone_snap.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../catalog_provider.dart' show filteredMotoIdsProvider;

/// The bike the v2 detail pager shows right now (`MotoDetailPagerV2View`).
/// The list the detail was opened from follows it while covered, so going
/// back lands on the bike seen last — not on the top, not on the tapped one.
final catalogShownMotoProvider = StateProvider<String?>((_) => null);

/// Gap between two full-screen bike cards.
const double kBikeScreenGap = 8;

/// "One bike per screen" (owner 2026-11-08): a card as tall as the shell
/// body with the hide-on-scroll chrome folded; never below the old 460.
double bikeScreenHeight(BuildContext context) {
  final folded = MgChromeScope.maybeOf(context)?.foldedViewport ?? 0;
  final h = folded > 0 ? folded : MediaQuery.sizeOf(context).height;
  return math.max(460.0, h);
}

/// Builds the card of bike [index]; [open] = the list's open (it remembers
/// the tapped bike, then calls the caller's own open).
typedef BikeScreenCardBuilder = Widget Function(BuildContext context, int index, VoidCallback open);

/// The bike list of Domů / Motorky as one card per screen: each card
/// [height] tall + [kBikeScreenGap], a night status-bar region (light icons
/// over the card), the [zone] the page physics settle on (gentle snap after
/// the finger lifts; none under reduced motion) and, while a detail opened
/// from HERE covers the list, it follows [catalogShownMotoProvider]: the
/// card of the bike shown last is at the top when the customer comes back.
/// [onOpen] = the caller's existing open (sibling ids + push).
class BikeScreenList extends ConsumerStatefulWidget {
  final List<String> ids;
  final MgSnapZone zone;
  final double height;
  final ValueChanged<int> onOpen;
  final BikeScreenCardBuilder card;

  const BikeScreenList({
    super.key,
    required this.ids,
    required this.zone,
    required this.height,
    required this.onOpen,
    required this.card,
  });

  @override
  ConsumerState<BikeScreenList> createState() => _BikeScreenListState();
}

class _BikeScreenListState extends ConsumerState<BikeScreenList> {
  ModalRoute<dynamic>? _route;

  /// The tapped bike: the detail's first publish is that bike (the list is
  /// already there) and must not move the list during the push.
  String? _skip;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  void _open(int i) {
    _skip = widget.ids[i];
    widget.onOpen(i);
  }

  void _follow(String? id) {
    final skip = id == _skip;
    _skip = null;
    if (id == null || skip || !mounted) return;
    final route = _route;
    if (route == null || route.isCurrent || !route.isActive) return;
    // Only a detail opened from THIS list (its ids are the pager's).
    if (!listEquals(ref.read(filteredMotoIdsProvider), widget.ids)) return;
    final i = widget.ids.indexOf(id);
    final pos = Scrollable.maybeOf(context)?.position;
    if (i < 0 || pos == null || !pos.hasPixels || !pos.hasContentDimensions) return;
    // Equal cards → the lazy list's estimated extent is exact.
    pos.jumpTo(widget.zone.offsetOf(i).clamp(pos.minScrollExtent, pos.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(catalogShownMotoProvider, (_, id) => _follow(id));
    final ids = widget.ids;
    return MgSnapZoneSliver(
      zone: widget.zone,
      extent: widget.height + kBikeScreenGap,
      count: ids.length,
      reduced: MgMotion.reduced(context),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => Padding(
            key: ValueKey('bike-screen-${ids[i]}'),
            padding: const EdgeInsets.only(bottom: kBikeScreenGap),
            // A night card under the status bar → light icons.
            child: MgStatusBar(dark: true, child: widget.card(context, i, () => _open(i))),
          ),
          childCount: ids.length,
        ),
      ),
    );
  }
}
