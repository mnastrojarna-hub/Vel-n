import 'package:flutter/material.dart';

import '../icons/mg_icon.dart';
import '../motion/mg_anim.dart';
import '../motion/mg_anim_loops.dart';
import '../motion/mg_motion.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_type.dart';

enum MgStepState { done, current, future }

/// One node of [MgTimeline].
class MgTimelineStep {
  final String title;
  final String? sub;
  final MgStepState state;

  /// Current node is live (ping) — e.g. ride in progress.
  final bool live;
  const MgTimelineStep({required this.title, this.sub, this.state = MgStepState.future, this.live = false});
}

/// Vertical timeline ("Tvoje cesta"): done = neon disc + ink ✓, current =
/// ink disc + neon ring (+ ping when live), future = white disc + line.
/// Connectors draw once (700 ms, staggered); reduced motion → static.
class MgTimeline extends StatelessWidget {
  final List<MgTimelineStep> steps;
  final bool dark;
  const MgTimeline({super.key, required this.steps, this.dark = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++) _node(context, steps[i], i, i == steps.length - 1),
      ],
    );
  }

  Widget _disc(MgTimelineStep s) {
    switch (s.state) {
      case MgStepState.done:
        return Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(color: MgColors.neon, shape: BoxShape.circle),
          child: const Center(child: MgIcon(MgIcons.check, size: 14, color: MgColors.onNeon, stroke: 2.6)),
        );
      case MgStepState.current:
        final disc = Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: MgColors.ink,
            shape: BoxShape.circle,
            border: Border.all(color: MgColors.neon, width: 3),
          ),
        );
        return s.live ? MgPing(color: MgColors.neonA(0.7), size: 24, child: disc) : disc;
      case MgStepState.future:
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: dark ? MgColors.panel : MgColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: dark ? MgColors.white(0.25) : MgColors.line, width: 2),
          ),
        );
    }
  }

  Widget _node(BuildContext context, MgTimelineStep s, int i, bool last) {
    final lineColor = s.state == MgStepState.done
        ? MgColors.neonLo
        : (dark ? MgColors.white(0.18) : MgColors.line);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 24,
          child: Column(children: [
            _disc(s),
            if (!last)
              Expanded(
                child: MgProgressOnce(
                  duration: MgMotion.connector,
                  delay: Duration(milliseconds: 200 + 90 * i),
                  builder: (_, t) => SizedBox(
                    width: 2,
                    child: CustomPaint(painter: _ConnectorPainter(lineColor, t)),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : 16, top: 2),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(s.title,
                  style: MgType.title.copyWith(
                    color: dark
                        ? (s.state == MgStepState.future ? MgColors.onDarkSecondary : MgColors.onDark)
                        : (s.state == MgStepState.future ? MgColors.lead : MgColors.ink),
                  )),
              if (s.sub != null)
                Text(s.sub!, style: MgType.small.copyWith(color: dark ? MgColors.onDarkMeta : MgColors.meta)),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Connector drawn from the top to [t] of its height (one-shot draw-in).
/// A painter (not a FractionallySizedBox) so IntrinsicHeight never divides
/// by a zero factor.
class _ConnectorPainter extends CustomPainter {
  final Color color;
  final double t;
  _ConnectorPainter(this.color, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height * t.clamp(0.0, 1.0)), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ConnectorPainter o) => o.t != t || o.color != color;
}
