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
    if (!_enabled) return false;
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
    final user = n.dragDetails != null || _user != ScrollDirection.idle;
    // Programmatic scroll, or the bounce at / beyond the bottom edge.
    if (!user || m.pixels >= m.maxScrollExtent) return false;
    // Content direction: a reversed list (chat) grows upward.
    final d = (n.scrollDelta ?? 0) * (m.axisDirection == AxisDirection.up ? -1 : 1);
    if (d == 0) return false;
    if (_acc != 0 && (d > 0) != (_acc > 0)) _acc = 0;
    _acc += d;
    if (_acc >= hideAfter && range >= minRange) {
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
