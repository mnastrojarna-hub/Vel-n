import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Downward offset of a sheet pulled from its scrolling body (design G3,
/// FND-5). Fed by [MgSheetPullPhysics]; the sheet frame translates by [dy].
class MgSheetPull {
  MgSheetPull(this.onChanged);

  final VoidCallback onChanged;
  double dy = 0;

  /// Adds [d] (finger down > 0, up < 0); never below 0. Returns what it used.
  double add(double d) {
    final before = dy;
    dy = math.max(0.0, dy + d);
    if (dy != before) onChanged();
    return dy - before;
  }

  void reset(double v) {
    if (v == dy) return;
    dy = v;
    onChanged();
  }
}

/// Clamping body physics of a pull-to-dismiss sheet: a downward finger at
/// the scroll top moves the sheet instead of over-scrolling, an upward finger
/// first takes the sheet back, then scrolls; no fling while the sheet is
/// pulled (the release decides pop vs. spring back).
class MgSheetPullPhysics extends ClampingScrollPhysics {
  final MgSheetPull pull;
  const MgSheetPullPhysics(this.pull, {super.parent});

  @override
  MgSheetPullPhysics applyTo(ScrollPhysics? ancestor) => MgSheetPullPhysics(pull, parent: buildParent(ancestor));

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (position.axis != Axis.vertical) return super.applyPhysicsToUserOffset(position, offset);
    final min = position.minScrollExtent;
    if (pull.dy > 0 || (position.pixels <= min && offset > 0)) {
      final rest = offset - pull.add(offset);
      return rest == 0 ? 0 : super.applyPhysicsToUserOffset(position, rest);
    }
    if (offset > 0 && position.pixels - offset < min) {
      final toTop = position.pixels - min;
      pull.add(offset - toTop);
      return toTop;
    }
    return super.applyPhysicsToUserOffset(position, offset);
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) =>
      pull.dy > 0 ? null : super.createBallisticSimulation(position, velocity);
}
