import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/i18n_provider.dart';
import '../icons/mg_icon.dart';
import '../motion/mg_motion.dart';
import '../rank/rank_frame.dart' show ringShader;
import '../rank/rank_provider.dart';
import '../rank/rank_tokens.dart';
import '../tokens/mg_colors.dart';
import 'mg_chrome_metrics.dart';
import 'mg_fab_avoid.dart';
import 'mg_nav_helpers.dart';

/// The AI assistant disc (`shared/ai-fab.html`): dark glass, 2 px rank ring
/// (tier material), soft rank glow, neon chat-spark glyph, NO text, NO idle
/// loop. 56 floating / 44 docked (no glow). Tap = `context.push('/ai-agent')`
/// exactly like today's Home FAB (or [onTap]).
class MgAiDisc extends ConsumerWidget {
  final double size;
  final VoidCallback? onTap;
  final bool glow;
  final RankTokens? rank;
  const MgAiDisc({super.key, this.size = 56, this.onTap, this.glow = true, this.rank});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RankTokens r = rank ?? ref.watch(rankTokensProvider);
    final label = t(context).tr('aiServiceAgent');
    final tap = onTap ?? () => mgPushOrGo(context, kV2AiAgentRoute);
    final mini = size < 50;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: tap,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        triggerMode: TooltipTriggerMode.longPress,
        child: _PressDisc(
          onTap: () {
            HapticFeedback.selectionClick();
            tap();
          },
          child: CustomPaint(
            painter: _AiRingPainter(r),
            child: Container(
              width: size,
              height: size,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  if (glow && !mini)
                    BoxShadow(
                      color: r.glowColor.withValues(alpha: r.row.glowAlpha),
                      blurRadius: 18,
                      spreadRadius: -2,
                    ),
                  BoxShadow(
                    color: MgColors.black(0.35),
                    blurRadius: mini ? 14 : 18,
                    offset: Offset(0, mini ? 6 : 8),
                  ),
                ],
              ),
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: Alignment(-0.4, -0.5),
                    radius: 1.0,
                    colors: [MgColors.glow, MgColors.panel, MgColors.night],
                    stops: [0, 0.55, 1],
                  ),
                ),
                child: Center(
                  child: MgIcon(MgIcons.ai, size: mini ? 21 : 26, color: MgColors.neon, stroke: 1.9),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PressDisc extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _PressDisc({required this.child, required this.onTap});

  @override
  State<_PressDisc> createState() => _PressDiscState();
}

class _PressDiscState extends State<_PressDisc> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down && !MgMotion.reduced(context) ? 0.92 : 1,
          duration: MgMotion.press,
          child: widget.child,
        ),
      );
}

class _AiRingPainter extends CustomPainter {
  final RankTokens r;
  _AiRingPainter(this.r);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final c = rect.center;
    final ring2 = r.ring2;
    if (ring2 != null) canvas.drawCircle(c, size.shortestSide / 2 + 1, Paint()..color = ring2);
    final p = Paint();
    final sh = ringShader(r, rect);
    if (sh != null) {
      p.shader = sh;
    } else {
      p.color = r.ring.first;
    }
    canvas.drawCircle(c, size.shortestSide / 2, p);
  }

  @override
  bool shouldRepaint(_AiRingPainter o) => o.r != r;
}

/// The floating AI button of the v2 shell (bottom-right 16). [hidden]
/// (route in the hidden set, keyboard open, payment on screen) fades it out
/// (scale .8, 150 ms) with no hit / semantics. Otherwise, whenever the
/// chrome changes or scrolling goes idle, it checks its slot against the
/// `MgFabAvoid` zones: cta / sos under it → off, only tap zones → peek
/// (+26 px aside, 85 %), else rest.
class MgAiFab extends StatefulWidget {
  final bool hidden;
  final VoidCallback? onTap;
  const MgAiFab({super.key, this.hidden = false, this.onTap});

  @override
  State<MgAiFab> createState() => _MgAiFabState();
}

class _MgAiFabState extends State<MgAiFab> {
  final GlobalKey _slotKey = GlobalKey();
  MgShellChrome? _chrome;
  MgFabState _state = MgFabState.rest;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = MgChromeScope.chromeOf(context);
    if (c != _chrome) {
      _chrome?.removeListener(_schedule);
      _chrome = c;
      _chrome?.addListener(_schedule);
    }
    _schedule();
  }

  @override
  void didUpdateWidget(covariant MgAiFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  @override
  void dispose() {
    _chrome?.removeListener(_schedule);
    super.dispose();
  }

  bool _pending = false;

  void _schedule() {
    if (_pending) return;
    _pending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pending = false;
      _evaluate();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _evaluate() {
    if (!mounted) return;
    final box = _slotKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final slot = box.localToGlobal(Offset.zero) & box.size;
    final next = mgFabStateFor(slot, _chrome?.zoneRects() ?? const []);
    if (next != _state) setState(() => _state = next);
  }

  @override
  Widget build(BuildContext context) {
    final off = widget.hidden || _state == MgFabState.off;
    final peek = !off && _state == MgFabState.peek;
    final d = MgMotion.of(context, MgMotion.fabState);
    return SizedBox(
      key: _slotKey,
      width: MgChrome.fab,
      height: MgChrome.fab,
      child: IgnorePointer(
        ignoring: off,
        child: ExcludeSemantics(
          excluding: off,
          child: AnimatedSlide(
            offset: Offset(peek ? 26 / MgChrome.fab : 0, 0),
            duration: d,
            curve: MgMotion.out,
            child: AnimatedOpacity(
              opacity: off ? 0 : (peek ? 0.85 : 1),
              duration: d,
              child: AnimatedScale(
                scale: off ? 0.8 : 1,
                duration: d,
                child: MgAiDisc(onTap: widget.onTap),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
