import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/widgets/moto_fx.dart';
import 'loyalty_provider.dart';
import 'loyalty_levels_provider.dart';
import 'loyalty_leaderboard_section.dart';

/// Od tohoto ranku má zákazník veškerou výbavu i obuv (vč. spolujezdce) zdarma
/// — shodné s `loyaltyFreeGearLevel` v booking_models.dart.
const _gearBenefitLevel = 3;

/// Celostránkový animovaný přehled věrnostních ranků.
///
/// Otevírá se klepnutím na „ikonu ranku" (MG logo s prstencem) v hlavičce.
/// Žebříček všech 20 ranků je vykreslen jako HORA: vrchol (Legenda) nahoře
/// jako aspirace, Startér dole. Aktuální rank pilota září (GlowPulse +
/// ShimmerSweep), odemčené ranky mají plnou barvu, zamčené jsou ztlumené.
/// Čistě gamifikace — žádná jiná funkčnost, jen motivace k dalšímu růstu.
class LoyaltyRanksScreen extends ConsumerWidget {
  const LoyaltyRanksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(loyaltyStatusProvider).valueOrNull;
    final levelsAsync = ref.watch(loyaltyLevelsProvider);
    String tr(String key) => t(context).tr(key);

    return Scaffold(
      backgroundColor: MotoGoColors.gradientTop,
      body: Stack(
        children: [
          // Ambientní animované pozadí — pomalu plující jiskry.
          const Positioned.fill(child: _AmbientSparks()),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    MotoGoColors.gradientTop,
                    MotoGoColors.gradientMid.withValues(alpha: 0.85),
                    MotoGoColors.gradientBot.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: levelsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: MotoGoColors.green),
              ),
              error: (_, __) => const SizedBox.shrink(),
              data: (levels) => CustomScrollView(
                slivers: [
                  _topBar(context, tr),
                  SliverToBoxAdapter(child: _Hero(status: status, tr: tr)),
                  const SliverToBoxAdapter(child: LoyaltyLeaderboardSection()),
                  _ladder(levels, status, tr),
                  SliverToBoxAdapter(child: _RulesCard(tr: tr)),
                  const SliverToBoxAdapter(child: SizedBox(height: 28)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar(BuildContext context, String Function(String) tr) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
        child: Row(
          children: [
            IconButton(
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/');
                }
              },
              icon: const Icon(Icons.arrow_back_ios_new,
                  color: Colors.white, size: 20),
            ),
            Expanded(
              child: Text(
                tr('loyaltyRanksTitle'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const Text('🏍️', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  /// Žebříček odshora (Legenda, level 20) dolů (Startér, level 1) — pilot
  /// vidí „vrchol hory", kam může vystoupat.
  Widget _ladder(
    List<LoyaltyLevel> levels,
    LoyaltyStatus? status,
    String Function(String) tr,
  ) {
    final current = status?.level ?? 0;
    final descending = levels.reversed.toList();
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final lvl = descending[i];
            return StaggeredReveal(
              index: i.clamp(0, 10),
              baseDelay: const Duration(milliseconds: 220),
              child: _RankTile(
                level: lvl,
                state: lvl.level == current
                    ? _TileState.current
                    : (lvl.level < current
                        ? _TileState.unlocked
                        : _TileState.locked),
                isFirst: i == 0,
                isLast: i == descending.length - 1,
                tr: tr,
              ),
            );
          },
          childCount: descending.length,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// HERO — můj aktuální rank (záře, count-up %, progress do dalšího)
// ════════════════════════════════════════════════════════════════════

class _Hero extends StatefulWidget {
  final LoyaltyStatus? status;
  final String Function(String) tr;
  const _Hero({required this.status, required this.tr});

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.status;
    final tr = widget.tr;
    // Bez statusu (nepřihlášen) — uvítací varianta s prvním rankem.
    final color = s?.color ?? MotoGoColors.green;
    final isLegend = s?.isLegend ?? false;
    final glow = isLegend ? const Color(0xFFFF8C00) : color;

    final progress = s == null
        ? 0.05
        : (s.level / s.maxLevel).clamp(0.05, 1.0);

    return AnimatedBuilder(
      animation: _intro,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_intro.value);
        final pct = ((s?.percent ?? 0) * t).round();
        final bar = progress * Curves.easeOutCubic
            .transform((_intro.value).clamp(0.0, 1.0));
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - t)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
              child: Column(
                children: [
                  // Logo s pulzujícím prstencem v barvě ranku.
                  GlowPulse(
                    color: glow,
                    borderRadius: BorderRadius.circular(30),
                    minBlur: 14,
                    maxBlur: 40,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        color: isLegend ? null : color,
                        gradient: isLegend
                            ? const LinearGradient(
                                colors: legendGradientColors,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Image.asset(
                          'assets/logo.webp',
                          width: 96,
                          height: 96,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 96,
                            height: 96,
                            color: Colors.black,
                            child: const Icon(Icons.motorcycle,
                                size: 44, color: MotoGoColors.green),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    (s == null
                            ? tr('loyaltyInfoTitle')
                            : tr('loyaltyMyRank'))
                        .toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _rankName(s?.rankName ?? 'Startér', color, isLegend),
                  const SizedBox(height: 8),
                  // Velké procento slevy (count-up).
                  _rankName('$pct %', color, isLegend, big: true),
                  const SizedBox(height: 14),
                  // Progress bar level X / 20.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      height: 10,
                      child: Stack(
                        children: [
                          Container(color: Colors.white.withValues(alpha: 0.12)),
                          FractionallySizedBox(
                            widthFactor: bar.clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isLegend ? null : color,
                                gradient: isLegend
                                    ? const LinearGradient(
                                        colors: legendGradientColors)
                                    : null,
                                boxShadow: [
                                  BoxShadow(
                                      color: glow.withValues(alpha: 0.6),
                                      blurRadius: 10),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    s == null
                        ? tr('loyaltyAppOnly')
                        : (s.isMax || s.nextRankName == null
                            ? tr('loyaltyMaxRank')
                            : tr('loyaltyNextRank')
                                .replaceAll('{n}', '${s.bookingsToNext}')
                                .replaceAll('{next}', s.nextRankName!)
                                .replaceAll('{pct}', '${s.nextPercent ?? ''}')),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  if (s != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${tr('loyaltyLevelOf').replaceAll('{lvl}', '${s.level}').replaceAll('{max}', '${s.maxLevel}')}'
                      ' · ${tr('loyaltyBookingsCount').replaceAll('{n}', '${s.qualifyingCount}')}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    tr('loyaltyClimbMotivation'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.45),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _rankName(String text, Color color, bool isLegend,
      {bool big = false}) {
    final style = TextStyle(
      fontSize: big ? 40 : 22,
      fontWeight: FontWeight.w900,
      letterSpacing: big ? 0 : 0.5,
      color: isLegend ? Colors.white : color,
    );
    final w = Text(text, style: style, textAlign: TextAlign.center);
    if (!isLegend) return w;
    return ShaderMask(
      shaderCallback: (b) =>
          const LinearGradient(colors: legendGradientColors).createShader(b),
      child: w,
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// RANK TILE — jeden řádek žebříčku
// ════════════════════════════════════════════════════════════════════

enum _TileState { unlocked, current, locked }

class _RankTile extends StatelessWidget {
  final LoyaltyLevel level;
  final _TileState state;
  final bool isFirst;
  final bool isLast;
  final String Function(String) tr;

  const _RankTile({
    required this.level,
    required this.state,
    required this.isFirst,
    required this.isLast,
    required this.tr,
  });

  @override
  Widget build(BuildContext context) {
    final color = colorFromHex(level.colorHex);
    final isCurrent = state == _TileState.current;
    final isLocked = state == _TileState.locked;
    final medallion = _medallion(color);

    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: isCurrent
            ? MotoGoColors.dark
            : Colors.white.withValues(alpha: isLocked ? 0.05 : 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent
              ? color.withValues(alpha: 0.7)
              : Colors.white.withValues(alpha: isLocked ? 0.05 : 0.12),
          width: isCurrent ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          medallion,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        level.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: isLocked
                              ? Colors.white.withValues(alpha: 0.5)
                              : Colors.white,
                        ),
                      ),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: 8),
                      _youChip(color),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  tr('loyaltyFromBooking')
                      .replaceAll('{n}', '${level.minBookingOrder}'),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
                // Od 3. ranku: výbava spolujezdce i veškerá obuv zdarma.
                if (level.level >= _gearBenefitLevel) ...[
                  const SizedBox(height: 3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('🎒 ', style: TextStyle(fontSize: 10.5)),
                      Expanded(
                        child: Text(
                          tr('loyaltyGearBenefit'),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isLocked
                                ? MotoGoColors.green.withValues(alpha: 0.5)
                                : MotoGoColors.green,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _percentPill(color, isLocked),
        ],
      ),
    );

    Widget tile = card;
    if (isCurrent) {
      tile = GlowPulse(
        color: level.isLegend ? const Color(0xFFFF8C00) : color,
        borderRadius: BorderRadius.circular(16),
        minBlur: 10,
        maxBlur: 30,
        child: ShimmerSweep(
          color: color,
          borderRadius: BorderRadius.circular(16),
          child: card,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: tile,
    );
  }

  Widget _medallion(Color color) {
    final isCurrent = state == _TileState.current;
    final isLocked = state == _TileState.locked;
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        color: level.isLegend ? null : color.withValues(alpha: isLocked ? 0.5 : 1),
        gradient: level.isLegend
            ? LinearGradient(
                colors: isLocked
                    ? legendGradientColors
                        .map((c) => c.withValues(alpha: 0.5))
                        .toList()
                    : legendGradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        boxShadow: isLocked
            ? null
            : [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10)],
      ),
      child: Center(
        child: isLocked
            ? Icon(Icons.lock_rounded,
                size: 18, color: Colors.black.withValues(alpha: 0.45))
            : (isCurrent
                ? const Text('🏅', style: TextStyle(fontSize: 20))
                : Text(
                    '${level.level}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _onColor(color),
                    ),
                  )),
      ),
    );
  }

  Widget _percentPill(Color color, bool isLocked) {
    final text = Text(
      '${level.percent} %',
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w900,
        color: isLocked
            ? Colors.white.withValues(alpha: 0.4)
            : (level.isLegend ? Colors.white : color),
      ),
    );
    if (level.isLegend && !isLocked) {
      return ShaderMask(
        shaderCallback: (b) =>
            const LinearGradient(colors: legendGradientColors).createShader(b),
        child: text,
      );
    }
    return text;
  }

  Widget _youChip(Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: level.isLegend ? const Color(0xFFFF8C00) : color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        tr('loyaltyYouChip'),
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          color: _onColor(level.isLegend ? const Color(0xFFFF8C00) : color),
        ),
      ),
    );
  }

  Color _onColor(Color c) =>
      c.computeLuminance() > 0.5 ? const Color(0xFF0F1A14) : Colors.white;
}

// ════════════════════════════════════════════════════════════════════
// RULES CARD — jak věrnostní program funguje
// ════════════════════════════════════════════════════════════════════

class _RulesCard extends StatelessWidget {
  final String Function(String) tr;
  const _RulesCard({required this.tr});

  @override
  Widget build(BuildContext context) {
    final rules = [
      tr('loyaltyRulePoints'),
      tr('loyaltyRuleLong'),
      tr('loyaltyRuleLevel'),
      tr('loyaltyRuleGear'),
      tr('loyaltyRuleAppOnly'),
      tr('loyaltyRuleCombo'),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🏅 ${tr('loyaltyInfoTitle')}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          for (final r in rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('✓ ',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: MotoGoColors.green)),
                  Expanded(
                    child: Text(
                      r,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.75),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// AMBIENT SPARKS — pomalu plující jiskry v pozadí
// ════════════════════════════════════════════════════════════════════

class _AmbientSparks extends StatefulWidget {
  const _AmbientSparks();

  @override
  State<_AmbientSparks> createState() => _AmbientSparksState();
}

class _AmbientSparksState extends State<_AmbientSparks>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) => CustomPaint(
          painter: _SparkFieldPainter(_ctrl.value),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _SparkFieldPainter extends CustomPainter {
  final double t;
  _SparkFieldPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    const count = 26;
    for (var i = 0; i < count; i++) {
      final fi = i.toDouble();
      final x = ((math.sin(fi * 12.9898) + 1) / 2) * size.width;
      // Pomalu stoupají; po dosažení vrcholu se přesunou dolů (modulo).
      final speed = 0.4 + ((math.sin(fi * 78.233) + 1) / 2) * 0.6;
      final raw = (1 - ((t * speed + fi / count) % 1.0));
      final y = raw * size.height;
      final twinkle = 0.25 + 0.55 * ((math.sin((t * 6.28 * 2) + fi) + 1) / 2);
      final radius = 1.0 + ((math.sin(fi * 39.425) + 1) / 2) * 1.8;
      final paint = Paint()
        ..color = (i % 4 == 0 ? MotoGoColors.green : Colors.white)
            .withValues(alpha: 0.10 + 0.18 * twinkle);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_SparkFieldPainter old) => old.t != t;
}

/// Otevře přehled ranků (volá se z hlavičky po klepnutí na logo).
void openLoyaltyRanks(BuildContext context) {
  HapticFeedback.lightImpact();
  context.push('/loyalty');
}
