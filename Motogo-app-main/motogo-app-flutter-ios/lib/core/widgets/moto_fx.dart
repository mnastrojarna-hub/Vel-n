import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// MotoGo FX — sdílené animace pro „Duolingo-like" zážitek s mototématikou.
///
/// - [PressableScale]  — pružné zmáčknutí hlavních tlačítek + haptika
/// - [MotoSuccessHero] — oslavná hlavička děkovacích stránek (motorka
///   přeletí obrazovku, za ní speed-lines, ohňostroj jisker a elastický check)
/// - [StaggeredReveal] — postupné naplutí obsahu pod hlavičkou
///
/// Cíl: úspěšná akce (zaplaceno / rezervováno / upraveno) musí být zážitek,
/// který zákazníka povzbudí k další rezervaci — žádný statický check.

// ═══════════════════════════════════════════════════════════════════
// PressableScale — pružný „squash" na stisk (všechna hlavní tlačítka)
// ═══════════════════════════════════════════════════════════════════

class PressableScale extends StatefulWidget {
  final Widget child;

  /// Volitelné — když je null, animace jen reaguje na stisk a tap si
  /// obslouží vnitřní widget (ElevatedButton apod.). Používá `Listener`
  /// (pointer events), takže NEsoupeří s gesture arénou dítěte.
  final VoidCallback? onTap;
  final double pressedScale;
  final bool haptic;
  final bool enabled;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.94,
    this.haptic = true,
    this.enabled = true,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
    reverseDuration: const Duration(milliseconds: 240),
  );

  void _down() {
    if (!widget.enabled) return;
    _ctrl.forward();
    if (widget.haptic) HapticFeedback.lightImpact();
  }

  void _up() {
    if (_ctrl.isAnimating || _ctrl.value > 0) _ctrl.reverse();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget result = Listener(
      onPointerDown: (_) => _down(),
      onPointerUp: (_) => _up(),
      onPointerCancel: (_) => _up(),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          final t = Curves.easeOut.transform(_ctrl.value);
          final back = Curves.elasticOut.transform(1 - _ctrl.value);
          final scale = _ctrl.status == AnimationStatus.reverse
              ? widget.pressedScale + (1 - widget.pressedScale) * back
              : 1 - (1 - widget.pressedScale) * t;
          return Transform.scale(scale: scale.clamp(0.85, 1.04), child: child);
        },
        child: widget.child,
      ),
    );
    if (widget.onTap != null) {
      result = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? widget.onTap : null,
        child: result,
      );
    }
    return result;
  }
}

// ═══════════════════════════════════════════════════════════════════
// MotoSuccessHero — oslavná hlavička děkovací stránky
// ═══════════════════════════════════════════════════════════════════

class MotoSuccessHero extends StatefulWidget {
  /// Velikost kruhu s checkem.
  final double size;

  const MotoSuccessHero({super.key, this.size = 96});

  @override
  State<MotoSuccessHero> createState() => _MotoSuccessHeroState();
}

class _MotoSuccessHeroState extends State<MotoSuccessHero>
    with TickerProviderStateMixin {
  late final AnimationController _ride;   // motorka + speed lines (1.1 s)
  late final AnimationController _pop;    // check ring elastic pop
  late final AnimationController _burst;  // jiskry
  late final AnimationController _pulse;  // trvalý jemný glow

  @override
  void initState() {
    super.initState();
    _ride = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    _pop = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _burst = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);

    _ride.forward();
    // Check + jiskry odpálí v momentě, kdy motorka „projede" středem.
    Future.delayed(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _pop.forward();
      _burst.forward();
    });
  }

  @override
  void dispose() {
    _ride.dispose();
    _pop.dispose();
    _burst.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final heroH = widget.size + 64;
    return SizedBox(
      height: heroH,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: Listenable.merge([_ride, _pop, _burst, _pulse]),
        builder: (context, _) {
          final w = MediaQuery.of(context).size.width;
          final rideT = Curves.easeInOutCubic.transform(_ride.value);
          final popT = Curves.elasticOut.transform(_pop.value);
          final glow = 10 + 10 * _pulse.value;

          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Jiskry / částice za motorkou
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _SparkBurstPainter(
                      progress: Curves.easeOutCubic.transform(_burst.value),
                      color: MotoGoColors.green,
                    ),
                  ),
                ),
              ),

              // Speed-lines pruhy za motorkou
              if (_ride.value > 0 && _ride.value < 1) ...[
                _speedLine(w, rideT, dy: -26, len: 64, alpha: 0.55),
                _speedLine(w, rideT, dy: 0, len: 96, alpha: 0.85),
                _speedLine(w, rideT, dy: 26, len: 52, alpha: 0.45),
              ],

              // Check ring — elastický pop + pulzující glow
              Opacity(
                opacity: _pop.value.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 0.4 + 0.6 * popT,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: MotoGoColors.green, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: MotoGoColors.green
                              .withValues(alpha: 0.45 * _pop.value),
                          blurRadius: glow,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        '✓',
                        style: TextStyle(
                          fontSize: widget.size * 0.42,
                          fontWeight: FontWeight.w900,
                          color: MotoGoColors.green,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Motorka přejíždí zleva doprava přes střed
              if (_ride.value < 1)
                Positioned(
                  left: -90 + rideT * (w + 120),
                  child: Transform(
                    alignment: Alignment.center,
                    // Mírný náklon dopředu = dojem zrychlení
                    transform: Matrix4.identity()..rotateZ(-0.06),
                    child: const Text('🏍️', style: TextStyle(fontSize: 52)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _speedLine(double w, double t,
      {required double dy, required double len, required double alpha}) {
    final x = -90 + t * (w + 120) - len - 14;
    return Positioned(
      left: x,
      top: (widget.size + 64) / 2 + dy,
      child: Container(
        width: len,
        height: 3,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          gradient: LinearGradient(colors: [
            MotoGoColors.green.withValues(alpha: 0),
            MotoGoColors.green.withValues(alpha: alpha),
          ]),
        ),
      ),
    );
  }
}

/// Jiskry vystřelující ze středu — deterministické (bez Random ve frame),
/// stejný princip jako _BurstPainter v loyalty level-up animaci.
class _SparkBurstPainter extends CustomPainter {
  final double progress;
  final Color color;

  _SparkBurstPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final center = Offset(size.width / 2, size.height / 2);
    const count = 26;
    for (var i = 0; i < count; i++) {
      final fi = i.toDouble();
      final angle = (fi / count) * 2 * math.pi + math.sin(fi * 12.9898) * 0.4;
      final speed = 0.5 + ((math.sin(fi * 78.233) + 1) / 2) * 0.5;
      final travel = progress * speed * size.width * 0.42;
      final fade = (1 - progress).clamp(0.0, 1.0);
      final pos = center +
          Offset(math.cos(angle) * travel, math.sin(angle) * travel * 0.85);
      final radius =
          (2.8 * (1 - progress * 0.5)) * (0.6 + ((math.sin(fi * 39.425) + 1) / 2) * 0.7);
      final paint = Paint()
        ..color = (i % 4 == 0 ? Colors.white : color)
            .withValues(alpha: 0.9 * fade);
      canvas.drawCircle(pos, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_SparkBurstPainter old) =>
      old.progress != progress || old.color != color;
}

// ═══════════════════════════════════════════════════════════════════
// StaggeredReveal — postupné naplutí obsahu (fade + slide-up)
// ═══════════════════════════════════════════════════════════════════

class StaggeredReveal extends StatefulWidget {
  final Widget child;

  /// Pořadí prvku — každý další startuje o ~90 ms později.
  final int index;

  /// Základní zpoždění před prvním prvkem (po hero animaci).
  final Duration baseDelay;

  const StaggeredReveal({
    super.key,
    required this.child,
    this.index = 0,
    this.baseDelay = const Duration(milliseconds: 550),
  });

  @override
  State<StaggeredReveal> createState() => _StaggeredRevealState();
}

class _StaggeredRevealState extends State<StaggeredReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void initState() {
    super.initState();
    Future.delayed(
      widget.baseDelay + Duration(milliseconds: 90 * widget.index),
      () {
        if (mounted) _ctrl.forward();
      },
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_ctrl.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 22 * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
