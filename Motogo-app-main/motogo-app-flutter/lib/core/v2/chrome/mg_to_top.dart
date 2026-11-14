import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/i18n_provider.dart';
import '../gestures/mg_zone_snap.dart';
import '../icons/mg_icon.dart';
import '../motion/mg_anim.dart';
import '../motion/mg_motion.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_shadows.dart';
import '../tokens/mg_space.dart';
import 'mg_chrome_metrics.dart';
import 'mg_fab_avoid.dart';
import 'mg_hide_on_scroll.dart';

/// Round "back to the top" arrow (owner v5.0.1: "ta šipka, co tam byla v
/// pravém dolním rohu"; the original look's scroll-to-top button). Sits in
/// the bottom-right corner on the AI button's row, just left of it (the AI
/// button owns the corner in the new look; without it the arrow takes the
/// corner), above the page dock and the status strips, so it never covers
/// the pay strip, the AI button, the dock or the menu. Shown once the
/// customer has left the first item ([mgToTopShouldShow]); folds away with
/// the hide-on-scroll chrome and while a CTA / SOS control lies under it.
/// Tap = [onTap] (the page's own animated scroll to the top).
class MgToTopLayer extends StatefulWidget {
  final ScrollController controller;
  final MgSnapZone? zone;
  final VoidCallback onTap;

  /// Height of the page's own dock (measured by `MgPage`).
  final double dockHeight;

  /// Written with the scroll condition (bars ignored): callers lift what
  /// would sit under the arrow (`MotoCardFullV2.liftExtra` = [kMgToTopSlot]).
  final ValueNotifier<bool>? shown;

  const MgToTopLayer({
    super.key,
    required this.controller,
    required this.onTap,
    this.zone,
    this.dockHeight = 0,
    this.shown,
  });

  @override
  State<MgToTopLayer> createState() => _MgToTopLayerState();
}

/// Room above the menu a caption needs to stay clear of the arrow (bottom
/// gap 12 + centred on the 56 AI disc + 44 disc + 4).
const double kMgToTopSlot = 12 + (MgChrome.fab - MgSize.touch) / 2 + MgSize.touch + 4;

/// Shown once the customer has left the first item of the page's snapped
/// list (half of it scrolled away); a page without one: past 600 px (the
/// original look's rule).
bool mgToTopShouldShow(double offset, MgSnapZone? zone) {
  if (zone != null && zone.count > 0 && zone.extent > 0) return offset > zone.offsetOf(0) + zone.extent / 2;
  return offset > 600;
}

class _MgToTopLayerState extends State<MgToTopLayer> {
  final GlobalKey _key = GlobalKey();
  bool _show = false;
  bool _blocked = false;
  MgShellChrome? _chrome;

  /// A blocked slot is checked again once the captions have moved (the
  /// chrome folds / unfolds in `MgMotion.sticky`).
  Timer? _recheck;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void didUpdateWidget(covariant MgToTopLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_check);
      widget.controller.addListener(_check);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = MgChromeScope.chromeOf(context);
    if (c != _chrome) {
      _chrome?.scrollTick.removeListener(_avoid);
      _chrome = c;
      _chrome?.scrollTick.addListener(_avoid);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_check);
    _chrome?.scrollTick.removeListener(_avoid);
    _recheck?.cancel();
    super.dispose();
  }

  void _check() {
    final c = widget.controller;
    final show = c.hasClients && c.positions.length == 1 && mgToTopShouldShow(c.offset, widget.zone);
    if (show == _show || !mounted) return;
    setState(() => _show = show);
    widget.shown?.value = show;
    if (show) WidgetsBinding.instance.addPostFrameCallback((_) => _avoid());
  }

  /// Scroll went idle: hide while a CTA / SOS control lies under the slot.
  void _avoid() {
    if (!mounted) return;
    final box = _key.currentContext?.findRenderObject();
    var blocked = false;
    if (box is RenderBox && box.attached && box.hasSize) {
      final r = (box.localToGlobal(Offset.zero) & box.size).inflate(4);
      for (final z in _chrome?.zoneRects() ?? const <(Rect, MgAvoidKind)>[]) {
        if ((z.$2 == MgAvoidKind.cta || z.$2 == MgAvoidKind.sos) && z.$1.overlaps(r)) blocked = true;
      }
    }
    if (blocked != _blocked) setState(() => _blocked = blocked);
    _recheck?.cancel();
    if (blocked) _recheck = Timer(MgMotion.sticky * 1.5, _avoid);
  }

  @override
  Widget build(BuildContext context) {
    final scope = MgChromeScope.maybeOf(context);
    final chrome = scope?.notifier;
    final fab = scope?.fabVisible ?? false;
    final base = scope == null || !scope.navVisible ? MediaQuery.paddingOf(context).bottom : 0.0;
    final dock = chrome == null || chrome.dockHeight < widget.dockHeight ? widget.dockHeight : chrome.dockHeight;
    final bottom = 12 + dock + (chrome?.stripsHeight ?? 0) + base + (fab ? (MgChrome.fab - MgSize.touch) / 2 : 0);
    final double right = 16 + (fab ? MgChrome.fab + MgChrome.fabGap : 0);
    final visible = _show && !_blocked && !MgBarsScope.hiddenOf(context);
    return Stack(children: [
      AnimatedPositioned(
        duration: MgMotion.of(context, MgMotion.sticky),
        curve: MgMotion.emphasized,
        right: right,
        bottom: bottom,
        child: IgnorePointer(
          ignoring: !visible,
          child: ExcludeSemantics(
            excluding: !visible,
            child: AnimatedScale(
              key: _key,
              scale: visible ? 1 : 0.6,
              duration: MgMotion.of(context, MgMotion.pop),
              curve: MgMotion.spring,
              child: AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: MgMotion.of(context, MgMotion.color),
                // While shown, the AI coach bubble never lies over it.
                child: _AsZone(
                  on: visible,
                  child: MgToTopDisc(label: t(context).tr('v2UxCoreToTop'), onTap: widget.onTap),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// The arrow itself, the original look's neon disc in the new palette:
/// brand-neon gradient, dark up arrow, a night ring and the AI disc's drop
/// shadow — it reads on white pages, dark bike cards and next to the AI
/// disc alike. 44 px, press scale, button semantics.
class MgToTopDisc extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const MgToTopDisc({super.key = const ValueKey('mg-to-top'), required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: MgPress(
          scale: 0.9,
          onTap: onTap,
          child: Container(
            width: MgSize.touch,
            height: MgSize.touch,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: MgGradients.neon,
              border: Border.all(color: MgColors.night, width: 1.5),
              boxShadow: [
                BoxShadow(color: MgColors.black(0.35), blurRadius: 14, offset: const Offset(0, 6)),
              ],
            ),
            child: const MgIcon(MgIcons.up, size: 20, color: MgColors.onNeon, stroke: 2.4),
          ),
        ),
      );
}

/// [child] as a `keep` avoid zone of the shell chrome while [on].
class _AsZone extends StatelessWidget {
  final bool on;
  final Widget child;
  const _AsZone({required this.on, required this.child});

  @override
  Widget build(BuildContext context) => on ? MgFabAvoid(kind: MgAvoidKind.keep, child: child) : child;
}
