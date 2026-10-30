import 'package:flutter/material.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/theme.dart';
import 'ride_card.dart' show rideDuration, rideKm;
import 'ride_model.dart';
import 'ride_trip.dart';

/// Etapy (dny) vícedenní jízdy / cesty (SPEC §9.3): „Den 1 · Po 6. 10. ·
/// 312 km · 5 h 10 min v sedle · Ø 61 km/h · max 118 km/h · ⛰ 1 240 m".
/// Zobrazí se, až když jsou aspoň 2 etapy, ve kterých se opravdu jelo.

/// Etapy, ve kterých se něco ujelo (prázdné „etapy" ze stání se nevypisují).
List<RideStage> rideDisplayStages(Iterable<RideStage> stages) =>
    [for (final s in stages) if (s.movingSec >= 60 || s.km >= 0.1) s];

/// Etapy cesty: etapy jednotlivých jízd, a kde server etapy nemá (starší
/// jízda), je etapou celá jízda.
List<RideStage> rideTripStages(RideTrip trip) => [
      for (final r in trip.rides)
        if (r.stages.isNotEmpty)
          ...r.stages
        else
          RideStage(
            from: r.startedAt,
            to: r.endedAt ?? r.lastFixAt ?? r.startedAt,
            km: r.distanceKm,
            movingSec: r.movingSec,
            gapSec: r.gapSec,
            pauseSec: r.pauseSec,
            gain: r.elevationGainM,
            max: r.maxSpeedKmh,
          ),
    ];

class RideStageList extends StatelessWidget {
  const RideStageList({super.key, required this.stages});

  final List<RideStage> stages;

  @override
  Widget build(BuildContext context) {
    final list = rideDisplayStages(stages);
    if (list.length < 2) return const SizedBox.shrink();
    final tr = t(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoRadius.card),
        boxShadow: MotoGoShadows.cardSmall,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(
          header: true,
          child: Text('🗓️ ${tr.tr('rpStages')}',
              style: const TextStyle(
                  fontSize: MotoGoTypo.sizeXl,
                  fontWeight: MotoGoTypo.w900,
                  color: MotoGoColors.black,
                  decoration: TextDecoration.none)),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < list.length; i++) _row(tr, i + 1, list[i], last: i == list.length - 1),
      ]),
    );
  }

  Widget _row(AppTranslations tr, int n, RideStage s, {required bool last}) {
    final d = s.from.toLocal();
    final metas = <String>[
      rideKm(s.km),
      if (s.movingSec >= 60) tr.trArgs('rpSaddle', {'time': rideDuration((s.movingSec / 60).round())}),
      if (s.avgKmh != null) 'Ø ${s.avgKmh!.toStringAsFixed(0)} km/h',
      if (s.max != null && s.max! > 0) tr.trArgs('rpMaxShort', {'v': '${s.max!.toStringAsFixed(0)} km/h'}),
      if (s.gain > 0) '⛰ ${s.gain} m',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: MotoGoColors.g100)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(
                text: tr.trArgs('rpStageDay', {'n': n}),
                style: const TextStyle(fontWeight: MotoGoTypo.w900, color: MotoGoColors.black)),
            TextSpan(text: '  ${tr.tr('rpWd${d.weekday}')} ${d.day}. ${d.month}.'),
          ]),
          style: const TextStyle(
              fontSize: MotoGoTypo.sizeLg,
              fontWeight: MotoGoTypo.w700,
              color: MotoGoColors.g500,
              decoration: TextDecoration.none),
        ),
        const SizedBox(height: 2),
        Text(metas.join(' · '),
            style: const TextStyle(
                fontSize: MotoGoTypo.sizeMd,
                fontWeight: MotoGoTypo.w700,
                color: MotoGoColors.g600,
                height: 1.35,
                decoration: TextDecoration.none)),
      ]),
    );
  }
}
