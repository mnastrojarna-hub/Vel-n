import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../motion/mg_motion.dart';
import '../motion/mg_sticky_slide.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_type.dart';
import '../widgets/mg_back_v2.dart';
import 'mg_hide_on_scroll.dart';
import 'mg_status_bar.dart';

/// Title of the collapsed bar of an `MgPage` with a pinned back; MgPage puts
/// it around its body so [MgPinnedBack.reveal] (called from a section of the
/// page) knows how tall the bar is at the current text size.
class MgPinnedScope extends InheritedWidget {
  final String? title;
  const MgPinnedScope({super.key, required this.title, required super.child});

  @override
  bool updateShouldNotify(MgPinnedScope old) => old.title != title;
}

/// The pinned back of `MgPage` (DESIGN_V22 §6.1 "stays pinned when a header
/// collapses"): appears once the scroll passes [after] (the header's own
/// disc is leaving). While the hero still lies under it ([heroExtent] = the
/// hero's bottom at scroll 0; 0 = unknown) it is the bare PHOTO disc; once
/// the hero is gone it is a compact collapsed bar — status-bar inset + 60 px
/// (more when [title] needs two lines at a larger system text size — the bar
/// grows, the second line is never cut) of [background] .94 with blur and a
/// 1 px `line` hairline, the LIGHT disc and the optional [title] — so the
/// content scrolls under the bar, never under a bare disc. Not in the tree
/// while hidden; fades (instant under reduced motion). [onTap] = the
/// screen's own back action (unchanged). The bar declares its brightness
/// (`MgStatusBar`, from [background]) — once it covers the status bar the
/// icons switch; the bare disc declares nothing (the hero under it does).
/// Hide-on-scroll (`MgBarsScope`, owner 2026-11-08): while the content is
/// scrolled DOWN the disc / bar slides up out of the status-bar area (its
/// status-bar region leaves with it) and comes back on any scroll up.
class MgPinnedBack extends StatelessWidget {
  final ScrollController controller;
  final double after;
  final double heroExtent;
  final bool close;
  final VoidCallback onTap;
  final Color background;
  final String? title;

  const MgPinnedBack({
    super.key,
    required this.controller,
    required this.after,
    required this.onTap,
    this.heroExtent = 0,
    this.close = false,
    this.background = MgColors.canvas,
    this.title,
  });

  static const double barHeight = 60;

  /// Room beside the title: 12 + the 44 px disc + 10 gap + 16.
  static const double _titleInsets = 12 + 44 + 10 + 16;

  /// Room above / below the title: 8 + 8 padding + the 1 px hairline.
  static const double _titleVInsets = 8 + 8 + 1;

  /// Height of the collapsed bar below the status-bar inset for [title] in
  /// a bar [width] wide: [barHeight], or the insets + the real two-line
  /// height when the title does not fit one line at the current text size.
  static double barHeightFor(BuildContext context, String? title, double width) {
    if (title == null || title.isEmpty) return barHeight;
    final fit = _TitleFit.measure(context, title, width - _titleInsets);
    return math.max(barHeight, _titleVInsets + fit.height.ceilToDouble());
  }

  /// Scrolls [target] (a context inside an `MgPage` with a pinned back) so
  /// its top lands 12 px under the collapsed bar. A scroll OFFSET, not an
  /// `ensureVisible` alignment: an alignment lands a target higher the
  /// taller it is (a 500 px section ended 45 px under the bar, its title
  /// hidden). Clamped to the scroll range; a zero [duration] jumps (reduced
  /// motion).
  static Future<void> reveal(BuildContext target, {Duration duration = Duration.zero, Curve curve = Curves.ease}) async {
    final scrollable = Scrollable.maybeOf(target, axis: Axis.vertical);
    final ro = target.findRenderObject();
    if (scrollable == null || ro == null || !ro.attached) return;
    final viewport = RenderAbstractViewport.maybeOf(ro);
    final position = scrollable.position;
    if (viewport == null || !position.hasPixels || !position.hasContentDimensions) return;
    final RenderObject vp = viewport;
    final width = vp is RenderBox && vp.hasSize ? vp.size.width : MediaQuery.sizeOf(target).width;
    final title = target.getInheritedWidgetOfExactType<MgPinnedScope>()?.title;
    final top = MediaQuery.paddingOf(target).top + barHeightFor(target, title, width) + 12;
    final to = (viewport.getOffsetToReveal(ro, 0).offset - top).clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((to - position.pixels).abs() < 0.5) return;
    if (duration == Duration.zero) {
      position.jumpTo(to);
      return;
    }
    await position.animateTo(to, duration: duration, curve: curve);
  }

  @override
  Widget build(BuildContext context) {
    final d = MgMotion.of(context, MgMotion.color);
    final top = MediaQuery.paddingOf(context).top;
    final folded = MgBarsScope.hiddenOf(context);
    return MgStickySlide(visible: !folded, from: AxisDirection.up, child: _pinned(context, d, top));
  }

  Widget _pinned(BuildContext context, Duration d, double top) {
    return LayoutBuilder(builder: (context, box) {
      final barH = barHeightFor(context, title, box.maxWidth.isFinite ? box.maxWidth : MediaQuery.sizeOf(context).width);
      return AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final px = controller.hasClients && controller.positions.length == 1 ? controller.position.pixels : 0.0;
          final on = px > after;
          final overHero = heroExtent > 0 && heroExtent - px > top + barH;
          final Widget child;
          if (!on) {
            child = const SizedBox.shrink(key: ValueKey('mg-pinned-off'));
          } else if (overHero) {
            child = Padding(
              key: const ValueKey('mg-pinned-disc'),
              padding: EdgeInsets.only(left: 12, top: top + 8),
              child: Align(
                alignment: AlignmentDirectional.topStart,
                child: MgV2Back(key: const ValueKey('mg-pinned-back'), onTap: onTap, close: close, style: MgBackStyle.photo),
              ),
            );
          } else {
            child = _bar(top, barH);
          }
          return AnimatedSwitcher(
            duration: d,
            layoutBuilder: (current, previous) => Stack(
              alignment: AlignmentDirectional.topStart,
              children: [...previous, if (current != null) current],
            ),
            child: child,
          );
        },
      );
    });
  }

  Widget _bar(double top, double barH) => MgStatusBar.forColor(
        background,
        key: const ValueKey('mg-pinned-bar'),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              height: top + barH,
              padding: EdgeInsets.fromLTRB(12, top + 8, 16, 8),
              decoration: BoxDecoration(
                color: background.withValues(alpha: 0.94),
                border: const Border(bottom: BorderSide(color: MgColors.line)),
              ),
              child: Row(children: [
                MgV2Back(key: const ValueKey('mg-pinned-back'), onTap: onTap, close: close, style: MgBackStyle.light),
                if ((title ?? '').isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Expanded(child: _BarTitle(title!)),
                ],
              ]),
            ),
          ),
        ),
      );
}

/// Whether the bar title fits 17/800 on one line in a given width, and its
/// real height (two lines of 15/800 otherwise) at the current text size.
/// Measured from the theme's body style — what the bar's `Text` renders
/// with — so [MgPinnedBack.reveal] gets the same number from any context.
class _TitleFit {
  final bool oneLine;
  final double height;
  const _TitleFit(this.oneLine, this.height);

  static _TitleFit measure(BuildContext context, String text, double width) {
    final base = Theme.of(context).textTheme.bodyMedium ?? DefaultTextStyle.of(context).style;
    final dir = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final scaler = MediaQuery.textScalerOf(context);
    final w = math.max(0.0, width);
    _TitleFit? lay(TextStyle style, int lines, bool one) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: base.merge(style)),
        maxLines: lines,
        textDirection: dir,
        textScaler: scaler,
      )..layout(maxWidth: w);
      final r = one && tp.didExceedMaxLines ? null : _TitleFit(one, tp.height);
      tp.dispose();
      return r;
    }

    return lay(MgType.section, 1, true) ?? lay(MgType.title, 2, false)!;
  }
}

/// 17/800 on one line, or 15/800 on two when it does not fit (like
/// `MgAppBar`).
class _BarTitle extends StatelessWidget {
  final String text;
  const _BarTitle(this.text);

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final fit = _TitleFit.measure(context, text, c.maxWidth);
        return Semantics(
          header: true,
          child: Text(
            text,
            maxLines: fit.oneLine ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: (fit.oneLine ? MgType.section : MgType.title).copyWith(color: MgColors.ink),
          ),
        );
      });
}
