import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'mg_motion.dart';

/// Tab switch = fade-through (design M1, v1 §2.7 / §4.1): the incoming tab
/// fades in (easeOut) and scales .98 → 1 over `MgMotion.tab` both ways;
/// reduced motion → the page appears at once.
Page<void> mgTabPage({required LocalKey key, required Widget child}) => CustomTransitionPage<void>(
      key: key,
      child: child,
      transitionDuration: MgMotion.tab,
      reverseTransitionDuration: MgMotion.tab,
      transitionsBuilder: mgTabTransition,
    );

/// The [mgTabPage] transition (public for routers that build own pages).
Widget mgTabTransition(BuildContext context, Animation<double> animation, Animation<double> secondary, Widget child) {
  if (MgMotion.reduced(context)) return child;
  final a = CurvedAnimation(parent: animation, curve: Curves.easeOut);
  return FadeTransition(
    opacity: a,
    child: ScaleTransition(scale: Tween<double>(begin: 0.98, end: 1).animate(a), child: child),
  );
}

/// Push transitions of the v2 look (design M1 / G2): Android predictive back
/// (off under reduced motion), iOS Cupertino — kept even under reduced motion
/// because it hosts the edge-swipe back gesture.
abstract final class MgPageTransitions {
  static PageTransitionsTheme theme() => const PageTransitionsTheme(builders: {
        TargetPlatform.android: _ReducedAware(PredictiveBackPageTransitionsBuilder()),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: ZoomPageTransitionsBuilder(),
        TargetPlatform.linux: ZoomPageTransitionsBuilder(),
      });
}

/// [inner] unless the platform asks for reduced motion (then no transition
/// for the incoming page and none for the page below it).
class _ReducedAware extends PageTransitionsBuilder {
  final PageTransitionsBuilder inner;
  const _ReducedAware(this.inner);

  @override
  Duration get transitionDuration => inner.transitionDuration;

  @override
  Duration get reverseTransitionDuration => inner.reverseTransitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition {
    final d = inner.delegatedTransition;
    if (d == null) return null;
    return (context, animation, secondary, allowSnapshotting, child) =>
        MgMotion.reduced(context) ? child : d(context, animation, secondary, allowSnapshotting, child);
  }

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      MgMotion.reduced(context) ? child : inner.buildTransitions(route, context, animation, secondaryAnimation, child);
}
