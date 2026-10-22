import 'package:flutter/material.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/theme.dart';
import 'ride_card.dart' show rideDateTime, rideDuration, rideKm, rideSpeed;
import 'ride_live_stats.dart';
import 'ride_map.dart' show rideHasMovedPause;
import 'ride_model.dart';

/// Statistiky jízdy / cesty (SPEC §9.3): km · v sedle · Ø · max ·
/// nastoupáno · na cestě (bez pauz) · zastávky · pauzy · bez signálu · dny ·
/// zastávky · fotky + start → konec. Nesmyslné hodnoty se nevymýšlejí:
/// prázdné pole „—", nulové pauzy / výpadky / jednodenní jízda se neukážou.
/// Čas „na cestě" je u nového serveru BEZ pauz (noci, oběd); u jízdy ze
/// starého serveru je to celkový čas (proto jiný popisek).
class RideStatsGrid extends StatelessWidget {
  const RideStatsGrid({super.key, required this.ride, this.showText = true});

  final UserRide ride;

  /// Motorka a popis jízdy (u cesty se nezobrazují — patří jednotlivým jízdám).
  final bool showText;

  /// Dlouhé časy (vícedenní cesta) jako „2 d 3 h", krátké „1 h 20 min".
  static String _long(int min) => rideLiveDuration(min * 60);

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final r = ride;
    final cells = <(String, String, String)>[
      ('📏', rideKm(r.distanceKm), tr.tr('rideStatDistance')),
      ('🏍️', r.movingSec > 0 ? rideDuration(r.movingMin) : '—', tr.tr('rideStatMoving')),
      ('📊', rideSpeed(r.avgSpeedKmh ?? r.avgOverallKmh), tr.tr('rideStatAvg')),
      ('🚀', rideSpeed(r.maxSpeedKmh), tr.tr('rideStatMax')),
      ('⛰️', r.elevationGainM > 0 ? '${r.elevationGainM} m' : '—', tr.tr('rideStatClimb')),
      ('⏱️', r.totalMin > 0 ? _long(r.totalMin) : '—',
          tr.tr(r.serverV2 ? 'rpStatOnRoad' : 'rideStatDuration')),
      ('⏸️', r.idleSec >= 60 ? rideDuration(r.idleMin) : '—', tr.tr('rideStatIdle')),
      if (r.pauseSec >= 60)
        (
          '🛌',
          r.pauseCount > 0
              ? tr.trArgs('rpStatPausesVal', {'n': r.pauseCount, 'time': _long(r.pauseMin)})
              : _long(r.pauseMin),
          tr.tr('rpStatPauses')
        ),
      if (r.gapSec > 0) ('📵', rideDuration(r.gapMin), tr.tr('rideStatGap')),
      if (r.days >= 2) ('📅', '${r.days}', tr.tr('rpStatDays')),
      ('📍', '${r.stops.length}', tr.tr('rideStatStops')),
      ('📷', '${r.photoCount}', tr.tr('rideStatPhotos')),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoRadius.card),
        boxShadow: MotoGoShadows.cardSmall,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth - 16) / 3;
          return Wrap(spacing: 8, runSpacing: 12, children: [
            for (final s in cells) SizedBox(width: w, child: _stat(s.$1, s.$2, s.$3)),
          ]);
        }),
        // Poctivé vysvětlení děravé stopy (jen skutečné výpadky signálu —
        // pauzy a noci sem nepatří).
        if (r.hasGaps) ...[const SizedBox(height: 12), _note('📵 ${tr.tr('rpGapNotice')}')],
        if (rideHasMovedPause(r.segments)) ...[
          const SizedBox(height: 8),
          _note('〰️ ${tr.tr('rpPauseLegend')}', bg: MotoGoColors.g100, border: MotoGoColors.g200, fg: MotoGoColors.g600),
        ],
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: MotoGoColors.g100, borderRadius: BorderRadius.circular(MotoGoRadius.xl)),
          child: Text(
            '🕘 ${tr.tr('rideStatStart')} ${rideDateTime(r.startedAt)}'
            '${r.endedAt != null ? '   →   ${tr.tr('rideStatEnd')} ${rideDateTime(r.endedAt!)}' : ''}',
            style: _meta,
          ),
        ),
        if (showText && (r.motoName ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('🏍️ ${r.motoName}', style: _meta.copyWith(fontSize: MotoGoTypo.sizeBase)),
        ],
        if (showText && (r.description ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(r.description!,
              style: _meta.copyWith(fontSize: MotoGoTypo.sizeBase, fontWeight: MotoGoTypo.w600, height: 1.45)),
        ],
      ]),
    );
  }

  static const _meta = TextStyle(
      fontSize: MotoGoTypo.sizeMd,
      fontWeight: MotoGoTypo.w700,
      color: MotoGoColors.g600,
      decoration: TextDecoration.none);

  Widget _note(String text, {Color? bg, Color? border, Color? fg}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg ?? MotoGoColors.amberBg,
          border: Border.all(color: border ?? MotoGoColors.amberBorder),
          borderRadius: BorderRadius.circular(MotoGoRadius.xl),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: MotoGoTypo.sizeSm,
                fontWeight: MotoGoTypo.w700,
                color: fg ?? MotoGoColors.amber,
                height: 1.35,
                decoration: TextDecoration.none)),
      );

  Widget _stat(String emoji, String value, String label) => Semantics(
        label: '$label: $value',
        excludeSemantics: true,
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                maxLines: 1,
                style: const TextStyle(
                    fontSize: MotoGoTypo.sizeXl,
                    fontWeight: MotoGoTypo.w900,
                    color: MotoGoColors.black,
                    decoration: TextDecoration.none)),
          ),
          Text(label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: MotoGoTypo.sizeSm,
                  fontWeight: MotoGoTypo.w700,
                  color: MotoGoColors.g400,
                  height: 1.2,
                  decoration: TextDecoration.none)),
        ]),
      );
}
