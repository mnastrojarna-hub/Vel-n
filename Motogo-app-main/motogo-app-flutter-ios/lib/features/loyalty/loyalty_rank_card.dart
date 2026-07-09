import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/widgets/moto_fx.dart';
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
          // Pulzující záře v barvě ranku → rank pilota „září" (požadavek).
          GlowPulse(
            color: color,
            borderRadius: BorderRadius.circular(12),
            minBlur: 8,
            maxBlur: 28,
            child: ShimmerSweep(
              color: color,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: MotoGoColors.dark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.55), width: 1.2),
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
          const SizedBox(height: 8),

          // Informace o programu — kompletní podmínky pro zákazníka.
          GestureDetector(
            onTap: () => _showProgramInfo(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('ℹ️', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 6),
                Text(
                  tr('loyaltyInfoBtn'),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: MotoGoColors.greenDarker,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Bottom sheet s podmínkami věrnostního programu.
  void _showProgramInfo(BuildContext context) {
    // Resolve ALL strings up-front against the (valid) caller context. The
    // modal bottom sheet builder runs in its own element subtree, and calling
    // t(ctx)/Localizations.localeOf inside it against the captured outer
    // context can crash on rebuild ("Null check operator used on a null value")
    // once that context's Localizations scope is no longer reachable.
    String tr(String key) => t(context).tr(key);
    final title = tr('loyaltyInfoTitle');
    final rules = [
      tr('loyaltyRulePoints'),
      tr('loyaltyRuleLong'),
      tr('loyaltyRuleLevel'),
      tr('loyaltyRuleAppOnly'),
      tr('loyaltyRuleCombo'),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '🏅 $title',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: MotoGoColors.black,
                ),
              ),
              const SizedBox(height: 12),
              for (final rule in rules)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('✓ ',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: MotoGoColors.greenDarker)),
                      Expanded(
                        child: Text(
                          rule,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: MotoGoColors.g600,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
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
