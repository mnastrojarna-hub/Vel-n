import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// MotoGo FX — sdílené animace pro „Duolingo-like" zážitek s mototématikou.
///
/// - [PressableScale]   — pružné zmáčknutí hlavních tlačítek + haptika
/// - [MotoSuccessHero]  — oslavná hlavička děkovacích stránek (motorka
///   přeletí obrazovku, za ní speed-lines, ohňostroj jisker a elastický check)
/// - [StaggeredReveal]  — postupné naplutí obsahu pod hlavičkou
/// - [MotoIntroOverlay] — intro při prvním spuštění appky (logo + přejezd)
/// - [MotoWelcomeOverlay] — celoobrazovková oslava po registraci
/// - [NavBounceIcon]    — elastický pop ikony při aktivaci tabu navigace
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
    this.pressedScale = 0.92,
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

// ═══════════════════════════════════════════════════════════════════
// NavBounceIcon — elastický pop ikony při aktivaci tabu spodní navigace
// ═══════════════════════════════════════════════════════════════════

class NavBounceIcon extends StatefulWidget {
  final bool active;
  final Widget child;

  const NavBounceIcon({super.key, required this.active, required this.child});

  @override
  State<NavBounceIcon> createState() => _NavBounceIconState();
}

class _NavBounceIconState extends State<NavBounceIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
      value: 1.0);

  @override
  void didUpdateWidget(NavBounceIcon old) {
    super.didUpdateWidget(old);
    if (!old.active && widget.active) {
      _ctrl.forward(from: 0);
    }
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
        // 0 → pop z 0.6, elastický overshoot, dosed na 1.0
        final s = 0.6 + 0.4 * Curves.elasticOut.transform(_ctrl.value);
        return Transform.scale(scale: s, child: child);
      },
      child: widget.child,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// MotoIntroOverlay — intro při prvním spuštění appky (~2,4 s)
// ═══════════════════════════════════════════════════════════════════

class MotoIntroOverlay extends StatefulWidget {
  final VoidCallback onDone;

  const MotoIntroOverlay({super.key, required this.onDone});

  @override
  State<MotoIntroOverlay> createState() => _MotoIntroOverlayState();
}

class _MotoIntroOverlayState extends State<MotoIntroOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400));
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
    _ctrl.addStatusListener((st) {
      if (st == AnimationStatus.completed) _finish();
    });
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double _seg(double from, double to, [Curve curve = Curves.easeOut]) {
    final v = ((_ctrl.value - from) / (to - from)).clamp(0.0, 1.0);
    return curve.transform(v);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final size = MediaQuery.of(context).size;
        final logoIn = _seg(0.05, 0.40, Curves.elasticOut);
        final logoOp = _seg(0.05, 0.22);
        final nameIn = _seg(0.28, 0.50);
        final ride = _seg(0.42, 0.78, Curves.easeInOutCubic);
        final fadeOut = _seg(0.86, 1.0);
        final rideX = -90 + ride * (size.width + 140);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _finish, // netrpěliví můžou přeskočit klepnutím
          child: Opacity(
            opacity: 1 - fadeOut,
            child: Material(
              color: const Color(0xFF0A1F15),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo s pulzem brandové zelené
                      Opacity(
                        opacity: logoOp,
                        child: Transform.scale(
                          scale: 0.5 + 0.5 * logoIn,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              color: MotoGoColors.green,
                              boxShadow: [
                                BoxShadow(
                                  color: MotoGoColors.green
                                      .withValues(alpha: 0.5 * logoOp),
                                  blurRadius: 26,
                                  spreadRadius: 3,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: Image.asset(
                                'assets/logo.png',
                                width: 104,
                                height: 104,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 104,
                                  height: 104,
                                  color: const Color(0xFF0A1F15),
                                  child: const Icon(Icons.motorcycle,
                                      size: 48, color: MotoGoColors.green),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Opacity(
                        opacity: nameIn,
                        child: Transform.translate(
                          offset: Offset(0, 14 * (1 - nameIn)),
                          child: const Column(children: [
                            Text('MOTO GO 24',
                                style: TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 4,
                                    color: MotoGoColors.green)),
                            SizedBox(height: 6),
                            Text('PŮJČOVNA MOTOREK',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 5,
                                    color: Color(0xFF8AAB99))),
                          ]),
                        ),
                      ),
                    ],
                  ),
                  // Motorka přejede spodní třetinou obrazovky
                  if (ride > 0 && ride < 1) ...[
                    Positioned(
                      left: rideX - 150,
                      top: size.height * 0.72,
                      child: Container(
                        width: 130,
                        height: 3,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          gradient: LinearGradient(colors: [
                            MotoGoColors.green.withValues(alpha: 0),
                            MotoGoColors.green.withValues(alpha: 0.8),
                          ]),
                        ),
                      ),
                    ),
                    Positioned(
                      left: rideX,
                      top: size.height * 0.72 - 30,
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()..rotateZ(-0.06),
                        child: const Text('🏍️', style: TextStyle(fontSize: 44)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// MotoWelcomeOverlay — oslava po úspěšné registraci (~2,8 s, tap přeskočí)
// ═══════════════════════════════════════════════════════════════════

class MotoWelcomeOverlay extends StatefulWidget {
  final String title;
  final String subtitle;

  const MotoWelcomeOverlay({
    super.key,
    required this.title,
    required this.subtitle,
  });

  /// Zobrazí overlay a vrátí se po jeho doběhnutí / tapnutí.
  static Future<void> show(BuildContext context,
      {required String title, required String subtitle}) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      barrierLabel: 'welcome',
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (_, __, ___) =>
          MotoWelcomeOverlay(title: title, subtitle: subtitle),
    );
  }

  @override
  State<MotoWelcomeOverlay> createState() => _MotoWelcomeOverlayState();
}

class _MotoWelcomeOverlayState extends State<MotoWelcomeOverlay> {
  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 2800), _close);
  }

  void _close() {
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _close,
      child: Material(
        color: const Color(0xF20A1F15), // téměř neprůhledný brand dark
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const MotoSuccessHero(size: 104),
              const SizedBox(height: 10),
              StaggeredReveal(
                index: 0,
                baseDelay: const Duration(milliseconds: 500),
                child: Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.white),
                ),
              ),
              const SizedBox(height: 10),
              StaggeredReveal(
                index: 1,
                baseDelay: const Duration(milliseconds: 500),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    widget.subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.7)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// GlowPulse — jemně pulzující záře kolem dítěte (rank pilota „září")
// ═══════════════════════════════════════════════════════════════════

/// Obalí [child] pulzujícím boxShadow v barvě [color]. Použito pro věrnostní
/// rank v profilu — pill ranku tak nenápadně „dýchá"/září, aby přitáhl
/// pozornost bez rušivé animace.
class GlowPulse extends StatefulWidget {
  final Widget child;
  final Color color;
  final BorderRadius borderRadius;
  final double minBlur;
  final double maxBlur;

  const GlowPulse({
    super.key,
    required this.child,
    required this.color,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.minBlur = 6,
    this.maxBlur = 22,
  });

  @override
  State<GlowPulse> createState() => _GlowPulseState();
}

class _GlowPulseState extends State<GlowPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

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
        final t = Curves.easeInOut.transform(_ctrl.value);
        final blur = widget.minBlur + (widget.maxBlur - widget.minBlur) * t;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.30 + 0.35 * t),
                blurRadius: blur,
                spreadRadius: 0.5 + 1.5 * t,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// ShimmerSweep — lesklý záblesk přejíždějící přes dítě (v barvě ranku)
// ═══════════════════════════════════════════════════════════════════

/// Periodicky přejede přes [child] šikmý lesklý pruh v barvě [color]. Použito
/// na věrnostní rank pilota („zlatý/diamantový" lesk dle barvy ranku) a na
/// hlavní tlačítka, aby UI působilo živěji. Pruh je jen overlay — nezasahuje
/// do obsahu ani do dotyků.
class ShimmerSweep extends StatefulWidget {
  final Widget child;
  final Color color;
  final BorderRadius borderRadius;
  final Duration period;

  const ShimmerSweep({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.borderRadius = BorderRadius.zero,
    this.period = const Duration(milliseconds: 2800),
  });

  @override
  State<ShimmerSweep> createState() => _ShimmerSweepState();
}

class _ShimmerSweepState extends State<ShimmerSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: widget.period)..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: widget.borderRadius,
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  // -1.2 → 1.2: pruh přijede zleva, projede a odjede vpravo.
                  final dx = -1.2 + 2.4 * _ctrl.value;
                  return Align(
                    alignment: Alignment(dx, 0),
                    child: Transform.rotate(
                      angle: 0.42,
                      child: FractionallySizedBox(
                        heightFactor: 2.2,
                        child: Container(
                          width: 46,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                widget.color.withValues(alpha: 0.0),
                                widget.color.withValues(alpha: 0.55),
                                widget.color.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
