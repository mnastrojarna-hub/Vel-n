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
/// Sedí neviditelně NAD celou navigací (v `MaterialApp.builder`), takže je
/// přítomný na KAŽDÉ obrazovce — i na těch mimo spodní lištu (login, platba,
/// „success" potvrzení rezervace, dokumenty…). Jakmile `get_loyalty_status`
/// vrátí vyšší level, než jaký si appka pamatuje (SharedPreferences per-user),
/// přehraje celoobrazovkovou oslavnou animaci:
///   • postup o 1 rank → standardní oslava (barevná vlna + logo + ohňostroj),
///   • postup o 2+ ranky → „MEGA POSTUP" — turbo verze (více vln, rázová
///     vlna, hustší ohňostroj, zlatý nádech a odznak „+N").
/// Level-up nastává po DOKONČENÍ rezervace (app i web; 7+ dní = 4 body = skok
/// o 2 ranky, měsíční výhra = +4 body).
///
/// DŮLEŽITÉ pro spolehlivost: nový level se do SharedPreferences zapíše až
/// PO skutečném zobrazení animace. Když by se watcher mezitím odmountoval
/// (nestihlo se zobrazit), oslava se NEZTRATÍ — přehraje se při dalším
/// načtení statusu / spuštění appky.
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
      // Rank klesl/zůstal — udrž uložený stav v souladu, ale neslav.
      if (status.level != last) {
        await prefs.setInt(_lvlKey, status.level);
        await prefs.setString(_colorKey, status.colorHex);
      }
      return;
    }

    // Postup! Pozn.: NEukládáme nový level dřív, než animaci skutečně
    // zobrazíme — jinak by se při neúspěšném zobrazení oslava ztratila.
    if (!mounted || _showing) return;
    final gained = status.level - last;
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
        gained: gained,
      ),
    );
    _showing = false;

    // Teprve teď, když oslava proběhla, posuň zapamatovaný level.
    await prefs.setInt(_lvlKey, status.level);
    await prefs.setString(_colorKey, status.colorHex);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(loyaltyStatusProvider, (prev, next) {
      final s = next.valueOrNull;
      if (s == null) return;
      // Listener může vystřelit i uprostřed build/navigační fáze — dialog
      // (Navigator) se smí otevřít až po dokončení framu, jinak hrozí pád.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeCelebrate(s);
      });
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

/// Celoobrazovková level-up animace.
///
/// `gained` = o kolik ranků zákazník postoupil. `gained >= 2` přepne na
/// turbo („MEGA POSTUP") verzi — delší, hustší a se zlatým nádechem.
class LevelUpCelebration extends StatefulWidget {
  final LoyaltyStatus status;
  final Color fromColor;
  final int gained;

  const LevelUpCelebration({
    super.key,
    required this.status,
    required this.fromColor,
    this.gained = 1,
  });

  @override
  State<LevelUpCelebration> createState() => _LevelUpCelebrationState();
}

class _LevelUpCelebrationState extends State<LevelUpCelebration>
    with TickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final AnimationController _pulse;

  bool get _turbo => widget.gained >= 2;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      // Turbo trvá déle — víc vln a hustší ohňostroj potřebují prostor.
      duration: Duration(milliseconds: _turbo ? 4200 : 3200),
    )..forward();
    _pulse = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _turbo ? 700 : 900),
    )..repeat(reverse: true);
    // Auto-zavření, kdyby zákazník neklikl.
    Future.delayed(Duration(seconds: _turbo ? 8 : 7), _close);
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
    // Turbo i Legenda září zlatě; jinak barva nového ranku.
    final glowColor = (status.isLegend || _turbo)
        ? const Color(0xFFFF8C00)
        : toColor;
    String tr(String key) => t(context).tr(key);

    return AnimatedBuilder(
      animation: Listenable.merge([_ctrl, _pulse]),
      builder: (context, _) {
        final size = MediaQuery.of(context).size;
        final scrim = _seg(0.0, 0.15);
        final sweep = _seg(0.0, 0.30, Curves.easeInOutCubic);
        final logoIn = _seg(0.15, 0.50, Curves.elasticOut);
        final ringMix = _seg(0.22, 0.55);
        final burst = _seg(0.32, 1.0, Curves.easeOutCubic);
        final shock = _turbo ? _seg(0.30, 0.85, Curves.easeOutCubic) : 0.0;
        final textIn = _seg(0.50, 0.72);
        final badgeIn = _turbo ? _seg(0.46, 0.66, Curves.elasticOut) : 0.0;
        final btnIn = _seg(0.82, 1.0);

        final ringColor = Color.lerp(widget.fromColor, toColor, ringMix)!;
        final pulseGlow = (_turbo ? 26.0 : 18.0) +
            (_turbo ? 22.0 : 14.0) * _pulse.value * ringMix;
        final centerY = size.height * 0.38;
        final center = Offset(size.width / 2, centerY);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_ctrl.value > 0.55) _close();
          },
          child: Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                // Ztmavení obrazovky (turbo je o něco temnější pro kontrast).
                Positioned.fill(
                  child: Container(
                    color: const Color(0xFF0A1A10)
                        .withValues(alpha: (_turbo ? 0.95 : 0.92) * scrim),
                  ),
                ),

                // Barevné vlny nového ranku letící „skrze obrazovku".
                // Turbo: víc vln v různých fázích + zlatý akcent.
                _sweepStripe(size, sweep, toColor, height: 130, angle: -0.32),
                _sweepStripe(size, (sweep - 0.12).clamp(0.0, 1.0),
                    Colors.white.withValues(alpha: 0.85),
                    height: 26, angle: -0.32, offsetY: 90),
                if (_turbo) ...[
                  _sweepStripe(
                      size,
                      (sweep - 0.06).clamp(0.0, 1.0),
                      const Color(0xFFFFD700).withValues(alpha: 0.7),
                      height: 70, angle: 0.30, offsetY: -120),
                  _sweepStripe(
                      size,
                      (sweep - 0.20).clamp(0.0, 1.0),
                      toColor.withValues(alpha: 0.8),
                      height: 100, angle: 0.30, offsetY: 230),
                ],

                // Částicový ohňostroj (turbo = hustší) + rázová vlna z loga.
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _BurstPainter(
                        progress: burst,
                        shock: shock,
                        count: _turbo ? 90 : 42,
                        color: toColor,
                        secondary: (status.isLegend || _turbo)
                            ? legendGradientColors.last
                            : Colors.white,
                        center: center,
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
                      Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          Transform.scale(
                            scale: 0.6 + 0.4 * logoIn,
                            child: Opacity(
                              opacity: _seg(0.15, 0.30),
                              child: Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(30),
                                  color: (status.isLegend || _turbo) &&
                                          ringMix > 0.95
                                      ? null
                                      : ringColor,
                                  gradient: (status.isLegend || _turbo) &&
                                          ringMix > 0.95
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
                          // Odznak „+N" — jen v turbo režimu.
                          if (_turbo)
                            Positioned(
                              top: -14,
                              right: -18,
                              child: Transform.scale(
                                scale: badgeIn,
                                child: _jumpBadge(widget.gained),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 26),

                      // NOVÝ RANK! / MEGA POSTUP!
                      Opacity(
                        opacity: textIn,
                        child: Transform.translate(
                          offset: Offset(0, 18 * (1 - textIn)),
                          child: Column(
                            children: [
                              Text(
                                tr(_turbo
                                    ? 'loyaltyMegaLevelUpTitle'
                                    : 'loyaltyLevelUpTitle'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: _turbo ? 16 : 13,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: _turbo ? 3 : 4,
                                  color: _turbo
                                      ? const Color(0xFFFFD27A)
                                      : Colors.white.withValues(alpha: 0.7),
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
                              color: (status.isLegend || _turbo) ? null : toColor,
                              gradient: (status.isLegend || _turbo)
                                  ? const LinearGradient(
                                      colors: legendGradientColors)
                                  : null,
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: [
                                BoxShadow(
                                  color: glowColor.withValues(alpha: 0.5),
                                  blurRadius: 16,
                                ),
                              ],
                            ),
                            child: Text(
                              tr('confirm'),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: (status.isLegend || _turbo)
                                    ? const Color(0xFF0F1A14)
                                    : _onColor(toColor),
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

  /// Zlatý odznak „+N" pro turbo postup.
  Widget _jumpBadge(int n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: legendGradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF8C00).withValues(alpha: 0.6),
            blurRadius: 14,
          ),
        ],
      ),
      child: Text(
        '+$n',
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w900,
          color: Color(0xFF0F1A14),
        ),
      ),
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
    final gradient = status.isLegend || _turbo;
    final text = Text(
      status.rankName.toUpperCase(),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: _turbo ? 30 : 26,
        fontWeight: FontWeight.w900,
        letterSpacing: 1,
        color: gradient ? Colors.white : status.color,
      ),
    );
    if (!gradient) return text;
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

/// Částice vystřelující z loga + rázová vlna — deterministické (bez Random).
class _BurstPainter extends CustomPainter {
  final double progress;
  final double shock;
  final int count;
  final Color color;
  final Color secondary;
  final Offset center;

  _BurstPainter({
    required this.progress,
    required this.shock,
    required this.count,
    required this.color,
    required this.secondary,
    required this.center,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Rázová vlna (turbo) — rozpínající se prstenec.
    if (shock > 0 && shock < 1) {
      final r = shock * size.shortestSide * 0.85;
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 * (1 - shock)
        ..color = const Color(0xFFFFD700)
            .withValues(alpha: 0.55 * (1 - shock));
      canvas.drawCircle(center, r, ringPaint);
    }

    if (progress <= 0) return;
    for (var i = 0; i < count; i++) {
      // Pseudo-náhodnost odvozená z indexu — stabilní mezi framy.
      final fi = i.toDouble();
      final angle = (fi / count) * 2 * math.pi + math.sin(fi * 12.9898) * 0.35;
      final speed = 0.55 + ((math.sin(fi * 78.233) + 1) / 2) * 0.45;
      final travel = progress * speed * size.shortestSide * 0.78;
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
      old.progress != progress ||
      old.shock != shock ||
      old.color != color;
}
