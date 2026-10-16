import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../motion/mg_motion.dart';
import '../shell/shell_nav_map.dart';
import '../tokens/mg_colors.dart';
import 'mg_chrome_metrics.dart';

/// Page scaffold of every v2 screen (PLAN §1.9): [header] (MgRankHero /
/// MgAppBar / MgPhotoHero), [sections] in a scroll view (the first one
/// overlaps the header by 24 px when [overlapHero]), optional [slivers]
/// after them, an optional bottom [dock] (measured; the scroll pads for it)
/// and bottom padding that keeps everything above the strips / AI button.
/// [tabIndex] = the tab this page is the root of: re-tapping the tab
/// scrolls to the top. [onRefresh] = pull-to-refresh with the caller's
/// EXISTING refresh action.
class MgPage extends ConsumerStatefulWidget {
  final Widget? header;
  final List<Widget> sections;
  final List<Widget> slivers;
  final Widget? dock;
  final Color background;
  final bool overlapHero;
  final double overlap;
  final Future<void> Function()? onRefresh;
  final ScrollController? controller;
  final int? tabIndex;
  final EdgeInsetsGeometry sectionPadding;

  const MgPage({
    super.key,
    this.header,
    this.sections = const [],
    this.slivers = const [],
    this.dock,
    this.background = MgColors.canvas,
    this.overlapHero = true,
    this.overlap = 24,
    this.onRefresh,
    this.controller,
    this.tabIndex,
    this.sectionPadding = EdgeInsets.zero,
  });

  @override
  ConsumerState<MgPage> createState() => _MgPageState();
}

class _MgPageState extends ConsumerState<MgPage> {
  ScrollController? _own;
  double _dockH = 0;

  ScrollController get _ctrl => widget.controller ?? (_own ??= ScrollController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  void _toTop() {
    if (!_ctrl.hasClients) return;
    if (MgMotion.reduced(context)) {
      _ctrl.jumpTo(0);
    } else {
      _ctrl.animateTo(0, duration: MgMotion.sheet, curve: MgMotion.out);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tabIndex != null) {
      ref.listen<(int, int)>(v2TabReselectProvider, (prev, next) {
        if (next.$1 == widget.tabIndex && next != prev) _toTop();
      });
    }
    final overlap = widget.overlapHero && widget.header != null && widget.sections.isNotEmpty ? widget.overlap : 0.0;
    final bottomPad = (widget.dock != null ? _dockH + 12 : MgChrome.bottomObstruction(context)) - overlap;
    final content = <Widget>[
      if (widget.header != null) SliverToBoxAdapter(child: widget.header),
      if (widget.sections.isNotEmpty)
        SliverToBoxAdapter(
          child: Transform.translate(
            offset: Offset(0, -overlap),
            child: Padding(
              padding: widget.sectionPadding,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: widget.sections),
            ),
          ),
        ),
      ...widget.slivers,
      SliverToBoxAdapter(child: SizedBox(height: bottomPad < 0 ? 0 : bottomPad)),
    ];
    Widget scroll = CustomScrollView(
      controller: _ctrl,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: content,
    );
    if (widget.onRefresh != null) {
      scroll = RefreshIndicator(
        onRefresh: widget.onRefresh!,
        color: MgColors.onNeon,
        backgroundColor: MgColors.neon,
        child: scroll,
      );
    }
    return Material(
      color: widget.background,
      child: Stack(children: [
        Positioned.fill(child: scroll),
        if (widget.dock != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MgSizeReporter(
              onSize: (s) {
                if (mounted && (s.height - _dockH).abs() > 0.5) setState(() => _dockH = s.height);
              },
              child: widget.dock!,
            ),
          ),
      ]),
    );
  }
}
