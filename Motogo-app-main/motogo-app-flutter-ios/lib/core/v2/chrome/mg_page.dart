import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../gestures/mg_zone_snap.dart';
import '../motion/mg_motion.dart';
import '../motion/mg_sticky_slide.dart';
import '../shell/shell_nav_map.dart';
import '../tokens/mg_colors.dart';
import 'mg_chrome_metrics.dart';
import 'mg_hide_on_scroll.dart';
import 'mg_pinned_back.dart';
import 'mg_status_bar.dart';
import 'mg_to_top.dart';

export 'mg_pinned_back.dart' show MgPinnedBack, MgPinnedScope;

/// Page scaffold of every v2 screen (PLAN §1.9): [header] (MgRankHero /
/// MgAppBar / MgPhotoHero), [sections] in a scroll view (the first one
/// overlaps the header by 24 px when [overlapHero]), optional [slivers]
/// after them, an optional bottom [dock] (measured; the scroll pads for it)
/// and bottom padding that keeps everything above the strips / AI button.
/// [tabIndex] = the tab this page is the root of: re-tapping the tab
/// scrolls to the top. [onRefresh] = pull-to-refresh with the caller's
/// EXISTING refresh action. [pinnedBack] = the screen's back action: once
/// the header (with its back disc) scrolls away, a 44 px back disc stays
/// pinned top-left, so a long page always shows a way back (owner rule R6);
/// once the hero is gone too it sits in a compact light bar with
/// [pinnedTitle] (`MgPinnedBack`). Status bar (fix:statusbar): the page
/// declares its [background] through `MgStatusBar`; a dark header / hero and
/// the collapsed pinned bar declare themselves and win while they lie under
/// the status bar, so the icons follow the surface as the page scrolls.
///
/// Pull-to-refresh (design G5): Android neon disc, iOS the adaptive
/// Cupertino spinner in neon. [overscrollColor] (dark-header pages pass
/// `MgColors.night`): what shows above a dark header while iOS rubber-bands
/// — the backdrop follows the header's visible extent, light sections keep
/// the canvas. [pinnedBar] (dark, e.g. a compact title + action bar) slides
/// down from the top once the scroll passes [pinnedBarAfter] (default: the
/// measured header height − 8) and declares light status-bar icons; not
/// together with [pinnedBack]. Hide-on-scroll (owner 2026-11-08): the
/// pinned back / bar fold away while the content scrolls down
/// (`MgBarsScope` of the v2 shell; a page outside the shell listens to its
/// own scroll). [snap] = a "one per screen" zone the scroll settles on;
/// one swipe moves one of its items (`MgZoneSnapPhysics` + the page's
/// `MgSwipeAnchorListener`). [toTop] (opt-in, v5.0.1) = the round
/// "back to the top" arrow bottom-right (`MgToTopLayer`): shown once the
/// first item is left, one tap = the same animated scroll as a tab
/// re-tap; [toTopShown] reports when it shows (lift what it would cover).
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

  /// Title of the collapsed bar around the pinned back (optional).
  final String? pinnedTitle;

  final Color? overscrollColor;
  final Widget? pinnedBar;
  final double? pinnedBarAfter;
  final MgSnapZone? snap;
  final bool toTop;
  final ValueNotifier<bool>? toTopShown;

  /// Opt-in (Profil only): keep the scroll position when [onRefresh]
  /// switches on / off. Off by default, so pages whose refresh follows a
  /// mode (Motorky, Moje jízdy) still open the new mode at the top.
  final bool keepScrollOnRefreshToggle;

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
    this.pinnedTitle,
    this.overscrollColor,
    this.pinnedBar,
    this.pinnedBarAfter,
    this.snap,
    this.toTop = false,
    this.toTopShown,
    this.keepScrollOnRefreshToggle = false,
  }) : assert(pinnedBar == null || pinnedBack == null, 'pinnedBar and pinnedBack exclude each other');

  @override
  ConsumerState<MgPage> createState() => _MgPageState();
}

class _MgPageState extends ConsumerState<MgPage> {
  ScrollController? _own;
  double _dockH = 0;
  double _headerH = 0;
  double _heroH = 0;

  /// With [MgPage.keepScrollOnRefreshToggle]: keeps the scroll view (and
  /// its position) when [MgPage.onRefresh] switches on / off — Profil while
  /// the personal form is open would otherwise jump to the top (K4-02).
  final _scrollKey = GlobalKey(debugLabel: 'mg-page-scroll');

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
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // No header → the first section is the hero: its height decides
              // when the pinned back turns from a photo disc into a bar.
              if (widget.header == null && widget.pinnedBack != null && widget.sections.isNotEmpty) ...[
                MgSizeReporter(
                  onSize: (s) {
                    if (mounted && (s.height - _heroH).abs() > 0.5) setState(() => _heroH = s.height);
                  },
                  child: widget.sections.first,
                ),
                ...widget.sections.skip(1),
              ] else
                ...widget.sections,
            ]),
          ),
        );
    Widget? header = widget.header;
    final measure = widget.pinnedBack != null || widget.overscrollColor != null || widget.pinnedBar != null;
    if (header != null && measure) {
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
      key: widget.keepScrollOnRefreshToggle ? _scrollKey : null,
      controller: _ctrl,
      physics: widget.snap == null
          ? const AlwaysScrollableScrollPhysics()
          : MgZoneSnapPhysics(zone: widget.snap!, parent: const AlwaysScrollableScrollPhysics()),
      slivers: content,
    );
    // One swipe = one item: the snap physics need where the drag began.
    if (widget.snap != null) scroll = MgSwipeAnchorListener(anchor: widget.snap!.anchor, child: scroll);
    if (widget.onRefresh != null) {
      scroll = Theme.of(context).platform == TargetPlatform.iOS
          ? RefreshIndicator.adaptive(onRefresh: widget.onRefresh!, color: MgColors.neon, child: scroll)
          : RefreshIndicator(
              onRefresh: widget.onRefresh!,
              color: MgColors.onNeon,
              backgroundColor: MgColors.neon,
              child: scroll,
            );
    }
    // Outside the v2 shell (no bars scope) the page folds its own chrome.
    final ownBars = MgBarsScope.maybeOf(context) == null;
    final Widget page = MgStatusBar.forColor(
      widget.background,
      child: MgPinnedScope(
        title: widget.pinnedBack != null ? widget.pinnedTitle : null,
        child: Material(
          color: widget.background,
          child: Stack(children: [
            if (widget.overscrollColor != null && widget.header != null)
              _OverscrollBackdrop(controller: _ctrl, extent: _headerH, color: widget.overscrollColor!),
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
            if (widget.toTop)
              Positioned.fill(
                child: MgToTopLayer(
                  controller: _ctrl,
                  zone: widget.snap,
                  dockHeight: widget.dock != null ? _dockH : 0,
                  shown: widget.toTopShown,
                  onTap: _toTop,
                ),
              ),
            if (widget.pinnedBack != null)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: MgPinnedBack(
                  controller: _ctrl,
                  // The header's own disc sits in its top ~70 px: show the
                  // pinned one just before that part leaves the screen.
                  after: _headerH > 0 ? (_headerH - 72).clamp(24.0, double.infinity) : 64,
                  heroExtent: widget.header != null ? _headerH : _heroH + widget.sectionPadding.resolve(Directionality.of(context)).top,
                  close: widget.pinnedClose,
                  onTap: widget.pinnedBack!,
                  background: widget.background,
                  title: widget.pinnedTitle,
                ),
              ),
            if (widget.pinnedBar != null)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: _PinnedBarHost(
                  controller: _ctrl,
                  after: widget.pinnedBarAfter ?? (_headerH > 0 ? _headerH - 8 : 120),
                  child: widget.pinnedBar!,
                ),
              ),
          ]),
        ),
      ),
    );
    return ownBars ? MgHideOnScroll(child: page) : page;
  }
}

/// The header colour behind the scroll view, as tall as the header's
/// visible part (+ the iOS rubber-band gap above it).
class _OverscrollBackdrop extends StatelessWidget {
  final ScrollController controller;
  final double extent;
  final Color color;
  const _OverscrollBackdrop({required this.controller, required this.extent, required this.color});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (_, __) {
          final off = controller.hasClients && controller.positions.length == 1 ? controller.offset : 0.0;
          final h = (extent - off).clamp(0.0, double.infinity);
          return Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: h,
            child: ColoredBox(key: const ValueKey('mg-page-overscroll'), color: color),
          );
        },
      );
}

/// Shows [child] (sliding down from the top) once the scroll passes [after].
class _PinnedBarHost extends StatefulWidget {
  final ScrollController controller;
  final double after;
  final Widget child;
  const _PinnedBarHost({required this.controller, required this.after, required this.child});

  @override
  State<_PinnedBarHost> createState() => _PinnedBarHostState();
}

class _PinnedBarHostState extends State<_PinnedBarHost> {
  bool _on = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_check);
  }

  @override
  void didUpdateWidget(covariant _PinnedBarHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_check);
      widget.controller.addListener(_check);
    }
    _on = _visible();
  }

  bool _visible() {
    final c = widget.controller;
    return c.hasClients && c.positions.length == 1 && c.offset > widget.after;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_check);
    super.dispose();
  }

  void _check() {
    final on = _visible();
    if (on != _on && mounted) setState(() => _on = on);
  }

  /// The status-bar region slides with the bar: off-screen it stops counting.
  /// Folds away with the hide-on-scroll chrome too.
  @override
  Widget build(BuildContext context) => MgStickySlide(
        visible: _on && !MgBarsScope.hiddenOf(context),
        from: AxisDirection.up,
        child: MgStatusBar(dark: true, child: widget.child),
      );
}
