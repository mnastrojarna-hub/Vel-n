import 'dart:async';

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
import 'mg_ai_coach.dart';
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
/// chrome changes or scrolling goes idle (never mid-drag), it checks its
/// slot against the `MgFabAvoid` zones (`mgFabPlacementFor`): free → rest;
/// else lift above them (≤ 56 px, 300 ms spring) when that slot is free;
/// else cta / sos → off; else peek (+26 px aside, 85 %). First run: the
/// coach bubble left of the disc (`MgAiCoach`), never over a cta / sos.
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
  double _lift = 0;
  final GlobalKey _coachKey = GlobalKey();
  bool _coachWanted = false;
  bool _coachBlocked = false;

  Timer? _coachTimer;

  @override
  void initState() {
    super.initState();
    MgAiCoach.seen().then((seen) {
      if (seen || !mounted) return;
      _coachTimer = Timer(MgAiCoach.delay, () {
        if (!mounted) return;
        setState(() => _coachWanted = true);
        // The bubble checks its place against the zones (never over a
        // CTA / SOS / key control such as the to-top arrow) once laid out.
        _schedule();
      });
    });
  }

  /// The [MgAiCoach.shownFor] timeout runs from the first frame the bubble
  /// is really on screen (not offstage, FAB not peek / off / hidden): it
  /// does not sit over the content for good, and it is never marked seen
  /// unseen (5.0.1 FS-03).
  bool _coachArmed = false;
  bool get _coachVisible =>
      _coachWanted && !widget.hidden && _state != MgFabState.off && _state != MgFabState.peek && !_coachBlocked;

  void _armCoach() {
    if (!mounted || _coachArmed || !_coachVisible) return;
    _coachArmed = true;
    _coachTimer?.cancel();
    _coachTimer = Timer(MgAiCoach.shownFor, () {
      if (mounted) _dismissCoach();
    });
  }

  void _dismissCoach() {
    if (!_coachWanted) return;
    setState(() => _coachWanted = false);
    MgAiCoach.markSeen();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = MgChromeScope.chromeOf(context);
    if (c != _chrome) {
      _chrome?.removeListener(_schedule);
      _chrome?.scrollTick.removeListener(_schedule);
      _chrome = c;
      _chrome?.addListener(_schedule);
      _chrome?.scrollTick.addListener(_schedule);
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
    _coachTimer?.cancel();
    _chrome?.removeListener(_schedule);
    _chrome?.scrollTick.removeListener(_schedule);
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
    final zones = _chrome?.zoneRects() ?? const <(Rect, MgAvoidKind)>[];
    final (next, lift) = mgFabPlacementFor(slot, zones);
    var blocked = false;
    final cb = _coachKey.currentContext?.findRenderObject();
    if (cb is RenderBox && cb.attached && cb.hasSize) {
      // Where the bubble sits with the new lift: left of the disc (gap 8),
      // bottoms aligned — from the slot, not from its own box, which moves
      // while it is offstage (blocked) and would flip the decision back.
      final r = Rect.fromLTWH(
          slot.left - 8 - cb.size.width, slot.bottom - cb.size.height - lift, cb.size.width, cb.size.height);
      // Never over a CTA, SOS or key text (keep); tap targets are fine.
      blocked = zones.any((z) => z.$2 != MgAvoidKind.tap && z.$1.overlaps(r));
    }
    if (next != _state || lift != _lift || blocked != _coachBlocked) {
      setState(() {
        _state = next;
        _lift = lift;
        _coachBlocked = blocked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final off = widget.hidden || _state == MgFabState.off;
    final peek = !off && _state == MgFabState.peek;
    final lift = !off && _state == MgFabState.lift ? _lift : 0.0;
    final d = MgMotion.of(context, MgMotion.fabState);
    final disc = SizedBox(
      key: _slotKey,
      width: MgChrome.fab,
      height: MgChrome.fab,
      child: IgnorePointer(
        ignoring: off,
        child: ExcludeSemantics(
          excluding: off,
          child: AnimatedSlide(
            offset: Offset(peek ? 26 / MgChrome.fab : 0, -lift / MgChrome.fab),
            duration: lift > 0 || _state == MgFabState.lift ? MgMotion.of(context, MgMotion.sheet) : d,
            curve: lift > 0 ? MgMotion.spring : MgMotion.out,
            child: AnimatedOpacity(
              opacity: off ? 0 : (peek ? 0.85 : 1),
              duration: d,
              child: AnimatedScale(
                scale: off ? 0.8 : 1,
                duration: d,
                child: MgAiDisc(
                  onTap: () {
                    _dismissCoach();
                    (widget.onTap ?? () => mgPushOrGo(context, kV2AiAgentRoute))();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final coach = _coachWanted && !widget.hidden && !off && !peek;
    if (coach && !_coachBlocked && !_coachArmed) WidgetsBinding.instance.addPostFrameCallback((_) => _armCoach());
    return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      if (coach)
        Offstage(
          offstage: _coachBlocked,
          child: Transform.translate(
            offset: Offset(0, -lift),
            child: KeyedSubtree(key: _coachKey, child: MgAiCoachBubble(onClose: _dismissCoach)),
          ),
        ),
      if (coach) const SizedBox(width: 8),
      disc,
    ]);
  }
}
