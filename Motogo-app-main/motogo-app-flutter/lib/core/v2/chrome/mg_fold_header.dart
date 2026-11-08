import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../tokens/mg_colors.dart';
import 'mg_chrome_metrics.dart' show MgSizeReporter;
import 'mg_hide_on_scroll.dart';
import 'mg_nav_band.dart';
import 'mg_status_bar.dart';

/// A fixed top header above a scroll body (a Column: header, then the
/// Expanded scroll view) folds with the hide-on-scroll bars (owner
/// 2026-11-08 "celá ta hlavička … ta pevná část, aby se při scrollování
/// zabalovala"): scrolling the content down folds it up to a status-bar
/// strip of [fill] (the icons stay readable), any scroll up, the top edge or
/// a route change bring it back. The header leaves through the top edge and
/// fades (`MgNavBand`, `MgMotion.sticky` + emphasized, instant under reduced
/// motion), the body below grows by the folded part; at rest the header is
/// painted exactly as before. The screen puts its Column in `MgBarsHost`
/// (inside the v2 shell the shell's bars, on a root route its own). The
/// folding height is reported to the bars: a page that would stop scrolling
/// once the header folds never folds it (no flicker).
class MgFoldHeader extends StatefulWidget {
  final Widget child;
  final Color fill;
  const MgFoldHeader({super.key, required this.child, this.fill = MgColors.night});

  @override
  State<MgFoldHeader> createState() => _MgFoldHeaderState();
}

class _MgFoldHeaderState extends State<MgFoldHeader> {
  MgBarsController? _bars;
  ModalRoute<dynamic>? _route;
  double _h = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    final b = MgBarsScope.read(context);
    if (!identical(b, _bars)) {
      _bars?.removeFold(this);
      _bars = b;
      _report();
    }
  }

  /// Counts only while its route is on top (a covered page's header does
  /// not change the page above).
  void _report() => _bars?.reportFold(this, _h, () => _route?.isCurrent ?? true);

  @override
  void dispose() {
    _bars?.removeFold(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return MgStatusBar(
      dark: MgStatusBar.isDark(widget.fill),
      child: MgNavBand(
        folded: MgBarsScope.hiddenOf(context),
        band: top,
        fill: widget.fill,
        child: MgSizeReporter(
          onSize: (s) {
            final h = math.max(0.0, s.height - top);
            if (h == _h || !mounted) return;
            _h = h;
            _report();
          },
          child: widget.child,
        ),
      ),
    );
  }
}
