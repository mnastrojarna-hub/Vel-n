import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/router.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/widgets/moto_fx.dart';
import 'loyalty_provider.dart';

/// Prémiový rank banner na domovské obrazovce — ať zákazník hned vidí, jak
/// vysoko v komunitě stojí, a co mu zbývá k dalšímu ranku (motivace růstu).
/// Pulzuje + leskne se v barvě ranku. Skryje se, dokud backend rank nevrací.
class HomeRankBanner extends ConsumerWidget {
  const HomeRankBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(loyaltyStatusProvider).valueOrNull;
    if (status == null) return const SizedBox.shrink();
    final color = status.color;
    String tr(String k) => t(context).tr(k);
    final progress = (status.level / status.maxLevel).clamp(0.04, 1.0);
    final nextLine = (!status.isMax &&
            status.nextRankName != null &&
            status.bookingsToNext != null)
        ? tr('loyaltyNextRank')
            .replaceAll('{n}', '${status.bookingsToNext}')
            .replaceAll('{next}', status.nextRankName!)
            .replaceAll('{pct}', '${status.nextPercent ?? ''}')
        : tr('loyaltyMaxRank');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: PressableScale(
        pressedScale: 0.97,
        onTap: () => context.go(Routes.profile),
        child: GlowPulse(
          color: color,
          borderRadius: BorderRadius.circular(16),
          minBlur: 10,
          maxBlur: 26,
          child: ShimmerSweep(
            color: color,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A2E22), Color(0xFF0F1A14)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.6), width: 1.3),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('🏅', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Text(
                        tr('loyaltyMyRank').toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: color.withValues(alpha: 0.6)),
                        ),
                        child: Text('${status.percent} %',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: status.isLegend ? Colors.white : color)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _rankName(status, color),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 8,
                      child: Stack(children: [
                        Container(color: Colors.white.withValues(alpha: 0.12)),
                        FractionallySizedBox(
                          widthFactor: progress,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: status.isLegend
                                  ? const LinearGradient(colors: legendGradientColors)
                                  : LinearGradient(
                                      colors: [color, color.withValues(alpha: 0.55)]),
                              boxShadow: [
                                BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8),
                              ],
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(nextLine,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.85))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rankName(LoyaltyStatus status, Color color) {
    final w = Text(
      status.rankName.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.5,
        color: status.isLegend ? Colors.white : color,
      ),
    );
    if (!status.isLegend) return w;
    return ShaderMask(
      shaderCallback: (b) =>
          const LinearGradient(colors: legendGradientColors).createShader(b),
      child: w,
    );
  }
}
