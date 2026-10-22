import 'package:flutter/material.dart';

import '../../i18n/i18n_provider.dart';
import '../icons/mg_icon.dart';
import '../motion/mg_motion.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_type.dart';
import '../widgets/mg_sheet.dart';

/// The Velín banner in the v2 look (DESIGN_V22 §2.4 #2): ONE neon line —
/// a slow marquee when the text is longer than the line, a static line with
/// an ellipsis under reduced motion (it never moves then). Tap = the full
/// text in a light sheet, so nothing is ever lost. [band] = its own night
/// band under the status bar (shell tabs without their own banner line);
/// otherwise an inline row (last line of a dark header).
class MgTopBanner extends StatelessWidget {
  final String text;
  final bool band;
  const MgTopBanner({super.key, required this.text, this.band = false});

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
            const MgIcon(MgIcons.info, size: 16, color: MgColors.neon),
            const SizedBox(width: 8),
            Expanded(child: _Marquee(text: text.trim())),
          ]),
        ),
      ),
    );
    if (!band) return line;
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      color: MgColors.night,
      padding: EdgeInsets.fromLTRB(16, top, 16, 0),
      child: line,
    );
  }
}

class _Marquee extends StatefulWidget {
  final String text;
  const _Marquee({required this.text});

  @override
  State<_Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<_Marquee> with SingleTickerProviderStateMixin {
  static const double _gap = 48;
  static const double _speed = 40; // px / s — calm, readable
  late final AnimationController _ctrl = AnimationController(vsync: this);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _run(bool on, double distance) {
    if (!on) {
      if (_ctrl.isAnimating) _ctrl.stop();
      return;
    }
    final d = Duration(milliseconds: (distance / _speed * 1000).round());
    if (_ctrl.duration != d) {
      _ctrl.duration = d;
      _ctrl.repeat();
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = MgType.meta.copyWith(fontWeight: FontWeight.w700, color: MgColors.neon, height: 1.2);
    final reduced = MgMotion.reduced(context);
    return LayoutBuilder(builder: (context, c) {
      final tp = TextPainter(
        text: TextSpan(text: widget.text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final w = tp.width;
      tp.dispose();
      final moves = !reduced && w > c.maxWidth;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _run(moves, w + _gap);
      });
      final single = Text(widget.text, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: style);
      if (!moves) return Align(alignment: AlignmentDirectional.centerStart, child: single);
      final row = Row(mainAxisSize: MainAxisSize.min, children: [
        Text(widget.text, maxLines: 1, softWrap: false, style: style),
        const SizedBox(width: _gap),
        Text(widget.text, maxLines: 1, softWrap: false, style: style),
      ]);
      return ClipRect(
        child: OverflowBox(
          maxWidth: double.infinity,
          alignment: AlignmentDirectional.centerStart,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, child) => Transform.translate(offset: Offset(-_ctrl.value * (w + _gap), 0), child: child),
            child: row,
          ),
        ),
      );
    });
  }
}
