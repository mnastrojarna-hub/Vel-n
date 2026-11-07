import 'package:flutter/widgets.dart';

/// Carousel physics snapping to whole cards (design G4 e: Home routes,
/// routes-map point panel, upsell). A fling settles on the nearest snap
/// offset in the fling direction, a slow release on the nearest one.
/// Snap offsets = [leadingInset] + k × [itemExtent] (card width + gap),
/// clamped to the scroll extent. Use with a 24–48 px peek of the next card.
class MgSnapScrollPhysics extends ScrollPhysics {
  final double itemExtent;
  final double leadingInset;
  const MgSnapScrollPhysics({required this.itemExtent, this.leadingInset = 0, super.parent});

  @override
  MgSnapScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      MgSnapScrollPhysics(itemExtent: itemExtent, leadingInset: leadingInset, parent: buildParent(ancestor));

  /// Snap target for a release at [position] with [velocity] (px/s).
  double targetFor(ScrollMetrics position, double velocity, Tolerance tolerance) {
    final page = (position.pixels - leadingInset) / itemExtent;
    final double k;
    if (velocity.abs() < tolerance.velocity * 10) {
      k = page.roundToDouble();
    } else if (velocity > 0) {
      k = (page + 1e-3).ceilToDouble();
    } else {
      k = (page - 1e-3).floorToDouble();
    }
    return (leadingInset + k * itemExtent).clamp(position.minScrollExtent, position.maxScrollExtent);
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    final target = targetFor(position, velocity, tolerance);
    if ((target - position.pixels).abs() < tolerance.distance) return null;
    return ScrollSpringSimulation(spring, position.pixels, target, velocity, tolerance: tolerance);
  }

  @override
  bool get allowImplicitScrolling => false;
}
