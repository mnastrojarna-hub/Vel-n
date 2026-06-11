import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import 'loyalty_provider.dart';

/// Karta věrnostního ranku v profilu — název, % slevy, progress do dalšího
/// levelu. Zobrazí se jen když backend vrátí rank (jinak nic nerendruje).
class LoyaltyRankCard extends ConsumerWidget {
  const LoyaltyRankCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(loyaltyStatusProvider).valueOrNull;
    if (status == null) return const SizedBox.shrink();

    final color = status.color;
    String tr(String key) => t(context).tr(key);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Titulek sekce — rendruje se jen společně s kartou.
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(
            tr('loyaltyMyRank').toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: MotoGoColors.g500,
            ),
          ),
        ),
        _card(context, status, color, tr),
      ],
    );
  }

  Widget _card(BuildContext context, LoyaltyStatus status, Color color,
      String Function(String) tr) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
        boxShadow: [
          BoxShadow(
            color: MotoGoColors.black.withValues(alpha: 0.06),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tmavý pill — světlé/metalické barvy ranků vyniknou jako v hlavičce.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: MotoGoColors.dark,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 14,
                  spreadRadius: 0.5,
                ),
              ],
            ),
            child: Row(
              children: [
                const Text('🏅', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: _rankNameText(
                    status.rankName.toUpperCase(),
                    status,
                    fontSize: 14,
                  ),
                ),
                _rankNameText('${status.percent} %', status, fontSize: 18),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Progress bar 1–20
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Container(color: MotoGoColors.g200),
                  FractionallySizedBox(
                    widthFactor:
                        (status.level / status.maxLevel).clamp(0.05, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: status.isLegend ? null : color,
                        gradient: status.isLegend
                            ? const LinearGradient(
                                colors: legendGradientColors)
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),

          Text(
            '${tr('loyaltyLevelOf').replaceAll('{lvl}', '${status.level}').replaceAll('{max}', '${status.maxLevel}')}'
            ' · ${tr('loyaltyBookingsCount').replaceAll('{n}', '${status.qualifyingCount}')}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: MotoGoColors.g600,
            ),
          ),
          const SizedBox(height: 4),

          // Další rank / max rank
          if (!status.isMax &&
              status.nextRankName != null &&
              status.bookingsToNext != null)
            Text(
              tr('loyaltyNextRank')
                  .replaceAll('{n}', '${status.bookingsToNext}')
                  .replaceAll('{next}', status.nextRankName!)
                  .replaceAll('{pct}', '${status.nextPercent ?? ''}'),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: MotoGoColors.black,
              ),
            )
          else
            Text(
              tr('loyaltyMaxRank'),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: MotoGoColors.greenDarker,
              ),
            ),
          const SizedBox(height: 6),

          // POZOR: sleva platí jen pro rezervace vytvořené v aplikaci.
          Text(
            '★ ${tr('loyaltyAppOnly')}',
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: MotoGoColors.g400,
            ),
          ),
        ],
      ),
    );
  }

  /// Text v barvě ranku; Legenda (lvl 20) má zlato-oranžový gradient.
  Widget _rankNameText(String text, LoyaltyStatus status,
      {required double fontSize}) {
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      color: status.isLegend ? Colors.white : status.color,
      letterSpacing: 0.5,
    );
    final widget = Text(text, style: style, overflow: TextOverflow.ellipsis);
    if (!status.isLegend) return widget;
    return ShaderMask(
      shaderCallback: (bounds) =>
          const LinearGradient(colors: legendGradientColors)
              .createShader(bounds),
      child: widget,
    );
  }
}
