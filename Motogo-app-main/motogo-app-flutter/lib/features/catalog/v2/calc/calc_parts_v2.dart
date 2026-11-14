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
import '../catalog_text.dart';

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
/// (✓ when [done]), title 17/800 and the step body in a white card. [info]
/// = a step with nothing to choose: a light "i" tile instead of the number.
class CalcStepCardV2 extends StatelessWidget {
  final int n;
  final bool done;
  final bool info;
  final String title;
  final Widget? trailing;
  final Widget child;

  const CalcStepCardV2({
    super.key,
    required this.n,
    required this.title,
    required this.child,
    this.done = false,
    this.info = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => MgCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            info ? const CalcInfoBadge() : CalcStepBadge(n: n, done: done),
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

/// Badge of an information-only step (calculator ④, detail ②): the light
/// "i" icon tile in the 34 px slot of the step numbers.
class CalcInfoBadge extends StatelessWidget {
  const CalcInfoBadge({super.key});

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(child: MgIconTileLight(MgIcons.info, size: 34));
}

/// "Vyzvednutí od 12:00 = 1. den za polovinu" + the concrete saving (owner
/// 2026-10-22: information, the time is chosen in the booking form). Dark =
/// inside the calculator's total block, light = on a white card (detail).
class CalcHalfInfo extends StatelessWidget {
  final double save;
  final double total;
  final bool dark;
  const CalcHalfInfo({super.key, required this.save, required this.total, this.dark = true});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: dark ? MgColors.neonA(0.06) : MgColors.tintOk,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: dark ? MgColors.neonA(0.25) : MgColors.tintOkBorder),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(
          label: tr.tr('v2BkHalfA11y'),
          child: ExcludeSemantics(
            child: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(color: MgColors.neon, shape: BoxShape.circle),
              child: Center(
                child: Text('½', style: MgType.title.copyWith(fontWeight: FontWeight.w900, color: MgColors.onNeon)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 2),
            Text(tr.tr('v2LpCalcTitle'),
                style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: dark ? MgColors.onDark : MgColors.ink)),
            const SizedBox(height: 2),
            Text(
              tr.trArgs('v2LpCalcSave', {'amount': catMoney(save), 'total': catMoney(total)}),
              style: MgType.tab(MgType.small.copyWith(color: dark ? MgColors.onDarkLead : MgColors.body2)),
            ),
          ]),
        ),
      ]),
    );
  }
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
