import 'package:flutter/material.dart';

import '../../i18n/i18n_provider.dart';
import '../icons/mg_icon.dart';
import '../motion/mg_anim_loops.dart';
import '../motion/mg_motion.dart';
import '../motion/mg_sticky_slide.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_type.dart';
import '../widgets/mg_sheet.dart';
import 'mg_status_bar.dart';

/// The Velín banner in the v2 look (DESIGN_V22 §2.4 #2): ONE neon line —
/// a slow marquee when the text is longer than the line, a static line with
/// an ellipsis under reduced motion (it never moves then). Tap = the full
/// text in a light sheet, so nothing is ever lost. [band] = its own night
/// band under the status bar (shell tabs without their own banner line) —
/// it declares light status-bar icons (`MgStatusBar`); otherwise an inline
/// row (last line of a dark header). [folded] (band only, hide-on-scroll
/// `MgBarsScope`): the line folds up under the status-bar strip, which stays
/// night (light icons keep their surface); the body below grows.
///
/// [bg] / [fg] = the colours chosen in Velín (`BannerData.bg/color`, as the
/// old `ShellHeaderBanner`, G-350): the band is painted in [bg], an inline
/// row gets a rounded [bg] strip; the text and icon use [fg]. null = neon
/// on night.
class MgTopBanner extends StatelessWidget {
  final String text;
  final bool band;
  final bool folded;
  final Color? bg;
  final Color? fg;
  const MgTopBanner({super.key, required this.text, this.band = false, this.folded = false, this.bg, this.fg});

  static const double height = 28;

  void _open(BuildContext context) {
    final tr = t(context);
    showMgSheet<void>(
      context,
      title: tr.tr('v2BannerTitle'),
      builder: (_) => Text(text, style: MgType.body.copyWith(color: MgColors.ink)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final line = Semantics(
      button: true,
      label: text,
      hint: tr.tr('v2BannerOpenA11y'),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _open(context),
        child: SizedBox(
          height: height,
          child: Row(children: [
            MgIcon(MgIcons.info, size: 16, color: fg ?? MgColors.neon),
            const SizedBox(width: 8),
            Expanded(child: RepaintBoundary(child: _Marquee(text: text.trim(), color: fg ?? MgColors.neon))),
          ]),
        ),
      ),
    );
    if (!band) {
      if (bg == null) return line;
      return Container(
        key: const ValueKey('mg-top-banner-strip'),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: line,
      );
    }
    final top = MediaQuery.paddingOf(context).top;
    final fill = bg ?? MgColors.night;
    return MgStatusBar(
      dark: fill.computeLuminance() < 0.5,
      child: Container(
        color: fill,
        padding: EdgeInsets.fromLTRB(16, top, 16, 0),
        child: MgStickySlide(visible: !folded, from: AxisDirection.up, collapse: true, child: line),
      ),
    );
  }
}

/// Slow marquee driven by the shared loop clock: paused by `TickerMode`
/// and while scrolled off-screen (design M6), static under reduced motion.
class _Marquee extends StatelessWidget {
  final String text;
  final Color color;
  const _Marquee({required this.text, required this.color});

  static const double _gap = 48;
  static const double _speed = 40; // px / s — calm, readable

  @override
  Widget build(BuildContext context) {
    final style = MgType.meta.copyWith(fontWeight: FontWeight.w700, color: color, height: 1.2);
    final reduced = MgMotion.reduced(context);
    return LayoutBuilder(builder: (context, c) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final w = tp.width;
      tp.dispose();
      final moves = !reduced && w > c.maxWidth;
      final single = Text(text, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: style);
      if (!moves) return Align(alignment: AlignmentDirectional.centerStart, child: single);
      final row = Row(mainAxisSize: MainAxisSize.min, children: [
        Text(text, maxLines: 1, softWrap: false, style: style),
        const SizedBox(width: _gap),
        Text(text, maxLines: 1, softWrap: false, style: style),
      ]);
      final loop = w + _gap;
      return ClipRect(
        child: OverflowBox(
          maxWidth: double.infinity,
          alignment: AlignmentDirectional.centerStart,
          child: MgLoopClock(
            active: true,
            builder: (_, t) => t == null
                ? row
                : ValueListenableBuilder<double>(
                    valueListenable: t,
                    child: row,
                    builder: (_, sec, child) =>
                        Transform.translate(offset: Offset(-((sec * _speed) % loop), 0), child: child),
                  ),
          ),
        ),
      );
    });
  }
}
