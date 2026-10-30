import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/rank/rank_copy.dart';
import '../../../core/v2/rank/rank_frame.dart';
import '../../../core/v2/rank/rank_provider.dart';
import '../../../core/v2/rank/rank_tokens.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../booking/booking_models.dart' show loyaltyFreeGearLevel;
import '../loyalty_levels_provider.dart';
import 'loyalty_status_parts_v2.dart';

/// The 20-level ladder grouped by the 5 tiers (V21 P4, V22 §1.5): tier
/// header (emblem + "Silnice / Kovová liga / …" + "od X bodů"), then each
/// level as a row previewing ITS OWN colour (`rankTokensForLevel`): mini
/// frame with the level number, name, "od {2L−2} bodů", passenger-gear
/// benefit from level 3, % pill, "TY" on the current one, lock when locked.
/// Top (Legenda) first, like today.
class LoyaltyLadderV2 extends StatelessWidget {
  final List<LoyaltyLevel> levels;
  final int current;
  const LoyaltyLadderV2({super.key, required this.levels, required this.current});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final desc = levels.reversed.toList();
    final groups = <RankTier, List<LoyaltyLevel>>{};
    for (final l in desc) {
      groups.putIfAbsent(RankTokens.forLevel(l.level).tier, () => []).add(l);
    }
    var row = 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final entry in groups.entries) ...[
        _TierHeader(tier: entry.key, locked: entry.value.every((l) => l.level > current)),
        for (final l in entry.value)
          MgReveal(
            index: (row++).clamp(0, 5),
            sessionKey: 'ladder-${l.level}',
            child: _LevelRow(level: l, current: current, tr: tr),
          ),
        const SizedBox(height: 12),
      ],
    ]);
  }
}

class _TierHeader extends StatelessWidget {
  final RankTier tier;
  final bool locked;
  const _TierHeader({required this.tier, required this.locked});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final first = RankTokens.forLevel(const [1, 6, 10, 17, 20][tier.index]);
    final to = first.tierTo;
    return Opacity(
      opacity: locked ? 0.75 : 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          RankEmblemV2(rank: first, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Semantics(header: true, child: Text(RankCopy.tierName(tr, tier), style: MgType.title.copyWith(color: MgColors.onDark))),
              Text(
                '${first.level == to ? '${first.level}' : '${first.level}–$to'} · '
                '${tr.tr('loyaltyFromBooking').replaceAll('{n}', '${2 * first.level - 2}')}',
                style: MgType.tab(MgType.micro.copyWith(color: MgColors.onDarkMeta)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _LevelRow extends StatelessWidget {
  final LoyaltyLevel level;
  final int current;
  final AppTranslations tr;
  const _LevelRow({required this.level, required this.current, required this.tr});

  @override
  Widget build(BuildContext context) {
    final r = rankTokensForLevel(level.level, level.colorHex);
    final isCurrent = level.level == current;
    final locked = level.level > current;
    final frame = Opacity(
      opacity: locked ? 0.6 : 1,
      child: RankFrame(
        size: 40,
        rank: r,
        showArc: false,
        showLevel: false,
        showMarks: false,
        showGlyph: false,
        glow: !locked,
        child: ColoredBox(
          color: MgColors.night,
          child: Center(
            child: Text('${level.level}', style: MgType.tab(MgType.body.copyWith(fontWeight: FontWeight.w900, color: r.accentOnDark))),
          ),
        ),
      ),
    );
    return Semantics(
      label: '${RankCopy.name(tr, level.level, level.name)}, ${level.percent} %${isCurrent ? ', ${tr.tr('loyaltyYouChip')}' : ''}',
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isCurrent ? MgColors.neonA(0.10) : MgColors.white(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isCurrent ? MgColors.neonA(0.55) : MgColors.white(0.06), width: isCurrent ? 1.5 : 1),
        ),
        // Benefit (výbava zdarma) pod celým řádkem — na plnou šířku, ne vedle
        // odznaků (nl „Passagiersuitrusting" se jinak lámal uprostřed slova).
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
         Row(children: [
          frame,
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // 0.7: dlouhé ranky (uk „Діамантовий“, en „Ambassador“) vedle čipů TY + %.
              MgWordFit(
                minScale: 0.7,
                child: Text(RankCopy.name(tr, level.level, level.name),
                    style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: locked ? MgColors.onDarkLead : MgColors.onDark)),
              ),
              Text(tr.tr('loyaltyFromBooking').replaceAll('{n}', '${2 * level.level - 2}'),
                  style: MgType.tab(MgType.micro.copyWith(fontWeight: FontWeight.w600, color: MgColors.onDarkMeta))),
            ]),
          ),
          const SizedBox(width: 8),
          if (isCurrent) ...[
            MgPop(
              playOnMount: true,
              child: Container(
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(color: MgColors.neon, borderRadius: BorderRadius.circular(999)),
                child: Center(
                  widthFactor: 1,
                  child: Text(tr.tr('loyaltyYouChip'),
                      style: MgType.micro.copyWith(fontWeight: FontWeight.w900, height: 1, letterSpacing: 0.6, color: MgColors.onNeon)),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(color: MgColors.white(0.08), borderRadius: BorderRadius.circular(999)),
            child: Center(
              widthFactor: 1,
              child: Text('${level.percent} %',
                  style: MgType.tab(MgType.meta.copyWith(fontWeight: FontWeight.w900, height: 1, color: MgColors.onDark))),
            ),
          ),
          if (locked) ...[
            const SizedBox(width: 6),
            const MgIcon(MgIcons.lock, size: 16, color: MgColors.onDarkFloor),
          ],
         ]),
          if (level.level >= loyaltyFreeGearLevel)
            Padding(
              padding: const EdgeInsets.only(left: 52, top: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                MgIcon(MgIcons.vest, size: 14, color: locked ? MgColors.neonText.withValues(alpha: 0.6) : MgColors.neonText),
                const SizedBox(width: 4),
                Expanded(
                  child: MgWordFit(
                    minScale: 0.85,
                    child: Text(tr.tr('loyaltyGearBenefit'),
                        style: MgType.micro.copyWith(color: locked ? MgColors.neonText.withValues(alpha: 0.6) : MgColors.neonText)),
                  ),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}
