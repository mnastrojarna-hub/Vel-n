import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Hide-on-scroll of the v2 chrome (owner 2026-11-08: "Pokud scrolluju
/// dolů, mělo by se spodní menu zabalit … i celá ta hlavička"): while the
/// customer scrolls the vertical content DOWN the bottom nav and the fixed
/// top parts (shell banner band, the pinned back / collapsed bar of
/// `MgPage`, the detail pager controls) fold away; any scroll UP brings
/// them back at once.
///
/// Only USER scrolling of a vertical scrollable counts (a drag, or the
/// fling that follows it): horizontal pagers / carousels / chip rails,
/// programmatic scrolls (`ensureVisible`, scroll-to-top, a reveal) and the
/// iOS bounce beyond the bottom edge are ignored. Hysteresis: hidden after
/// [hideAfter] px of continuous downward scroll, shown after [showAfter] px
/// upward; always shown at the top (pixels <= min — also after a
/// programmatic scroll-to-top), when the content cannot scroll, on [show]
/// (route change, tab switch, pager page change) and while [enabled] is
/// false (screen reader on).
class MgBarsController extends ChangeNotifier {
  static const double hideAfter = 24;
  static const double showAfter = 8;

  /// Content shorter than this never hides the bars: folding them grows
  /// the viewport (nav 64 px + banner line), and a page that would stop
  /// scrolling then must not flicker.
  static const double minRange = 200;

  bool _hidden = false;
  bool _enabled = true;
  bool _disposed = false;
  double _acc = 0;
  ScrollDirection _user = ScrollDirection.idle;
  final Map<Object, (double, bool Function())> _folds = {};

  /// A popup route (bottom sheet, dialog, menu) is the top route of the
  /// shell navigator (`MgBarsRouteObserver`): its scrolling is not the
  /// page's — folding the nav behind it would move the sheet under the
  /// finger — so nothing counts until it closes.
  bool popupOnTop = false;

  /// A fixed header that folds with the bars (`MgFoldHeader`) also grows
  /// the viewport: [h] px more scroll range are needed before anything
  /// folds (no flicker on a page that would stop scrolling).
  /// [active] = its route is the current one.
  void reportFold(Object owner, double h, bool Function() active) => _folds[owner] = (h, active);

  void removeFold(Object owner) => _folds.remove(owner);

  double get _foldExtra {
    var h = 0.0;
    for (final f in _folds.values) {
      if (f.$2()) h += f.$1;
    }
    return h;
  }

  bool get hidden => _hidden && _enabled;
  bool get enabled => _enabled;

  /// false = never hide (screen reader on): [hidden] reads false at once,
  /// listeners hear it after the frame (set from `didChangeDependencies`,
  /// never notify during a build).
  set enabled(bool v) {
    if (v == _enabled) return;
    _enabled = v;
    if (!v && _hidden) {
      WidgetsBinding.instance.addPostFrameCallback((_) => show());
    }
  }

  /// Bars back (top edge, a new pager page).
  void show() {
    _acc = 0;
    _set(false);
  }

  /// A route change / tab switch: bars back, and a user scroll of the old
  /// page that left mid-fling (its idle never came) is forgotten.
  void reset() {
    _user = ScrollDirection.idle;
    show();
  }

  void _set(bool v) {
    if (_hidden == v || _disposed) return;
    _hidden = v;
    // A scroll moved from inside a build / layout (a jumpTo there) must not
    // mark the listening chrome dirty mid-frame → tell them after it.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  /// Feed every scroll notification of the content; never absorbs it.
  bool handle(ScrollNotification n) {
    final m = n.metrics;
    if (m.axis != Axis.vertical || !m.hasPixels || !m.hasContentDimensions) return false;
    if (!_enabled || popupOnTop) return false;
    final range = m.maxScrollExtent - m.minScrollExtent;
    if (n is UserScrollNotification) {
      _user = n.direction;
      return false;
    }
    if (n is ScrollStartNotification) {
      if (n.dragDetails != null && range <= 0) show();
      return false;
    }
    if (n is OverscrollNotification) {
      // Android: pulling past the top (pull-to-refresh) → shown.
      if (n.overscroll < 0 && m.pixels <= m.minScrollExtent) show();
      return false;
    }
    if (n is! ScrollUpdateNotification) return false;
    if (m.pixels <= m.minScrollExtent) {
      show();
      return false;
    }
    final drag = n.dragDetails != null;
    // Programmatic scroll, or the bounce at / beyond the bottom edge.
    if ((!drag && _user == ScrollDirection.idle) || m.pixels >= m.maxScrollExtent) return false;
    final px = n.scrollDelta ?? 0;
    // After the finger lifts only the fling's own direction counts (`_user`
    // reverse = pixels growing): a snap's spring back to the bike, or a
    // spring's return after an overshoot, is physics — never the customer.
    if (!drag && (px > 0) != (_user == ScrollDirection.reverse)) return false;
    // Content direction: a reversed list (chat) grows upward.
    final d = px * (m.axisDirection == AxisDirection.up ? -1 : 1);
    if (d == 0) return false;
    if (_acc != 0 && (d > 0) != (_acc > 0)) _acc = 0;
    _acc += d;
    if (_acc >= hideAfter && range >= minRange + _foldExtra) {
      _set(true);
    } else if (_acc <= -showAfter) {
      _set(false);
    }
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Inherits the bars state of the nearest [MgHideOnScroll].
class MgBarsScope extends InheritedNotifier<MgBarsController> {
  const MgBarsScope({super.key, required MgBarsController controller, required super.child})
      : super(notifier: controller);

  static MgBarsController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MgBarsScope>()?.notifier;

  /// Without a dependency (callbacks).
  static MgBarsController? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MgBarsScope>()?.notifier;

  /// Whether the folding chrome is folded right now (false without a scope).
  static bool hiddenOf(BuildContext context) => maybeOf(context)?.hidden ?? false;
}

/// Listens to the scrolling of [child] and provides [MgBarsScope]. The v2
/// shell has one around its navigator; an `MgPage` outside the shell makes
/// its own. [controller] = an external one (the shell's); otherwise owned.
class MgHideOnScroll extends StatefulWidget {
  final MgBarsController? controller;
  final Widget child;
  const MgHideOnScroll({super.key, this.controller, required this.child});

  @override
  State<MgHideOnScroll> createState() => _MgHideOnScrollState();
}

class _MgHideOnScrollState extends State<MgHideOnScroll> {
  MgBarsController? _own;

  MgBarsController get _c => widget.controller ?? (_own ??= MgBarsController());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Screen reader on = the bars never fold (everything stays reachable).
    _c.enabled = !MediaQuery.accessibleNavigationOf(context);
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollNotification>(
        onNotification: _c.handle,
        child: MgBarsScope(controller: _c, child: widget.child),
      );
}

/// A screen with its own fixed header (`MgFoldHeader`): inside the v2 shell
/// the shell's bars fold it; on a root route (no scope above) the screen
/// listens to its own scrolling, as an `MgPage` outside the shell does.
class MgBarsHost extends StatelessWidget {
  final Widget child;
  const MgBarsHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) =>
      MgBarsScope.maybeOf(context) == null ? MgHideOnScroll(child: child) : child;
}

/// Observer of the shell navigator (router.dart `ShellRoute.observers`):
/// a new page on top — a push / pop / replace, also a `Navigator.push` the
/// router location never sees (full-screen map, viewers) — brings the bars
/// back; a popup route on top (bottom sheet, dialog, menu) only marks
/// [MgBarsController.popupOnTop] and leaves the bars as they are (the page
/// under it did not change). No-op outside the v2 shell (no scope).
class MgBarsRouteObserver extends NavigatorObserver {
  Route<dynamic>? _page;

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    final ctx = navigator?.context;
    final c = ctx == null ? null : MgBarsScope.read(ctx);
    if (c == null) return;
    final popup = topRoute is PopupRoute;
    c.popupOnTop = popup;
    if (popup || identical(topRoute, _page)) return;
    _page = topRoute;
    c.reset();
  }
}
