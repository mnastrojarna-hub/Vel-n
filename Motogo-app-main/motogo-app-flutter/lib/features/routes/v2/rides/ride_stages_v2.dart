import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_shadows.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_word_fit.dart';
import '../../ride_card.dart' show rideDuration, rideKm, rideSpeed;
import '../../ride_model.dart';
import 'ride_track_sketch_v2.dart' show RideMetaV2;

/// "Etapy" (SPEC §9.3): every day of a multi-day ride / trip on its own —
/// Den N · weekday date · km · time in the saddle · Ø · max · climb ·
/// breaks inside the day. Nights and long breaks are between the days,
/// never inside them. Hidden for a single stage.
class RideStagesV2 extends StatelessWidget {
  final List<RideStage> stages;
  const RideStagesV2({super.key, required this.stages});

  @override
  Widget build(BuildContext context) {
    if (stages.length < 2) return const SizedBox.shrink();
    final tr = t(context);
    final loc = MaterialLocalizations.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const MgIcon(MgIcons.moon, size: 20, color: MgColors.routeGreen),
        const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            header: true,
            child: MgWordFit(minScale: 0.75, child: Text(tr.tr('v2RpStages'), style: MgType.section.copyWith(color: MgColors.ink))),
          ),
        ),
        Text('${stages.length}', style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.meta))),
      ]),
      const SizedBox(height: 4),
      Text(tr.tr('v2RpStagesSub'), style: MgType.small.copyWith(color: MgColors.meta)),
      const SizedBox(height: 12),
      for (var i = 0; i < stages.length; i++) _StageCard(n: i + 1, stage: stages[i], date: loc.formatMediumDate(stages[i].from.toLocal())),
    ]);
  }
}

class _StageCard extends StatelessWidget {
  final int n;
  final RideStage stage;
  final String date;
  const _StageCard({required this.n, required this.stage, required this.date});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final s = stage;
    final day = tr.trArgs('v2RpStageDay', {'n': n});
    final metas = <Widget>[
      RideMetaV2(MgIcons.ruler, rideKm(s.km), strong: true),
      if (s.movingSec > 0) RideMetaV2(MgIcons.ride, tr.trArgs('v2RpChipRiding', {'time': rideDuration((s.movingSec / 60).round())})),
      if (s.avgKmh != null) RideMetaV2(MgIcons.speed, rideSpeed(s.avgKmh)),
      if ((s.max ?? 0) > 0) RideMetaV2(MgIcons.gauge, rideSpeed(s.max)),
      if (s.gain > 0) RideMetaV2(MgIcons.up, '${s.gain} m'),
      if (s.pauseSec >= 60) RideMetaV2(MgIcons.pause, rideDuration((s.pauseSec / 60).round())),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MergeSemantics(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: MgColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MgColors.line),
            boxShadow: MgShadows.card,
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(color: MgColors.ink, shape: BoxShape.circle),
              child: Center(child: Text('$n', style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w900, color: MgColors.neon)))),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                MgWordFit(
                  minScale: 0.8,
                  child: Text('$day · $date', style: MgType.title.copyWith(color: MgColors.ink)),
                ),
                const SizedBox(height: 6),
                Wrap(spacing: 10, runSpacing: 4, children: metas),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
