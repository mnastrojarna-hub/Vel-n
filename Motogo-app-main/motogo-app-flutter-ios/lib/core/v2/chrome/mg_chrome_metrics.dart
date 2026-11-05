import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// What a zone is to the AI button (DESIGN_V2 §4.2 FabAvoid): `cta` / `sos`
/// must never be covered (button goes off), `tap` may be peeked over.
enum MgAvoidKind { cta, sos, tap }

/// Live chrome state of the v2 shell: heights of the status strips and of
/// a screen dock, and the avoid zones registered by `MgFabAvoid`. Provided
/// by `AppShellV2` through [MgChromeScope]; screens outside the shell get
/// none (all zero).
class MgShellChrome extends ChangeNotifier {
  double _strips = 0;
  final Map<Object, (double, bool Function())> _docks = {};
  final Map<Object, (RenderBox? Function(), MgAvoidKind)> _zones = {};
  bool _disposed = false;

  /// Scroll went idle (sequence). A separate listenable: only the AI button
  /// re-checks its slot — layout dependents of the chrome (pages, strips)
  /// do not rebuild after every scroll gesture.
  final ValueNotifier<int> scrollTick = ValueNotifier<int>(0);

  double get stripsHeight => _strips;

  /// Tallest dock on a route that is not covered by another page (a dock
  /// under a pushed screen is invisible and must not lift the strips).
  double get dockHeight {
    var h = 0.0;
    for (final d in _docks.values) {
      if (d.$1 > h && d.$2()) h = d.$1;
    }
    return h;
  }

  int get scrollSeq => scrollTick.value;

  /// Children unregister in post-frame callbacks and may outlive the shell
  /// by a frame (logout, a route outside the shell, the kill-switch) — then
  /// every call is a no-op instead of "used after being disposed".
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void reportStrips(double h) {
    if (_disposed || (h - _strips).abs() < 0.5) return;
    _strips = h;
    _notify();
  }

  void reportDock(Object owner, double h, {bool Function()? visible}) {
    if (_disposed) return;
    final old = _docks[owner];
    _docks[owner] = (h, visible ?? old?.$2 ?? () => true);
    if (old?.$1 != h) _notify();
  }

  void removeDock(Object owner) {
    if (_disposed) return;
    if (_docks.remove(owner) != null) _notify();
  }

  /// A dock's route got covered / uncovered → strips and AI button re-place.
  void dockVisibilityChanged() => _notify();

  void registerZone(Object owner, RenderBox? Function() box, MgAvoidKind kind) {
    if (_disposed) return;
    _zones[owner] = (box, kind);
    _notify();
  }

  void removeZone(Object owner) {
    if (_disposed) return;
    if (_zones.remove(owner) != null) _notify();
  }

  /// Avoid zones in global coordinates (detached boxes are skipped).
  List<(Rect, MgAvoidKind)> zoneRects() {
    final out = <(Rect, MgAvoidKind)>[];
    for (final z in _zones.values) {
      final b = z.$1();
      if (b == null || !b.attached || !b.hasSize) continue;
      final o = b.localToGlobal(Offset.zero);
      out.add((o & b.size, z.$2));
    }
    return out;
  }

  /// Scroll went idle → re-evaluate the AI button placement.
  void scrollIdle() {
    if (_disposed) return;
    scrollTick.value++;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    scrollTick.dispose();
    super.dispose();
  }
}

/// Inherits the shell chrome + whether the nav / AI button are on screen.
class MgChromeScope extends InheritedNotifier<MgShellChrome> {
  final bool navVisible;
  final bool fabVisible;

  const MgChromeScope({
    super.key,
    required MgShellChrome chrome,
    required this.navVisible,
    required this.fabVisible,
    required super.child,
  }) : super(notifier: chrome);

  static MgChromeScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MgChromeScope>();

  /// Without a dependency (callbacks, registration).
  static MgShellChrome? chromeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MgChromeScope>()?.notifier;

  @override
  bool updateShouldNotify(MgChromeScope oldWidget) =>
      oldWidget.navVisible != navVisible ||
      oldWidget.fabVisible != fabVisible ||
      super.updateShouldNotify(oldWidget);
}

/// Chrome geometry (PLAN §1.9). The shell body ends at the top of the nav,
/// so obstructions are measured from the body's bottom edge.
abstract final class MgChrome {
  static const double nav = 64;
  static const double fab = 56;
  static const double fabMini = 44;
  static const double fabGap = 12;
  static const double strip = 52;
  static const double stripGap = 8;

  /// Bottom padding a scroll view in a shell screen needs so nothing ends
  /// under the strips / AI button / nav: strips + FAB 56 + 12 + 24.
  /// Outside the shell: the safe area + 24.
  static double bottomObstruction(BuildContext context) {
    final s = MgChromeScope.maybeOf(context);
    if (s == null) return MediaQuery.paddingOf(context).bottom + 24;
    final c = s.notifier!;
    final fab = s.fabVisible ? MgChrome.fab + fabGap : 0.0;
    final base = s.navVisible ? 0.0 : MediaQuery.paddingOf(context).bottom;
    return base + c.stripsHeight + fab + 24;
  }
}

/// Reports its child's size after layout (no rebuild loops: post-frame and
/// only when it changed).
class MgSizeReporter extends SingleChildRenderObjectWidget {
  final ValueChanged<Size> onSize;
  const MgSizeReporter({super.key, required this.onSize, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => RenderMgSizeReporter(onSize);

  @override
  void updateRenderObject(BuildContext context, RenderMgSizeReporter renderObject) {
    renderObject.onSize = onSize;
  }
}

/// Render object of [MgSizeReporter].
class RenderMgSizeReporter extends RenderProxyBox {
  ValueChanged<Size> onSize;
  Size? _last;
  RenderMgSizeReporter(this.onSize);

  @override
  void performLayout() {
    super.performLayout();
    final s = size;
    if (s == _last) return;
    _last = s;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onSize(s);
    });
  }
}
