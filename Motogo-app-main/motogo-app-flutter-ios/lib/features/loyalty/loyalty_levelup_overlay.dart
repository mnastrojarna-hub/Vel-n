import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../../core/supabase_client.dart';
import '../../core/i18n/i18n_provider.dart';
import '../reservations/reservation_provider.dart';
import 'loyalty_provider.dart';

/// Globální hlídač postupu na vyšší věrnostní rank.
///
/// Sedí neviditelně NAD celou navigací (v `MaterialApp.builder`), takže je
/// přítomný na KAŽDÉ obrazovce. Jakmile `get_loyalty_status` vrátí vyšší
/// level, než si appka pamatuje (SharedPreferences per-user), stáhne
/// personalizovanou motorku (RPC `get_loyalty_celebration_motos` — z historie
/// výpůjček, nejlepší médium: video → foto) a přehraje celoobrazovkovou
/// prémiovou oslavu: motorka přijíždí jako hlavní hrdina, identita se mění
/// dle ranku (nižší = brandová zelená, vyšší = zlato-chrom), vždy odznak
/// „+N". Postup o 2+ ranky = „mimořádný postup" se silnějšími efekty.
///
/// Spolehlivost: nový level se do SharedPreferences zapíše až PO zobrazení
/// oslavy — když se watcher mezitím odmountuje, oslava se neztratí.
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

    // První zjištění ranku (čerstvá instalace / nový login) — jen uložit.
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

    if (!mounted || _showing) return;
    final gained = status.level - last;
    _showing = true;

    // Personalizovaná motorka z historie výpůjček (fail-open → prázdné).
    final motos = await fetchLoyaltyCelebrationMotos();
    if (!mounted) {
      _showing = false;
      return; // NEukládáme — oslava se dožene příště.
    }

    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      barrierLabel: 'levelup',
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) => LevelUpCelebration(
        status: status,
        fromColor: colorFromHex(lastColorHex ?? '#9CA3AF'),
        gained: gained,
        motos: motos,
      ),
    );
    _showing = false;

    // Teprve po zobrazení posuň zapamatovaný level.
    await prefs.setInt(_lvlKey, status.level);
    await prefs.setString(_colorKey, status.colorHex);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(loyaltyStatusProvider, (prev, next) {
      final s = next.valueOrNull;
      if (s == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeCelebrate(s);
      });
    });
    ref.listen(reservationsProvider, (prev, next) {
      if (next.hasValue && prev?.valueOrNull != next.valueOrNull) {
        ref.invalidate(loyaltyStatusProvider);
      }
    });
    return const SizedBox.shrink();
  }
}

/// Celoobrazovková prémiová level-up oslava s motorkou jako hlavním motivem.
class LevelUpCelebration extends StatefulWidget {
  final LoyaltyStatus status;
  final Color fromColor;
  final int gained;
  final List<CelebrationMoto> motos;

  const LevelUpCelebration({
    super.key,
    required this.status,
    required this.fromColor,
    this.gained = 1,
    this.motos = const [],
  });

  @override
  State<LevelUpCelebration> createState() => _LevelUpCelebrationState();
}

class _LevelUpCelebrationState extends State<LevelUpCelebration>
    with TickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final AnimationController _pulse;

  bool get _turbo => widget.gained >= 2;
  CelebrationMoto? get _moto =>
      widget.motos.isNotEmpty ? widget.motos.first : null;

  /// „Zlatost" identity roste s rankem (0 = brandová zelená, 1 = zlato-chrom).
  /// Mimořádný postup (turbo) ji posune výš — odměna se cítí výjimečně.
  double get _goldness {
    final base = ((widget.status.level - 8) / 12).clamp(0.0, 1.0).toDouble();
    return _turbo ? math.max(base, 0.45) : base;
  }

  bool get _gold => widget.status.isLegend || _goldness >= 0.6;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _turbo ? 4600 : 3800),
    )..forward();
    _pulse = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _turbo ? 700 : 900),
    )..repeat(reverse: true);
    Future.delayed(Duration(seconds: _turbo ? 9 : 8), _close);
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
    final accent = status.color; // barva ranku z DB
    final glow = _gold ? const Color(0xFFFF8C00) : accent;
    String tr(String key) => t(context).tr(key);

    return AnimatedBuilder(
      animation: Listenable.merge([_ctrl, _pulse]),
      builder: (context, _) {
        final size = MediaQuery.of(context).size;
        final v = _ctrl.value;

        // Choreografie. Climax je ZÁMĚRNĚ na konci: logo MotoGo24 drží STAROU
        // barvu ranku a teprve k závěru se přeblikne na NOVOU (ringMix) +
        // záblesk + ukáže se číslo „+N". (Zvuk změny ranku napojíme na flash.)
        final mediaIn = _seg(0.0, 0.30, Curves.easeOutCubic); // příjezd motorky
        final beam = _seg(0.05, 0.55, Curves.easeInOutCubic); // průjezd světla
        final rev = _seg(0.22, 0.40, Curves.elasticOut); // záškub
        final emblemIn = _seg(0.18, 0.42, Curves.elasticOut); // logo (stará barva)
        final ringMix = _seg(0.56, 0.84); // PŘEKLOPENÍ staré → nové barvy
        final flash = _seg(0.58, 0.66) * (1 - _seg(0.66, 0.84)); // záblesk climaxu
        final badgeIn = _seg(0.66, 0.86, Curves.elasticOut); // číslo „+N" u climaxu
        final burst = _seg(0.62, 1.0, Curves.easeOutCubic); // jiskry u climaxu
        final shock = _turbo ? _seg(0.62, 0.95, Curves.easeOutCubic) : 0.0;
        final textIn = _seg(0.72, 0.90);
        final btnIn = _seg(0.90, 1.0);

        final pulseGlow = (_turbo ? 24.0 : 18.0) +
            (_turbo ? 20.0 : 14.0) * _pulse.value * emblemIn;
        // Logo MotoGo24 je UPROSTŘED scény (září dle ranku) — odtud i jiskry.
        final emblemCenter = Offset(size.width / 2, size.height * 0.42);

        // Příjezd zepředu: motorka „dojede" z dálky (zvětší se) + lehký drift.
        final heroScale = 1.18 - 0.18 * mediaIn + (_turbo ? 0.02 : 0.012) *
            _pulse.value;
        final heroDx = (1 - mediaIn) * size.width * 0.22;
        final heroRot = (1 - rev) * (_turbo ? -0.04 : -0.025);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (v > 0.6) _close();
          },
          child: Material(
            color: Colors.transparent,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Tmavý cinematic podklad (i kdyby médium chybělo).
                Container(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0, -0.4),
                      radius: 1.1,
                      colors: [Color(0xFF16241B), Color(0xFF070E09)],
                    ),
                  ),
                ),

                // HERO médium — motorka přijíždí (video > foto).
                if (_moto != null)
                  Opacity(
                    opacity: mediaIn,
                    child: Transform.translate(
                      offset: Offset(heroDx, 0),
                      child: Transform.rotate(
                        angle: heroRot,
                        child: Transform.scale(
                          scale: heroScale,
                          child: _HeroMedia(moto: _moto!),
                        ),
                      ),
                    ),
                  ),

                // Cinematic scrim — nahoře i dole ztmavit kvůli čitelnosti.
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.55),
                        Colors.black.withValues(alpha: 0.10),
                        Colors.black.withValues(alpha: 0.30),
                        Colors.black.withValues(alpha: 0.88),
                      ],
                      stops: const [0.0, 0.30, 0.55, 1.0],
                    ),
                  ),
                ),

                // Reflektor přejede scénou (průjezd světla).
                _beamSweep(size, beam),

                // Ohňostroj + rázová vlna z místa emblému.
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _BurstPainter(
                        progress: burst,
                        shock: shock,
                        speed: _turbo ? beam : 0.0,
                        count: _turbo ? 90 : 46,
                        color: _gold ? const Color(0xFFFFD700) : accent,
                        secondary:
                            _gold ? const Color(0xFFFF8C00) : Colors.white,
                        center: emblemCenter,
                      ),
                    ),
                  ),
                ),

                // Měkké tmavé „spotlight" pozadí pod logem (čitelnost přes video).
                Align(
                  alignment: const Alignment(0, -0.12),
                  child: IgnorePointer(
                    child: Container(
                      width: 300,
                      height: 300,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.55 * emblemIn),
                            Colors.black.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Logo MotoGo24 UPROSTŘED — drží starou barvu, na konci se
                // přeblikne na novou (ringMix) + odznak „+N".
                Align(
                  alignment: const Alignment(0, -0.12),
                  child: Opacity(
                    opacity: _seg(0.18, 0.36),
                    child: Transform.scale(
                      scale: 0.6 + 0.4 * emblemIn,
                      child: _emblem(ringMix, badgeIn, pulseGlow, glow, accent, tr),
                    ),
                  ),
                ),

                // Záblesk v momentě překlopení ranku (climax) — krátké projasnění.
                if (flash > 0.01)
                  IgnorePointer(
                    child: Container(
                      color: (_gold
                              ? const Color(0xFFFFE9AA)
                              : Colors.white)
                          .withValues(alpha: 0.45 * flash),
                    ),
                  ),

                // Spodní prémiový text.
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.only(
                        left: 26,
                        right: 26,
                        bottom: 34 + MediaQuery.of(context).padding.bottom),
                    child: Opacity(
                      opacity: textIn,
                      child: Transform.translate(
                        offset: Offset(0, 22 * (1 - textIn)),
                        child: _bottomTexts(status, accent, glow, btnIn, tr),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _emblem(double ringMix, double badgeIn, double pulseGlow, Color glow,
      Color accent, String Function(String) tr) {
    final ringColor = Color.lerp(widget.fromColor, accent, ringMix)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                color: _gold && ringMix > 0.9 ? null : ringColor,
                gradient: _gold && ringMix > 0.9
                    ? const LinearGradient(
                        colors: legendGradientColors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: glow.withValues(alpha: 0.6 * ringMix),
                    blurRadius: pulseGlow,
                    spreadRadius: 2 * ringMix,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset(
                  'assets/logo.png',
                  width: 92,
                  height: 92,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 92,
                    height: 92,
                    color: const Color(0xFF000000),
                    child: const Icon(Icons.motorcycle,
                        size: 44, color: Color(0xFF74FB71)),
                  ),
                ),
              ),
            ),
            // Vždy odznak „+N" (i pro +1) — naskočí v climaxu (badgeIn).
            Positioned(
              top: -12,
              right: -16,
              child: Transform.scale(
                scale: badgeIn,
                child: _jumpBadge(widget.gained),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          tr(_turbo ? 'loyaltyMegaLevelUpTitle' : 'loyaltyLevelUpKicker'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: _turbo ? 13 : 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 5,
            color: (_gold ? const Color(0xFFFFE7A0) : Colors.white)
                .withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }

  Widget _bottomTexts(LoyaltyStatus status, Color accent, Color glow,
      double btnIn, String Function(String) tr) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _rankTitle(status, accent),
        const SizedBox(height: 12),
        // „Vaše sleva X % platí napořád"
        Text(
          tr('loyaltyDiscountForever')
              .replaceAll('{pct}', '${status.percent}'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          tr('loyaltyValuedNote'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.45,
            color: Colors.white.withValues(alpha: 0.72),
          ),
        ),
        if (_moto != null && _moto!.title.isNotEmpty) ...[
          const SizedBox(height: 13),
          Text(
            '${tr('loyaltyYourBike')} · ${_moto!.title}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: (_gold ? const Color(0xFFFFE7A0) : accent)
                  .withValues(alpha: 0.85),
            ),
          ),
        ],
        const SizedBox(height: 22),
        Opacity(
          opacity: btnIn,
          child: GestureDetector(
            onTap: _close,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 34, vertical: 13),
              decoration: BoxDecoration(
                color: _gold ? null : accent,
                gradient: _gold
                    ? const LinearGradient(colors: legendGradientColors)
                    : null,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                      color: glow.withValues(alpha: 0.5), blurRadius: 18),
                ],
              ),
              child: Text(
                tr('confirm'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: _gold ? const Color(0xFF241A06) : _onColor(accent),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _jumpBadge(int n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        gradient: _gold
            ? const LinearGradient(
                colors: legendGradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : LinearGradient(
                colors: [
                  widget.status.color,
                  Color.lerp(widget.status.color, Colors.black, 0.25)!,
                ],
              ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: (_gold ? const Color(0xFFFF8C00) : widget.status.color)
                .withValues(alpha: 0.6),
            blurRadius: 14,
          ),
        ],
      ),
      child: Text(
        '+$n',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w900,
          color: _gold ? const Color(0xFF241A06) : _onColor(widget.status.color),
        ),
      ),
    );
  }

  /// Reflektor / světelný pruh přejede obrazovku (průjezd světla).
  Widget _beamSweep(Size size, double progress) {
    if (progress <= 0 || progress >= 1) return const SizedBox.shrink();
    final dx = -size.width * 0.8 + progress * size.width * 2.2;
    return Positioned(
      top: 0,
      bottom: 0,
      left: dx,
      child: IgnorePointer(
        child: Transform.rotate(
          angle: 0.12,
          child: Container(
            width: size.width * 0.5,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFFE9AA).withValues(alpha: 0),
                  const Color(0xFFFFE9AA).withValues(alpha: 0.16),
                  const Color(0xFFFFE9AA).withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rankTitle(LoyaltyStatus status, Color accent) {
    final text = Text(
      status.rankName.toUpperCase(),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.2,
        height: 1.05,
        color: _gold ? Colors.white : accent,
      ),
    );
    if (!_gold) return text;
    return ShaderMask(
      shaderCallback: (b) => const LinearGradient(
        colors: [Color(0xFFFFF4D6), Color(0xFFE9B24B), Color(0xFFFFD27A)],
      ).createShader(b),
      child: text,
    );
  }

  Color _onColor(Color c) =>
      c.computeLuminance() > 0.5 ? const Color(0xFF0F1A14) : Colors.white;
}

/// Hero motiv = full-screen médium poslední rezervované motorky:
/// PRIMÁRNĚ video (cover, muted, smyčka), jinak hlavní foto (cover).
class _HeroMedia extends StatelessWidget {
  final CelebrationMoto moto;
  const _HeroMedia({required this.moto});

  @override
  Widget build(BuildContext context) {
    if (moto.hasVideo) {
      return _HeroVideo(url: moto.videoUrl!);
    }
    if (moto.hasImage) {
      return Image.network(
        moto.imageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        loadingBuilder: (ctx, child, p) =>
            p == null ? child : const SizedBox.shrink(),
      );
    }
    return const SizedBox.shrink();
  }
}

class _HeroVideo extends StatefulWidget {
  final String url;
  const _HeroVideo({required this.url});

  @override
  State<_HeroVideo> createState() => _HeroVideoState();
}

class _HeroVideoState extends State<_HeroVideo> {
  VideoPlayerController? _c;
  bool _ready = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _c = c;
    try {
      await c.initialize();
      if (_disposed) {
        await c.dispose();
        return;
      }
      await c.setVolume(0);
      await c.setLooping(false); // po level-upu se přehraje JEN JEDNOU
      await c.play();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      // Video nešlo — hero zůstane na podkladu (gradient).
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (!_ready || c == null) return const SizedBox.shrink();
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: c.value.size.width,
        height: c.value.size.height,
        child: VideoPlayer(c),
      ),
    );
  }
}

/// Ohňostroj + rázová vlna + (turbo) rychlostní čáry — deterministické.
class _BurstPainter extends CustomPainter {
  final double progress;
  final double shock;
  final double speed; // 0..1 fáze rychlostních čar (turbo)
  final int count;
  final Color color;
  final Color secondary;
  final Offset center;

  _BurstPainter({
    required this.progress,
    required this.shock,
    required this.speed,
    required this.count,
    required this.color,
    required this.secondary,
    required this.center,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Rázová vlna (turbo)
    if (shock > 0 && shock < 1) {
      final r = shock * size.shortestSide * 0.9;
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 * (1 - shock)
        ..color = const Color(0xFFFFD700).withValues(alpha: 0.5 * (1 - shock));
      canvas.drawCircle(center, r, ring);
    }

    // Rychlostní čáry (jen turbo) — mužné, vodorovné, jemné.
    if (speed > 0 && speed < 1) {
      for (var i = 0; i < 6; i++) {
        final prog = (speed * 1.4 - i * 0.05).clamp(0.0, 1.0);
        if (prog <= 0 || prog >= 1) continue;
        final yy = size.height * 0.42 + i * 11;
        final x = -size.width * 0.6 + prog * size.width * 1.8;
        final rect = Rect.fromLTWH(x, yy, 90, 2);
        final g = const LinearGradient(colors: [
          Color(0x00FFE9AA),
          Color(0x80FFE9AA),
          Color(0x00FFE9AA),
        ]).createShader(rect);
        canvas.drawRect(rect, Paint()..shader = g);
      }
    }

    if (progress <= 0) return;
    final fade = (1 - progress).clamp(0.0, 1.0);
    if (fade <= 0) return;
    for (var i = 0; i < count; i++) {
      final fi = i.toDouble();
      final angle = (fi / count) * 2 * math.pi + math.sin(fi * 12.9898) * 0.35;
      final spd = 0.55 + ((math.sin(fi * 78.233) + 1) / 2) * 0.45;
      final travel = progress * spd * size.shortestSide * 0.8;
      final pos = center +
          Offset(math.cos(angle) * travel, math.sin(angle) * travel * 0.9);
      final radius = (2.9 * (1 - progress * 0.6)) *
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
      old.speed != speed ||
      old.color != color;
}
