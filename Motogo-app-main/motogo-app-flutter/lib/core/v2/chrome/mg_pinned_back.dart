import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../motion/mg_motion.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_type.dart';
import '../widgets/mg_back_v2.dart';

/// The pinned back of `MgPage` (DESIGN_V22 §6.1 "stays pinned when a header
/// collapses"): appears once the scroll passes [after] (the header's own
/// disc is leaving). While the hero still lies under it ([heroExtent] = the
/// hero's bottom at scroll 0; 0 = unknown) it is the bare PHOTO disc; once
/// the hero is gone it is a compact collapsed bar — status-bar inset + 60 px
/// of [background] .94 with blur and a 1 px `line` hairline, the LIGHT disc
/// and the optional [title] — so the content scrolls under the bar, never
/// under a bare disc. Not in the tree while hidden; fades (instant under
/// reduced motion). [onTap] = the screen's own back action (unchanged).
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

  /// `Scrollable.ensureVisible` alignment that lands [target] 12 px under
  /// the collapsed bar (not hidden behind it) on an `MgPage` with a pinned
  /// back.
  static double revealAlignment(BuildContext target) {
    final top = MediaQuery.paddingOf(target).top + barHeight + 12;
    final p = Scrollable.maybeOf(target)?.position;
    final h = p != null && p.hasViewportDimension ? p.viewportDimension : MediaQuery.sizeOf(target).height;
    return h <= 0 ? 0.1 : (top / h).clamp(0.0, 0.5);
  }

  @override
  Widget build(BuildContext context) {
    final d = MgMotion.of(context, MgMotion.color);
    final top = MediaQuery.paddingOf(context).top;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final px = controller.hasClients && controller.positions.length == 1 ? controller.position.pixels : 0.0;
        final on = px > after;
        final overHero = heroExtent > 0 && heroExtent - px > top + barHeight;
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
          child = _bar(top);
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
  }

  Widget _bar(double top) => ClipRect(
        key: const ValueKey('mg-pinned-bar'),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            height: top + barHeight,
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
      );
}

/// 17/800 on one line, or 15/800 on two when it does not fit (like
/// `MgAppBar`).
class _BarTitle extends StatelessWidget {
  final String text;
  const _BarTitle(this.text);

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final base = DefaultTextStyle.of(context).style.merge(MgType.section);
        final tp = TextPainter(
          text: TextSpan(text: text, style: base),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: c.maxWidth);
        final fits = !tp.didExceedMaxLines;
        tp.dispose();
        return Semantics(
          header: true,
          child: Text(
            text,
            maxLines: fits ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: (fits ? MgType.section : MgType.title).copyWith(color: MgColors.ink),
          ),
        );
      });
}
