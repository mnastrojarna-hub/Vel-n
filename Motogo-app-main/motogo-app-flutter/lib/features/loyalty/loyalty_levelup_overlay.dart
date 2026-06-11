import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/supabase_client.dart';
import '../../core/i18n/i18n_provider.dart';
import '../reservations/reservation_provider.dart';
import 'loyalty_provider.dart';

/// Globální hlídač postupu na vyšší věrnostní rank.
///
/// Sedí neviditelně v AppShell Stacku. Jakmile `get_loyalty_status` vrátí
/// vyšší level, než jaký si appka pamatuje (SharedPreferences per-user),
/// přehraje celoobrazovkovou oslavnou animaci: barevná vlna nového ranku
/// proletí obrazovkou, MG logo uprostřed změní barvu ringu ze staré na
/// novou a vystřelí částice. Level-up nastává po DOKONČENÍ rezervace
/// (jen rezervace vytvořené v aplikaci).
class LoyaltyLevelUpWatcher extends ConsumerStatefulWidget {
  const LoyaltyLevelUpWatcher({super.key});

  @override
  ConsumerState<LoyaltyLevelUpWatcher> createState() =>
      _LoyaltyLevelUpWatcherState();
}

class _LoyaltyLevelUpWatcherState extends ConsumerState<LoyaltyLevelUpWatcher> {
  bool _showing = false;

  String get _lvlKey =>
      'mg_loyalty_last_level_${MotoGoSupabase.currentUser?.id ?? 'anon'}';
  String get _colorKey =>
      'mg_loyalty_last_color_${MotoGoSupabase.currentUser?.id ?? 'anon'}';

  Future<void> _maybeCelebrate(LoyaltyStatus status) async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_lvlKey);
    final lastColorHex = prefs.getString(_colorKey);

    // První zjištění ranku (čerstvá instalace / nový login) — jen uložit,
    // ať se neslaví historický stav.
    if (last == null) {
      await prefs.setInt(_lvlKey, status.level);
      await prefs.setString(_colorKey, status.colorHex);
      return;
    }
    if (status.level <= last) {
      if (status.level != last) {
        await prefs.setInt(_lvlKey, status.level);
        await prefs.setString(_colorKey, status.colorHex);
      }
      return;
    }

    await prefs.setInt(_lvlKey, status.level);
    await prefs.setString(_colorKey, status.colorHex);

    if (!mounted || _showing) return;
    _showing = true;
    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      barrierLabel: 'levelup',
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => LevelUpCelebration(
        status: status,
        fromColor: colorFromHex(lastColorHex ?? '#9CA3AF'),
      ),
    );
    _showing = false;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(loyaltyStatusProvider, (prev, next) {
      final s = next.valueOrNull;
      if (s != null) _maybeCelebrate(s);
    });
    // Když se za běhu appky změní seznam rezervací (např. realtime přepnutí
    // na „dokončeno"), přepočti rank — animace tak proběhne hned, ne až po
    // restartu aplikace.
    ref.listen(reservationsProvider, (prev, next) {
      if (next.hasValue && prev?.valueOrNull != next.valueOrNull) {
        ref.invalidate(loyaltyStatusProvider);
      }
    });
    return const SizedBox.shrink();
  }
}

/// Celoobrazovková level-up animace (~3,2 s + tap/auto zavření).
class LevelUpCelebration extends StatefulWidget {
  final LoyaltyStatus status;
  final Color fromColor;

  const LevelUpCelebration({
    super.key,
    required this.status,
    required this.fromColor,
  });

  @override
  State<LevelUpCelebration> createState() => _LevelUpCelebrationState();
}

class _LevelUpCelebrationState extends State<LevelUpCelebration>
    with TickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..forward();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    // Auto-zavření po 7 s, kdyby zákazník neklikl.
    Future.delayed(const Duration(seconds: 7), _close);
  }

  void _close() {
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _pulse.dispose();
    super.dispose();
  }

  double _seg(double from, double to, [Curve curve = Curves.easeOut]) {
    final v = ((_ctrl.value - from) / (to - from)).clamp(0.0, 1.0);
    return curve.transform(v);
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final toColor = status.color;
    final glowColor =
        status.isLegend ? const Color(0xFFFF8C00) : toColor;
    String tr(String key) => t(context).tr(key);

    return AnimatedBuilder(
      animation: Listenable.merge([_ctrl, _pulse]),
      builder: (context, _) {
        final size = MediaQuery.of(context).size;
        final scrim = _seg(0.0, 0.15);
        final sweep = _seg(0.0, 0.30, Curves.easeInOutCubic);
        final logoIn = _seg(0.15, 0.50, Curves.elasticOut);
        final ringMix = _seg(0.22, 0.55);
        final burst = _seg(0.35, 1.0, Curves.easeOutCubic);
        final textIn = _seg(0.50, 0.72);
        final btnIn = _seg(0.82, 1.0);

        final ringColor = Color.lerp(widget.fromColor, toColor, ringMix)!;
        final pulseGlow = 18 + 14 * _pulse.value * ringMix;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_ctrl.value > 0.55) _close();
          },
          child: Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                // Ztmavení obrazovky
                Positioned.fill(
                  child: Container(
                    color: const Color(0xFF0A1A10)
                        .withValues(alpha: 0.92 * scrim),
                  ),
                ),

                // Barevná vlna nového ranku letící „skrze obrazovku"
                _sweepStripe(size, sweep, toColor, height: 130, angle: -0.32),
                _sweepStripe(size, (sweep - 0.12).clamp(0.0, 1.0),
                    Colors.white.withValues(alpha: 0.85),
                    height: 26, angle: -0.32, offsetY: 90),

                // Částicový ohňostroj z místa loga
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _BurstPainter(
                        progress: burst,
                        color: toColor,
                        secondary: status.isLegend
                            ? legendGradientColors.last
                            : Colors.white,
                        center: Offset(size.width / 2, size.height * 0.38),
                      ),
                    ),
                  ),
                ),

                // Logo + texty
                Positioned.fill(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(height: size.height * 0.06),
                      Transform.scale(
                        scale: 0.6 + 0.4 * logoIn,
                        child: Opacity(
                          opacity: _seg(0.15, 0.30),
                          child: Container(
                            padding: const EdgeInsets.all(7), // široký ring
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(30),
                              color: status.isLegend && ringMix > 0.95
                                  ? null
                                  : ringColor,
                              gradient: status.isLegend && ringMix > 0.95
                                  ? const LinearGradient(
                                      colors: legendGradientColors,
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                              boxShadow: [
                                BoxShadow(
                                  color: glowColor.withValues(
                                      alpha: 0.65 * ringMix),
                                  blurRadius: pulseGlow,
                                  spreadRadius: 2 * ringMix,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(23),
                              child: Image.asset(
                                'assets/logo.png',
                                width: 112,
                                height: 112,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 112,
                                  height: 112,
                                  color: const Color(0xFF000000),
                                  child: const Icon(Icons.motorcycle,
                                      size: 52, color: Color(0xFF74FB71)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 26),

                      // NOVÝ RANK!
                      Opacity(
                        opacity: textIn,
                        child: Transform.translate(
                          offset: Offset(0, 18 * (1 - textIn)),
                          child: Column(
                            children: [
                              Text(
                                tr('loyaltyLevelUpTitle'),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 4,
                                  color: Colors.white.withValues(alpha: 0.7),
                                ),
                              ),
                              const SizedBox(height: 8),
                              _rankTitle(status),
                              const SizedBox(height: 10),
                              Text(
                                tr('loyaltyLevelUpSub').replaceAll(
                                    '{pct}', '${status.percent}'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${tr('loyaltyLevelOf').replaceAll('{lvl}', '${status.level}').replaceAll('{max}', '${status.maxLevel}')}'
                                ' · ★ ${tr('loyaltyAppOnly')}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withValues(alpha: 0.55),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),

                      // Zavřít
                      Opacity(
                        opacity: btnIn,
                        child: GestureDetector(
                          onTap: _close,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 28, vertical: 12),
                            decoration: BoxDecoration(
                              color: status.isLegend ? null : toColor,
                              gradient: status.isLegend
                                  ? const LinearGradient(
                                      colors: legendGradientColors)
                                  : null,
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      glowColor.withValues(alpha: 0.5),
                                  blurRadius: 16,
                                ),
                              ],
                            ),
                            child: Text(
                              tr('confirm'),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: _onColor(toColor),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Diagonální pruh, který přeletí obrazovku zleva doprava.
  Widget _sweepStripe(Size size, double progress, Color color,
      {required double height, required double angle, double offsetY = 0}) {
    if (progress <= 0 || progress >= 1) return const SizedBox.shrink();
    final dx = -size.width * 1.4 + progress * size.width * 2.8;
    return Positioned(
      top: size.height * 0.30 + offsetY,
      left: dx,
      child: IgnorePointer(
        child: Transform.rotate(
          angle: angle,
          child: Container(
            width: size.width * 1.6,
            height: height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: 0),
                  color.withValues(alpha: 0.85),
                  color.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rankTitle(LoyaltyStatus status) {
    final text = Text(
      status.rankName.toUpperCase(),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w900,
        letterSpacing: 1,
        color: status.isLegend ? Colors.white : status.color,
      ),
    );
    if (!status.isLegend) return text;
    return ShaderMask(
      shaderCallback: (b) =>
          const LinearGradient(colors: legendGradientColors).createShader(b),
      child: text,
    );
  }

  /// Černý vs. bílý text podle světlosti barvy tlačítka.
  Color _onColor(Color c) =>
      c.computeLuminance() > 0.5 ? const Color(0xFF0F1A14) : Colors.white;
}

/// Částice vystřelující z loga — deterministické (bez Random ve frame).
class _BurstPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color secondary;
  final Offset center;

  _BurstPainter({
    required this.progress,
    required this.color,
    required this.secondary,
    required this.center,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    const count = 42;
    for (var i = 0; i < count; i++) {
      // Pseudo-náhodnost odvozená z indexu — stabilní mezi framy.
      final fi = i.toDouble();
      final angle = (fi / count) * 2 * math.pi + math.sin(fi * 12.9898) * 0.35;
      final speed = 0.55 + ((math.sin(fi * 78.233) + 1) / 2) * 0.45;
      final travel = progress * speed * size.shortestSide * 0.75;
      final fade = (1 - progress).clamp(0.0, 1.0);
      if (fade <= 0) continue;
      final pos = center +
          Offset(math.cos(angle) * travel, math.sin(angle) * travel * 0.9);
      final radius = (3.2 * (1 - progress * 0.6)) *
          (0.6 + ((math.sin(fi * 39.425) + 1) / 2) * 0.8);
      final paint = Paint()
        ..color = (i % 3 == 0 ? secondary : color)
            .withValues(alpha: 0.9 * fade);
      canvas.drawCircle(pos, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) =>
      old.progress != progress || old.color != color;
}
