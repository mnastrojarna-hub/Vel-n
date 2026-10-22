import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim_loops.dart';
import '../../../core/v2/rank/rank_copy.dart';
import '../../../core/v2/rank/rank_frame.dart';
import '../../../core/v2/rank/rank_hero.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_chips.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../loyalty/loyalty_provider.dart';
import 'res_fit_v2.dart';

/// Compact dark rank header of the Rezervace tab (V22 `.ls-h`): logo in the
/// tier ring, "Moje rezervace" + "Přehled všech rezervací", a "Živě" pill
/// (the list refreshes by itself — realtime + every 5 s, as today) and the
/// rank chip. Tab root → no back control (the nav is the way out; system
/// back → Home via the shell's `MgBackGuard`, unchanged).
class ResListHeaderV2 extends ConsumerWidget {
  const ResListHeaderV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final status = ref.watch(loyaltyStatusProvider).valueOrNull;
    final frame = RankFrame(
      size: 44,
      showMarks: false,
      semanticLabel: status == null ? null : RankCopy.aria(tr, status.level, RankCopy.name(tr, status.level, status.rankName), status.percent),
      child: Image.asset(
        'assets/logo.webp',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const ColoredBox(
          color: MgColors.neon,
          child: Center(child: MgIcon(MgIcons.moto, size: 22, color: MgColors.onNeon)),
        ),
      ),
    );
    return MgRankHero(
      ambientKey: 'reservations',
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LayoutBuilder(builder: (context, c) {
          final titleStyle = MgType.h2.copyWith(color: MgColors.onDark);
          final heading = Semantics(
            header: true,
            child: MgWordFit(minScale: 0.75, child: Text(tr.tr('myReservations'), style: titleStyle)),
          );
          final sub = Text(tr.tr('resOverview'), style: MgType.small.copyWith(color: MgColors.onDarkSecondary));
          // „Živě" vedle nadpisu jen když se nadpis vejde celými slovy
          // (de / fr / nl / pl / uk na 320 dp, velké písmo) — jinak pod ním.
          final pillW = resLineWidth(context, tr.tr('v2ResLive'), _LivePill.style) + 36;
          final inline = resWordsFit(context, tr.tr('myReservations'), titleStyle, c.maxWidth - 52 - 10 - 8 - pillW, minScale: 0.75);
          return Row(children: [
            Padding(padding: const EdgeInsets.all(4), child: frame),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                heading,
                const SizedBox(height: 2),
                sub,
                if (!inline) ...[const SizedBox(height: 8), const _LivePill()],
              ]),
            ),
            if (inline) ...[const SizedBox(width: 8), const _LivePill()],
          ]);
        }),
        if (status != null) ...[
          const SizedBox(height: 12),
          MgRankChip(
            label: RankCopy.chip(tr, RankCopy.name(tr, status.level, status.rankName), status.percent),
            semanticLabel: RankCopy.aria(tr, status.level, RankCopy.name(tr, status.level, status.rankName), status.percent),
          ),
        ],
      ]),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill();

  static final style = MgType.micro.copyWith(fontWeight: FontWeight.w800, color: MgColors.neonText);

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Semantics(
      label: tr.tr('v2ResLiveA11y'),
      excludeSemantics: true,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: MgColors.neonA(0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: MgColors.neonA(0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const MgPing(size: 8, color: MgColors.neon),
          const SizedBox(width: 6),
          Text(tr.tr('v2ResLive'), style: style),
        ]),
      ),
    );
  }
}
