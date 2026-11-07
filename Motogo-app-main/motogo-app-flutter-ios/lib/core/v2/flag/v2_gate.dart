import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../feature_flags.dart' show appV2UiProvider;
import '../../widgets/mg_back.dart' show mgCurrentLocation;
import '../tokens/mg_theme_v2.dart';
import 'v2_scope.dart';

/// The kill-switch gate inserted ONCE in `MaterialApp.router(builder:)`
/// around the router's navigator (main.dart): [MgV2Scope] from
/// `appV2UiProvider` (screens ask `MgV2.on`, the router picks with
/// `V2Switch`) and, while ON, the v2 theme overlay (only snackbar / dialog /
/// bottom-sheet / progress shapes — see `MgThemeV2`). OFF = the app theme
/// untouched, every seam builds the old UI.
///
/// It is also the flag's safe point in BOTH looks (the old shell knows
/// nothing about v2): after the cold-start fetch, on every resume (fresh
/// fetch) and whenever [router] lands on a tab root — as the ONLY page of
/// the stack and without a query — a pending value is applied — never
/// inside a flow or a running payment (`applyPendingIfSafe`). So OFF reaches
/// a customer sitting on Domů without a tab tap, and OFF → ON is symmetric.
class MgV2Gate extends ConsumerStatefulWidget {
  final Widget child;

  /// The app router (location for the safe point); null = the gate only
  /// mirrors the flag (tests, early frames).
  final GoRouter? router;
  const MgV2Gate({super.key, required this.child, this.router});

  @override
  ConsumerState<MgV2Gate> createState() => _MgV2GateState();
}

class _MgV2GateState extends ConsumerState<MgV2Gate> with WidgetsBindingObserver {
  GoRouter? _router;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listen(widget.router);
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterColdStart());
  }

  @override
  void didUpdateWidget(covariant MgV2Gate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.router != widget.router) _listen(widget.router);
  }

  void _listen(GoRouter? r) {
    if (r == _router) return;
    _router?.routerDelegate.removeListener(_onRoute);
    _router = r;
    _router?.routerDelegate.addListener(_onRoute);
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_onRoute);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Location for the safe point. A page PUSHED over another (the booking
  /// form's `/profile?edit=personal`, the old form's `/profile`: a tab-root
  /// path, but the customer is mid-booking) → null = no safe point; else the
  /// current location WITH its query (`applyPendingIfSafe` refuses `?edit=…`).
  String? _location() {
    final r = _router;
    if (r == null) return null;
    final loc = mgCurrentLocation(r);
    try {
      final cfg = r.routerDelegate.currentConfiguration;
      if (_hasPushedPage(cfg.matches)) return null;
      return cfg.uri.hasQuery ? '$loc?${cfg.uri.query}' : loc;
    } catch (_) {
      return loc;
    }
  }

  /// A `push` inside the shell lands as an [ImperativeRouteMatch] INSIDE the
  /// [ShellRouteMatch] (`matches.length` stays 1) → walk the shells.
  static bool _hasPushedPage(List<RouteMatchBase> matches) {
    for (final m in matches) {
      if (m is ImperativeRouteMatch) return true;
      if (m is ShellRouteMatch && _hasPushedPage(m.matches)) return true;
    }
    return false;
  }

  void _apply() {
    if (!mounted) return;
    final loc = _location();
    if (loc == null) return;
    final n = ref.read(appV2UiProvider.notifier);
    if (n.pending == null) return;
    n.applyPendingIfSafe(loc);
  }

  Future<void> _afterColdStart() async {
    try {
      await ref.read(appV2UiProvider.notifier).ready;
    } catch (_) {
      return;
    }
    _apply();
  }

  /// Router notifications can come mid-build (redirects) → apply after it.
  void _onRoute() {
    if (!mounted || ref.read(appV2UiProvider.notifier).pending == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _apply());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final n = ref.read(appV2UiProvider.notifier);
    n.refresh().then((_) => _apply(), onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final on = ref.watch(appV2UiProvider);
    MgV2.markApplied(on);
    final base = Theme.of(context);
    return MgV2Scope(
      enabled: on,
      child: Theme(data: on ? MgThemeV2.overlay(base) : base, child: widget.child),
    );
  }
}
