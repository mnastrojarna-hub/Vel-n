import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../motion/mg_motion.dart';
import '../shell/shell_nav_map.dart';
import '../tokens/mg_colors.dart';
import '../widgets/mg_back_v2.dart';
import 'mg_chrome_metrics.dart';

/// Page scaffold of every v2 screen (PLAN §1.9): [header] (MgRankHero /
/// MgAppBar / MgPhotoHero), [sections] in a scroll view (the first one
/// overlaps the header by 24 px when [overlapHero]), optional [slivers]
/// after them, an optional bottom [dock] (measured; the scroll pads for it)
/// and bottom padding that keeps everything above the strips / AI button.
/// [tabIndex] = the tab this page is the root of: re-tapping the tab
/// scrolls to the top. [onRefresh] = pull-to-refresh with the caller's
/// EXISTING refresh action. [pinnedBack] = the screen's back action: once
/// the header (with its back disc) scrolls away, a 44 px back disc stays
/// pinned top-left, so a long page always shows a way back (owner rule R6).
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
  final VoidCallback? pinnedBack;

  /// [pinnedBack] as ✕ (result / modal pages).
  final bool pinnedClose;

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
    this.pinnedBack,
    this.pinnedClose = false,
  });

  @override
  ConsumerState<MgPage> createState() => _MgPageState();
}

class _MgPageState extends ConsumerState<MgPage> {
  ScrollController? _own;
  double _dockH = 0;
  double _headerH = 0;

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
    Widget sections() => Transform.translate(
          offset: Offset(0, -overlap),
          child: Padding(
            padding: widget.sectionPadding,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: widget.sections),
          ),
        );
    Widget? header = widget.header;
    if (header != null && widget.pinnedBack != null) {
      header = MgSizeReporter(
        onSize: (s) {
          if (mounted && (s.height - _headerH).abs() > 0.5) setState(() => _headerH = s.height);
        },
        child: header,
      );
    }
    final content = <Widget>[
      // A viewport paints EARLIER slivers on top of later ones, so a sheet
      // overlapping the header must share one box with it (in a Column the
      // later child paints — and takes taps — above the header).
      if (overlap > 0)
        SliverToBoxAdapter(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [header!, sections()],
          ),
        )
      else ...[
        if (header != null) SliverToBoxAdapter(child: header),
        if (widget.sections.isNotEmpty) SliverToBoxAdapter(child: sections()),
      ],
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
        if (widget.pinnedBack != null)
          Positioned(
            left: 12,
            top: MediaQuery.paddingOf(context).top + 8,
            child: _PinnedBack(
              controller: _ctrl,
              // The header's own disc sits in its top ~70 px: show the
              // pinned one just before that part leaves the screen.
              after: _headerH > 0 ? (_headerH - 72).clamp(24.0, double.infinity) : 64,
              close: widget.pinnedClose,
              onTap: widget.pinnedBack!,
            ),
          ),
      ]),
    );
  }
}

/// The pinned back disc of [MgPage] (fades in / out with the scroll; not in
/// the tree while hidden; reduced motion = instant).
class _PinnedBack extends StatelessWidget {
  final ScrollController controller;
  final double after;
  final bool close;
  final VoidCallback onTap;
  const _PinnedBack({required this.controller, required this.after, required this.close, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = MgMotion.of(context, MgMotion.color);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final px = controller.hasClients && controller.positions.length == 1 ? controller.position.pixels : 0.0;
        final on = px > after;
        // Only in the tree while shown (no hidden duplicate for semantics /
        // finders); fades in and out (instant under reduced motion).
        return AnimatedSwitcher(
          duration: d,
          child: on
              ? MgV2Back(key: const ValueKey('mg-pinned-back'), onTap: onTap, close: close, style: MgBackStyle.photo)
              : const SizedBox.shrink(),
        );
      },
    );
  }
}
