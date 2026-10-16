import 'package:flutter/widgets.dart';

import 'mg_chrome_metrics.dart';

export 'mg_chrome_metrics.dart' show MgAvoidKind;

/// Marks a control the floating AI button must respect (DESIGN_V2 §4.2):
/// `cta` / `sos` → the button goes OFF when it would cover it; `tap` → the
/// button only peeks aside. Screens wrap their primary CTAs and SOS controls
/// in it. Outside the v2 shell it does nothing.
class MgFabAvoid extends StatefulWidget {
  final Widget child;
  final MgAvoidKind kind;
  const MgFabAvoid({super.key, required this.child, this.kind = MgAvoidKind.cta});

  @override
  State<MgFabAvoid> createState() => _MgFabAvoidState();
}

class _MgFabAvoidState extends State<MgFabAvoid> {
  MgShellChrome? _chrome;

  RenderBox? _box() {
    if (!mounted) return null;
    // A zone on a covered route (another page pushed on top) never counts.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return null;
    final ro = context.findRenderObject();
    return ro is RenderBox ? ro : null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = MgChromeScope.chromeOf(context);
    if (c != _chrome) {
      final old = _chrome;
      _chrome = c;
      // Never notify the chrome during build (its scope is an ancestor).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        old?.removeZone(this);
        if (mounted) _chrome?.registerZone(this, _box, widget.kind);
      });
    }
  }

  @override
  void didUpdateWidget(covariant MgFabAvoid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _chrome?.registerZone(this, _box, widget.kind);
      });
    }
  }

  @override
  void dispose() {
    final c = _chrome;
    _chrome = null;
    // Unregister after the frame: notifying during dispose would rebuild
    // listeners while the tree is locked.
    WidgetsBinding.instance.addPostFrameCallback((_) => c?.removeZone(this));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Placement decision of the floating AI button.
enum MgFabState { rest, peek, off }

/// Pure placement rule (unit-tested): the button slot (disc inflated by 8)
/// against the avoid zones — any `cta` / `sos` overlap → off, only `tap`
/// overlaps → peek, otherwise rest.
MgFabState mgFabStateFor(Rect slot, List<(Rect, MgAvoidKind)> zones) {
  final s = slot.inflate(8);
  var peek = false;
  for (final z in zones) {
    if (!z.$1.overlaps(s)) continue;
    if (z.$2 == MgAvoidKind.tap) {
      peek = true;
    } else {
      return MgFabState.off;
    }
  }
  return peek ? MgFabState.peek : MgFabState.rest;
}
