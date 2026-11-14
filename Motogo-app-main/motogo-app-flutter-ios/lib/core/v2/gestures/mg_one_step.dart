import 'package:flutter/widgets.dart';

/// "One item per swipe" (owner, v5.0.1: "vždycky chci listovat pouze o
/// jednu … nikdy ne o celý"): where the current swipe began. Written by
/// [MgSwipeAnchorListener] (drag start / scroll end), read by the snap
/// physics ([MgZoneSnapPhysics] through `MgSnapZone.anchor`,
/// [MgOnePagePhysics]), which then never settle further than the
/// neighbour of the item the finger started on. A quick second swipe that
/// interrupts the snap animation counts from the item that animation was
/// heading to, so it simply moves one more.
class MgSwipeAnchor {
  double? _start;
  double? _target;
  double? _origin;

  /// The finger started a drag at [pixels] (scroll offset).
  void dragStart(double pixels) {
    _start = pixels;
    _origin = null;
  }

  /// The scroll came to rest: no swipe is in progress any more (a later
  /// programmatic move — jump, "to the top", follow — is never clamped).
  void settled() {
    _start = null;
    _origin = null;
  }

  /// The physics started a snap animation to [pixels] (null = none).
  void aimed(double? pixels) => _target = pixels;

  /// Offset the current swipe counts from, or null when no drag is in
  /// progress: the snap target the drag interrupted (less than one
  /// [extent] away from where the finger went down), else the drag start.
  /// Fixed for the whole swipe (a re-run of the snap after a layout change
  /// keeps the same origin).
  double? origin(double extent) {
    final s = _start;
    if (s == null) return null;
    final t = _target;
    return _origin ??= t != null && (s - t).abs() < extent - 0.5 ? t : s;
  }
}

/// Feeds [anchor] from the scroll notifications of the scrollable right
/// below it (depth 0, [axis] only — nested photo pagers or inner lists are
/// ignored). Never consumes a notification (pull-to-refresh, hide-on-scroll
/// and the page's own listeners still see them).
class MgSwipeAnchorListener extends StatelessWidget {
  final MgSwipeAnchor anchor;
  final Axis axis;
  final Widget child;
  const MgSwipeAnchorListener({super.key, required this.anchor, this.axis = Axis.vertical, required this.child});

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.depth != 0 || n.metrics.axis != axis) return false;
          if (n is ScrollStartNotification && n.dragDetails != null) {
            anchor.dragStart(n.metrics.pixels);
          } else if (n is ScrollEndNotification) {
            anchor.settled();
          }
          return false;
        },
        child: child,
      );
}

/// Index of the item a swipe starting at [origin] counts from, for items at
/// `first + k × extent`; −1 = the free area above the first item.
int mgSwipeOriginIndex(double origin, double first, double extent) =>
    origin < first - 1 ? -1 : ((origin - first) / extent).round();

/// Velocity for a spring that starts at [from] and must settle at [to]
/// without passing it first: the fling only while it heads to the target,
/// capped so the (over-damped) scroll spring never overshoots into the
/// next item and comes back.
double mgSnapVelocity(double from, double to, double velocity) {
  final d = to - from;
  if (d * velocity <= 0) return 0;
  final cap = 18 * d.abs();
  return velocity.clamp(-cap, cap);
}

/// Page physics for a full-width `PageView` (viewportFraction 1) that move
/// exactly one page per swipe: the release snaps to the nearest page in
/// the fling direction (as `PageScrollPhysics`), clamped to the neighbours
/// of the page the drag started on ([anchor]). Use with
/// `pageSnapping: false` (a PageView otherwise wraps its own page physics
/// around these) and an [MgSwipeAnchorListener] (horizontal) around it.
class MgOnePagePhysics extends ScrollPhysics {
  final MgSwipeAnchor anchor;
  const MgOnePagePhysics({required this.anchor, super.parent});

  @override
  MgOnePagePhysics applyTo(ScrollPhysics? ancestor) => MgOnePagePhysics(anchor: anchor, parent: buildParent(ancestor));

  /// Target page for a release at [pixels] with [velocity] in a viewport of
  /// [extent] px; [origin] = the swipe's origin offset (null = no clamp).
  static int targetPage(double pixels, double extent, double velocity, double minVelocity, double? origin) {
    var page = pixels / extent;
    if (velocity < -minVelocity) {
      page -= 0.5;
    } else if (velocity > minVelocity) {
      page += 0.5;
    }
    var k = page.round();
    if (origin != null) {
      final a = (origin / extent).round();
      k = k.clamp(a - 1, a + 1);
    }
    return k;
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final extent = position.viewportDimension;
    if (extent <= 0) return super.createBallisticSimulation(position, velocity);
    final tolerance = toleranceFor(position);
    final k = targetPage(position.pixels, extent, velocity, tolerance.velocity, anchor.origin(extent));
    final target = (k * extent).clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < tolerance.distance) {
      anchor.aimed(null);
      return null;
    }
    anchor.aimed(target);
    return ScrollSpringSimulation(spring, position.pixels, target, mgSnapVelocity(position.pixels, target, velocity),
        tolerance: tolerance);
  }

  @override
  bool get allowImplicitScrolling => false;
}
