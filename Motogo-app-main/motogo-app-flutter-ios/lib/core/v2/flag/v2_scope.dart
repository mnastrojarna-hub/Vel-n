import 'package:flutter/widgets.dart';

/// Kill-switch scope of the v2 look (`app_v2_ui`, PLAN §0.3 / §3). Inserted
/// ONCE in `MaterialApp.router(builder:)` from `appV2UiProvider`, so every
/// route, sheet and dialog can ask [MgV2.on]. No scope = OFF (old UI) — the
/// pre-existing tests and any early frame keep the old screens.
class MgV2Scope extends InheritedWidget {
  final bool enabled;
  const MgV2Scope({super.key, required this.enabled, required super.child});

  @override
  bool updateShouldNotify(MgV2Scope oldWidget) => oldWidget.enabled != enabled;
}

abstract final class MgV2 {
  /// true = draw the v2 look. Registers a dependency, so the caller rebuilds
  /// when the flag is applied.
  static bool on(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MgV2Scope>()?.enabled ?? false;

  /// Same as [on] without a dependency (callbacks, one-off checks).
  static bool peek(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MgV2Scope>()?.enabled ?? false;
}

/// `MgV2.on(context) ? v2 : v1` — used by the router for rebuilt screens and
/// the shell. Exactly one of the two is built.
class V2Switch extends StatelessWidget {
  final Widget v1;
  final Widget v2;
  const V2Switch({super.key, required this.v1, required this.v2});

  @override
  Widget build(BuildContext context) => MgV2.on(context) ? v2 : v1;
}

/// Tab roots of the v2 nav — the only places where a pending flag change may
/// be applied (never inside a focused flow / payment).
const List<String> kV2TabRoots = ['/', '/search', '/reservations', '/routes', '/profile'];
