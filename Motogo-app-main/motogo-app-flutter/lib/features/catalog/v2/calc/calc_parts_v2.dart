import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/rank/rank_copy.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_chips.dart';
import '../../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../../core/v2/widgets/mg_surfaces.dart';
import '../../../loyalty/loyalty_provider.dart';

/// Light head of the calculator (V22 §2.4 Kalkulačka): dark eyebrow pill
/// "KALKULAČKA CENY", rank chip (dark pill + dot), H2 ink, lead.
class CalcHeadCardV2 extends ConsumerWidget {
  const CalcHeadCardV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final loyalty = ref.watch(loyaltyStatusProvider).valueOrNull;
    return MgCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          MgEyebrowDark(tr.tr('v2CalcEyebrow'), icon: MgIcons.calc),
          if (loyalty != null && loyalty.level >= 1)
            MgRankChip(
              onLight: true,
              label: RankCopy.chip(tr, RankCopy.name(tr, loyalty.level, loyalty.rankName), loyalty.percent),
            ),
        ]),
        const SizedBox(height: 14),
        Semantics(header: true, child: Text(tr.tr('v2CalcTitle'), style: MgType.h2.copyWith(color: MgColors.ink))),
        const SizedBox(height: 6),
        Text(tr.tr('v2CalcLead'), style: MgType.body.copyWith(color: MgColors.lead)),
      ]),
    );
  }
}

/// One numbered step of the calculator: 34 px dark disc with a neon number
/// (✓ when [done]), title 17/800 and the step body in a white card.
class CalcStepCardV2 extends StatelessWidget {
  final int n;
  final bool done;
  final String title;
  final Widget? trailing;
  final Widget child;

  const CalcStepCardV2({
    super.key,
    required this.n,
    required this.title,
    required this.child,
    this.done = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => MgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            CalcStepBadge(n: n, done: done),
            const SizedBox(width: 10),
            Expanded(
              child: Semantics(header: true, child: Text(title, style: MgType.section.copyWith(color: MgColors.ink))),
            ),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      );
}

class CalcStepBadge extends StatelessWidget {
  final int n;
  final bool done;
  const CalcStepBadge({super.key, required this.n, required this.done});

  @override
  Widget build(BuildContext context) => Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done ? MgColors.neon : MgColors.panel,
          boxShadow: [BoxShadow(color: MgColors.neonA(done ? 0.4 : 0.3), spreadRadius: 2)],
        ),
        child: Center(
          child: done
              ? MgPop(trigger: done, child: MgIcon(MgIcons.check, size: 18, color: MgColors.onNeon, stroke: 2.6))
              : Text('$n', style: MgType.tab(MgType.title.copyWith(fontWeight: FontWeight.w900, color: MgColors.neon))),
        ),
      );
}

/// Amber / info hint line used inside the steps (T3-like, no action).
class CalcHint extends StatelessWidget {
  final String text;
  final bool warn;
  const CalcHint(this.text, {super.key, this.warn = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: warn ? MgColors.warnBg : MgColors.well,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: warn ? MgColors.warnBorder : MgColors.line),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          MgIcon(warn ? MgIcons.warn : MgIcons.info, size: 18, color: warn ? MgColors.warn : MgColors.link),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: MgType.small.copyWith(color: warn ? MgColors.warn : MgColors.body2)),
          ),
        ]),
      );
}
