import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A run of equal items inside a vertical page scroll ("one bike per
/// screen", owner 2026-11-08): item k's top lies at [start] + k × [extent]
/// (item + gap). Written by [MgSnapZoneSliver] after every layout, read by
/// [MgZoneSnapPhysics]. Inactive (no snapping) while empty, under reduced
/// motion or when the laid-out items are not all [extent] tall (a card
/// grown by a very large text size).
class MgSnapZone {
  double start = 0;
  double extent = 0;
  int count = 0;
  bool reduced = false;
  bool uniform = true;
  Object? _owner;

  bool get active => extent > 0 && count > 0 && uniform && !reduced;

  /// Scroll offset that puts item [i]'s top at the viewport top.
  double offsetOf(int i) => start + i * extent;
}

/// Page physics that settle a release inside the [zone] on an item top:
/// the natural end of the fling (the parent's own simulation) rounds to the
/// nearest item, a deliberate flick moves at least one item in its
/// direction. Only ballistic (after the finger lifts — never against a
/// drag); outside the zone, out of range (bounce) and while the zone is
/// inactive the parent physics run unchanged.
class MgZoneSnapPhysics extends ScrollPhysics {
  final MgSnapZone zone;
  const MgZoneSnapPhysics({required this.zone, super.parent});

  /// px/s from which a release counts as a flick (≥ one item).
  static const double flick = 300;

  @override
  MgZoneSnapPhysics applyTo(ScrollPhysics? ancestor) => MgZoneSnapPhysics(zone: zone, parent: buildParent(ancestor));

  /// Share of an item above the first one that still pulls into the zone:
  /// the header above the list (filters, dates) stays free to rest on.
  static const double leadIn = 0.25;

  /// Snap offset for a release at [position] whose fling would end at
  /// [natural]; null = not in the zone (free scrolling).
  double? targetFor(ScrollMetrics position, double natural, double velocity) {
    if (!zone.active) return null;
    final e = zone.extent;
    final first = zone.start;
    final last = zone.offsetOf(zone.count - 1);
    if (natural < first - e * leadIn || natural > last + e / 2) return null;
    var k = ((natural - first) / e).round();
    final page = (position.pixels - first) / e;
    if (velocity > flick) {
      k = math.max(k, (page + 1e-3).ceil());
    } else if (velocity < -flick) {
      k = math.min(k, (page - 1e-3).floor());
    }
    // A flick up from the first item leaves the zone into the header.
    if (k < 0) return null;
    k = math.min(k, zone.count - 1);
    return zone.offsetOf(k).clamp(position.minScrollExtent, position.maxScrollExtent);
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    final base = super.createBallisticSimulation(position, velocity);
    if (!zone.active || position.outOfRange) return base;
    var natural = position.pixels;
    if (base != null) {
      final x = base.x(20);
      if (x.isFinite) natural = x;
    }
    natural = natural.clamp(position.minScrollExtent, position.maxScrollExtent);
    final target = targetFor(position, natural, velocity);
    if (target == null) return base;
    final tolerance = toleranceFor(position);
    if ((target - position.pixels).abs() < tolerance.distance && velocity.abs() < tolerance.velocity) return null;
    return ScrollSpringSimulation(spring, position.pixels, target, velocity, tolerance: tolerance);
  }
}

/// Wraps the list sliver of a [MgSnapZone]: after each layout it writes the
/// list's scroll start (`precedingScrollExtent`), [extent], [count] and
/// whether every laid-out item is [extent] tall.
class MgSnapZoneSliver extends SingleChildRenderObjectWidget {
  final MgSnapZone zone;
  final double extent;
  final int count;
  final bool reduced;

  const MgSnapZoneSliver({
    super.key,
    required this.zone,
    required this.extent,
    required this.count,
    this.reduced = false,
    required Widget sliver,
  }) : super(child: sliver);

  @override
  RenderMgSnapZone createRenderObject(BuildContext context) =>
      RenderMgSnapZone(zone: zone, extent: extent, count: count, reduced: reduced);

  @override
  void updateRenderObject(BuildContext context, RenderMgSnapZone renderObject) {
    renderObject
      ..zone = zone
      ..extent = extent
      ..count = count
      ..reduced = reduced
      ..publish();
  }
}

/// Render object of [MgSnapZoneSliver].
class RenderMgSnapZone extends RenderProxySliver {
  RenderMgSnapZone({required this.zone, required this.extent, required this.count, required this.reduced}) {
    publish();
  }

  MgSnapZone zone;
  double extent;
  int count;
  bool reduced;

  void publish() {
    zone
      .._owner = this
      ..extent = extent
      ..count = count
      ..reduced = reduced;
  }

  @override
  void performLayout() {
    super.performLayout();
    publish();
    zone.start = constraints.precedingScrollExtent;
    var uniform = true;
    final c = child;
    if (c is RenderSliverMultiBoxAdaptor) {
      // Item extents from the laid-out items' scroll offsets (a child's size
      // belongs to its own parent).
      double? prev;
      for (var b = c.firstChild; b != null; b = c.childAfter(b)) {
        final o = c.childScrollOffset(b);
        if (o == null) continue;
        if (prev != null && (o - prev - extent).abs() > 1) uniform = false;
        prev = o;
      }
    }
    zone.uniform = uniform;
  }

  @override
  void dispose() {
    // A newer sliver may already own the zone (replaced in the same frame).
    if (identical(zone._owner, this)) zone.count = 0;
    super.dispose();
  }
}
