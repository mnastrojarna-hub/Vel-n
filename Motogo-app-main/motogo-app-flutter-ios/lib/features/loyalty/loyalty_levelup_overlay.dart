import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../../core/supabase_client.dart';
import '../../core/widgets/net_image.dart';
import '../../core/i18n/i18n_provider.dart';
import '../reservations/reservation_provider.dart';
import 'loyalty_provider.dart';

/// Globální hlídač postupu na vyšší věrnostní rank.
///
/// Sedí neviditelně NAD celou navigací (v `MaterialApp.builder`), takže je
/// přítomný na KAŽDÉ obrazovce. Jakmile `get_loyalty_status` vrátí vyšší
/// level, než si appka pamatuje (SharedPreferences per-user), stáhne
/// personalizovanou motorku (RPC `get_loyalty_celebration_motos` — poslední
/// dokončená rezervace + její videa/foto) a přehraje celoobrazovkovou oslavu:
/// montáž videí motorky s hudbou na pozadí (~67 s, 1×), po videích zůstane
/// hlavní animovaná fotka (posledních 5 s vždy fotka), reveal ranku HNED na
/// začátku (logo MotoGo24 ve středu se přeblikne ze staré barvy na novou +
/// odznak „+N"), vše skončí s koncem hudby. Dole tlačítko „Pokračovat".
///
/// Spolehlivost: nový level se do SharedPreferences zapíše až PO zobrazení
/// oslavy — když se watcher mezitím odmountuje, oslava se neztratí.
class LoyaltyLevelUpWatcher extends ConsumerStatefulWidget {
  const LoyaltyLevelUpWatcher({super.key});

  @override
  ConsumerState<LoyaltyLevelUpWatcher> createState() =>
      _LoyaltyLevelUpWatcherState();
}

class _LoyaltyLevelUpWatcherState extends ConsumerState<LoyaltyLevelUpWatcher>
    with WidgetsBindingObserver {
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Návrat appky do popředí → znovu načti rank. Bez toho by povýšení, které
  /// nastalo, když byl uživatel pryč (rezervace dokončena server-side), appka
  /// při „warm resume" vůbec nezaznamenala a oslava by se nikdy nepřehrála.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        MotoGoSupabase.currentUser != null) {
      ref.invalidate(loyaltyStatusProvider);
    }
  }

  String get _lvlKey =>
      'mg_loyalty_last_level_${MotoGoSupabase.currentUser?.id ?? 'anon'}';
  String get _colorKey =>
      'mg_loyalty_last_color_${MotoGoSupabase.currentUser?.id ?? 'anon'}';

  /// „Už oslaveno na level N" — SERVER je zdroj pravdy (`profiles`), takže
  /// povýšení uvidí uživatel VŽDY a právě JEDNOU: přežije reinstal, nové
  /// zařízení i smazaná data. Vrací null, když RPC ještě není nasazené →
  /// fallback na lokální SharedPreferences baseline (appka funguje jako dřív).
  Future<int?> _serverCelebrated() async {
    if (MotoGoSupabase.currentUser == null) return null;
    try {
      final res = await MotoGoSupabase.client.rpc('loyalty_get_celebrated');
      if (res is num) return res.toInt();
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _advanceServer(int level) async {
    if (MotoGoSupabase.currentUser == null) return;
    try {
      await MotoGoSupabase.client
          .rpc('loyalty_advance_celebrated', params: {'p_level': level});
    } catch (_) {/* fail-open */}
  }

  Future<void> _persistLocal(
      SharedPreferences prefs, LoyaltyStatus status) async {
    await prefs.setInt(_lvlKey, status.level);
    await prefs.setString(_colorKey, status.colorHex);
  }

  Future<void> _maybeCelebrate(LoyaltyStatus status) async {
    if (!mounted || _showing) return;
    final prefs = await SharedPreferences.getInstance();
    final lastColorHex = prefs.getString(_colorKey);

    // Baseline = server (autoritativní, přežije reinstal), jinak lokální mirror.
    final serverBaseline = await _serverCelebrated();
    final bool serverMode = serverBaseline != null;
    final int? baseline = serverBaseline ?? prefs.getInt(_lvlKey);

    // Neseednuto (server 0 nebo lokálně nic) → jen zaznamenej aktuální level,
    // NEoslavuj (na úplně prvním pozorování není co „povyšovat").
    if (baseline == null || (serverMode && baseline == 0)) {
      await _persistLocal(prefs, status);
      if (serverMode) await _advanceServer(status.level);
      return;
    }

    if (status.level <= baseline) {
      await _persistLocal(prefs, status);
      return;
    }

    if (!mounted || _showing) return;
    final gained = status.level - baseline;
    _showing = true;

    final motos = await fetchLoyaltyCelebrationMotos();
    if (!mounted) {
      _showing = false;
      return; // NEukládáme — oslava se dožene příště (baseline zůstává nižší).
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

    // Zapiš „oslaveno" AŽ po přehrání → přežije zabití appky uprostřed videa
    // (příště se dožene). Server GREATEST → i napříč zařízeními jen jednou.
    await _persistLocal(prefs, status);
    if (serverMode) await _advanceServer(status.level);
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

/// Celoobrazovková prémiová level-up oslava (montáž videí + hudba, ~67 s).
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
  // Délka = délka hudby (ořez 0:25–1:32 ≈ 67 s). Master clock celé scény.
  static const double _T = 67.0;
  static const double _photoAt = _T - 5.0; // posledních 5 s vždy fotka
  static const double _rs = 1.4; // reveal ranku HNED na začátku

  late final AnimationController _ctrl;
  late final AnimationController _pulse;

  bool get _turbo => widget.gained >= 2;
  CelebrationMoto? get _moto =>
      widget.motos.isNotEmpty ? widget.motos.first : null;

  /// Jen vrchol „Legenda MotoGo" (level 20) má zlato-chrom gradient;
  /// ostatní ranky používají svou skutečnou barvu (`color_hex`).
  bool get _gold => widget.status.isLegend;

  double get _t => _ctrl.value * _T;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 67000), // = _T (67 s)
    )
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _close();
      })
      ..forward();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
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

  /// Segment v sekundách na hlavní časové ose.
  double _seg(double from, double to, [Curve curve = Curves.easeOut]) {
    final v = ((_t - from) / (to - from)).clamp(0.0, 1.0);
    return curve.transform(v);
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final accent = status.color; // skutečná barva ranku z DB
    final glow = _gold ? const Color(0xFFFF8C00) : accent;
    String tr(String key) => t(context).tr(key);

    return AnimatedBuilder(
      animation: Listenable.merge([_ctrl, _pulse]),
      builder: (context, _) {
        final size = MediaQuery.of(context).size;

        final beam = _seg(0.2, 2.6, Curves.easeInOutCubic); // úvodní průjezd světla
        final emblemIn = _seg(0.4, 2.4, Curves.elasticOut);
        final ringMix = _seg(_rs, _rs + 3.0); // přeblik stará → nová barva
        final flash = _seg(_rs, _rs + 0.8) * (1 - _seg(_rs + 0.8, _rs + 2.4));
        final badgeIn = _seg(_rs + 0.9, _rs + 2.6, Curves.elasticOut);
        final burst = _seg(_rs, _rs + 3.4, Curves.easeOutCubic);
        final shock = _turbo ? _seg(_rs, _rs + 3.0, Curves.easeOutCubic) : 0.0;
        final textIn = _seg(_rs + 0.3, _rs + 2.4);
        final btnIn = _seg(_rs + 1.6, _rs + 3.2);

        final pulseGlow = (_turbo ? 36.0 : 30.0) +
            (_turbo ? 30.0 : 24.0) * _pulse.value * emblemIn;
        final emblemCenter = Offset(size.width / 2, size.height * 0.42);
        final forcePhoto = _t >= _photoAt;

        return Material(
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

              // Hudba na pozadí (přehraje se 1×) — neviditelná.
              const _BgMusic(),

              // HERO médium: montáž videí motorky → hlavní fotka (Ken Burns).
              if (_moto != null)
                _MediaMontage(
                  videos: _moto!.videos,
                  imageUrl: _moto!.imageUrl,
                  forcePhoto: forcePhoto,
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

              _beamSweep(size, beam),

              // Ohňostroj + rázová vlna z místa emblému (úvodní reveal).
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
                          Colors.black.withValues(alpha: 0.5 * emblemIn),
                          Colors.black.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Logo MotoGo24 UPROSTŘED — reveal ranku na začátku.
              Align(
                alignment: const Alignment(0, -0.12),
                child: Opacity(
                  opacity: _seg(0.18, 0.9),
                  child: Transform.scale(
                    scale: 0.6 + 0.4 * emblemIn,
                    child:
                        _emblem(ringMix, emblemIn, badgeIn, pulseGlow, accent, tr),
                  ),
                ),
              ),

              // Záblesk v momentě přeblku barvy (reveal).
              if (flash > 0.01)
                IgnorePointer(
                  child: Container(
                    color: (_gold ? const Color(0xFFFFE9AA) : Colors.white)
                        .withValues(alpha: 0.45 * flash),
                  ),
                ),

              // Spodní prémiový text + tlačítko „Pokračovat".
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
        );
      },
    );
  }

  Widget _emblem(double ringMix, double emblemIn, double badgeIn,
      double pulseGlow, Color accent, String Function(String) tr) {
    final ringColor = Color.lerp(widget.fromColor, accent, ringMix)!;
    final glowC = _gold && ringMix > 0.9 ? const Color(0xFFFF8C00) : ringColor;
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
                    color: glowC.withValues(alpha: 0.65 * emblemIn),
                    blurRadius: pulseGlow,
                    spreadRadius: 3 * emblemIn,
                  ),
                  BoxShadow(
                    color: glowC.withValues(alpha: 0.30 * emblemIn),
                    blurRadius: pulseGlow * 2.6,
                    spreadRadius: 10 * emblemIn,
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
            // Vždy odznak „+N" (i pro +1).
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
        Text(
          tr('loyaltyDiscountForever').replaceAll('{pct}', '${status.percent}'),
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
            onTap: _close, // „Pokračovat" = zavřít oslavu
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
                  BoxShadow(color: glow.withValues(alpha: 0.5), blurRadius: 18),
                ],
              ),
              child: Text(
                tr('loyaltyContinue'),
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
          color:
              _gold ? const Color(0xFF241A06) : _onColor(widget.status.color),
        ),
      ),
    );
  }

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
    final shadows = [
      Shadow(color: accent.withValues(alpha: 0.9), blurRadius: 18),
      Shadow(color: accent.withValues(alpha: 0.5), blurRadius: 36),
    ];
    final text = Text(
      status.rankName.toUpperCase(),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.2,
        height: 1.05,
        color: _gold ? Colors.white : accent,
        shadows: shadows,
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

/// Hudba na pozadí — přehraje se JEN JEDNOU. Přehráváme přes `video_player`
/// (umí audio-only asset), takže nepotřebujeme další závislost. Fail-open:
/// když se nepovede, scéna běží dál bez hudby (master clock je controller).
class _BgMusic extends StatefulWidget {
  const _BgMusic();
  @override
  State<_BgMusic> createState() => _BgMusicState();
}

class _BgMusicState extends State<_BgMusic> {
  VideoPlayerController? _c;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _go();
  }

  Future<void> _go() async {
    try {
      final c = VideoPlayerController.asset(
        'assets/levelup_music.mp3',
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _c = c;
      await c.initialize();
      if (_disposed) {
        await c.dispose();
        return;
      }
      await c.setVolume(1.0);
      await c.setLooping(false);
      await c.play();
    } catch (_) {/* fail-open */}
  }

  @override
  void dispose() {
    _disposed = true;
    _c?.pause();
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Montáž médií poslední rezervované motorky: videa se přehrají po sobě
/// (full-screen, muted, každé 1×), po dojetí všech zůstane hlavní fotka
/// (Ken Burns). `forcePhoto` (posledních 5 s) přepne na fotku okamžitě.
class _MediaMontage extends StatefulWidget {
  final List<String> videos;
  final String? imageUrl;
  final bool forcePhoto;
  const _MediaMontage({
    required this.videos,
    this.imageUrl,
    this.forcePhoto = false,
  });

  @override
  State<_MediaMontage> createState() => _MediaMontageState();
}

class _MediaMontageState extends State<_MediaMontage> {
  VideoPlayerController? _c;
  int _idx = 0;
  bool _photo = false;
  bool _advancing = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    if (widget.forcePhoto || widget.videos.isEmpty) {
      _photo = true;
    } else {
      _load(0);
    }
  }

  @override
  void didUpdateWidget(covariant _MediaMontage old) {
    super.didUpdateWidget(old);
    if (widget.forcePhoto && !_photo) _toPhoto();
  }

  Future<void> _load(int i) async {
    _advancing = false;
    final old = _c;
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.videos[i]));
    _c = c;
    _idx = i;
    try {
      await c.initialize();
      if (_disposed) {
        await c.dispose();
        return;
      }
      await c.setVolume(0); // hudba jde z pozadí, videa němá
      await c.setLooping(false);
      await c.play();
      c.addListener(_tick);
      if (mounted) setState(() {});
    } catch (_) {
      if (!_disposed && i + 1 < widget.videos.length) {
        _load(i + 1);
      } else {
        _toPhoto();
      }
    }
    old?.removeListener(_tick);
    await old?.dispose();
  }

  void _tick() {
    final c = _c;
    if (c == null || _disposed || _advancing) return;
    final v = c.value;
    if (!v.isInitialized) return;
    if (widget.forcePhoto) {
      _toPhoto();
      return;
    }
    if (v.duration > Duration.zero &&
        v.position >= v.duration - const Duration(milliseconds: 90)) {
      _advancing = true;
      if (_idx + 1 < widget.videos.length) {
        _load(_idx + 1);
      } else {
        _toPhoto();
      }
    }
  }

  void _toPhoto() {
    if (_photo) return;
    _photo = true;
    final c = _c;
    _c = null;
    c?.removeListener(_tick);
    c?.pause();
    c?.dispose();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _disposed = true;
    _c?.removeListener(_tick);
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_photo) {
      final url = widget.imageUrl;
      if (url == null || url.trim().isEmpty) return const SizedBox.shrink();
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 1.0, end: 1.14),
        duration: const Duration(seconds: 9),
        curve: Curves.easeOut,
        builder: (_, s, __) => Transform.scale(
          scale: s,
          child: MgImage(
            url,
            thumbWidth: 1000,
            fit: BoxFit.cover,
            placeholder: const SizedBox.shrink(),
            error: const SizedBox.shrink(),
          ),
        ),
      );
    }
    final c = _c;
    if (c == null || !c.value.isInitialized) return const SizedBox.shrink();
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
  final double speed;
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
    if (shock > 0 && shock < 1) {
      final r = shock * size.shortestSide * 0.9;
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 * (1 - shock)
        ..color = const Color(0xFFFFD700).withValues(alpha: 0.5 * (1 - shock));
      canvas.drawCircle(center, r, ring);
    }

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
        ..color =
            (i % 3 == 0 ? secondary : color).withValues(alpha: 0.9 * fade);
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
