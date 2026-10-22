import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_shadows.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_word_fit.dart';
import '../../ride_card.dart' show rideDateTime, rideDuration, rideKm, rideSpeed;
import '../../ride_model.dart';
import 'ride_track_sketch_v2.dart' show kRidePauseLink;

typedef _Stat = (String icon, String value, String label);

/// The one dark stats card (board `.stc`) with the sane stats of SPEC §9.3:
/// km · time in the saddle · Ø · max · climb · on the road without breaks ·
/// short stops · breaks (n× · time, only when any) · no signal (only when
/// any) · days (≥ 2) · rides (trip) · stops · photos, then start → end,
/// bike, description. Rides from the old server keep their old labels
/// (total time / stopped time — nights are still inside there).
class RideStatsCardV2 extends StatelessWidget {
  final UserRide ride;

  /// Trip: days over all its rides and the number of rides.
  final int? days;
  final int? rides;
  const RideStatsCardV2({super.key, required this.ride, this.days, this.rides});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final r = ride;
    final v2 = r.serverV2;
    final nDays = days ?? r.days;
    final pauses = r.pauseCount;
    final stats = <_Stat>[
      (MgIcons.ruler, rideKm(r.distanceKm), tr.tr('rideStatDistance')),
      (MgIcons.ride, r.movingSec > 0 ? rideDuration(r.movingMin) : '—', tr.tr('v2RpStatMoving')),
      (MgIcons.speed, rideSpeed(r.avgSpeedKmh ?? r.avgOverallKmh), tr.tr('rideStatAvg')),
      (MgIcons.gauge, rideSpeed(r.maxSpeedKmh), tr.tr('rideStatMax')),
      (MgIcons.up, r.elevationGainM > 0 ? '${r.elevationGainM} m' : '—', tr.tr('rideStatClimb')),
      (MgIcons.clock, r.totalMin > 0 ? rideDuration(r.totalMin) : '—', tr.tr(v2 ? 'v2RpStatOnRoad' : 'rideStatDuration')),
      (MgIcons.parking, r.idleSec > 0 ? rideDuration(r.idleMin) : '—', tr.tr(v2 ? 'v2RpStatIdle' : 'rideStatIdle')),
      if (r.pauseSec > 0)
        (
          MgIcons.pause,
          pauses > 0 ? tr.trArgs('v2RpStatPausesVal', {'n': pauses, 'time': rideDuration(r.pauseMin)}) : rideDuration(r.pauseMin),
          tr.tr('v2RpStatPauses'),
        ),
      if (nDays >= 2) (MgIcons.moon, '$nDays', tr.tr('v2RpStatDays')),
      if (rides != null) (MgIcons.list, '$rides', tr.tr('v2RpStatRides')),
      (MgIcons.pin, '${r.stops.length}', tr.tr('rideStatStops')),
      (MgIcons.camera, '${r.photoCount}', tr.tr('rideStatPhotos')),
    ];
    final gaps = <_Stat>[
      if (r.gapSec > 0) (MgIcons.signalOff, rideDuration(r.gapMin), tr.tr('rideStatGap')),
    ];
    final movedPause = r.segments.any((s) => s.gapBefore?.isPause == true && s.gapBefore!.km > kRideStillKm);
    final when = '${tr.tr('rideStatStart')} ${rideDateTime(r.startedAt)}'
        '${r.endedAt != null ? '  →  ${tr.tr('rideStatEnd')} ${rideDateTime(r.endedAt!)}' : ''}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const RadialGradient(
          center: Alignment.topRight,
          radius: 1.4,
          colors: [MgColors.glow, MgColors.panel, MgColors.night],
          stops: [0, 0.55, 1],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: MgShadows.dark,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (context, box) {
          // 3 columns when every label word fits a tile, else 2 (long
          // words — pl "przewyższenie", de compounds — never break).
          final cols = rideStatColumns(context, box.maxWidth, [for (final s in [...stats, ...gaps]) s.$3]);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _grid(stats, cols),
            if (gaps.isNotEmpty) ...[const SizedBox(height: 8), _grid(gaps, cols, warn: true)],
          ]);
        }),
        if (r.hasGaps) ...[
          const SizedBox(height: 8),
          _note(MgIcons.signalOff, tr.tr('v2RpGapNotice'), MgColors.warnBg, MgColors.warn),
        ],
        if (movedPause) ...[
          const SizedBox(height: 8),
          _note(null, tr.tr('v2RpPauseLegend'), MgColors.white(0.06), MgColors.onDarkLead),
        ],
        const SizedBox(height: 12),
        _line(MgIcons.clock, when),
        if ((r.motoName ?? '').isNotEmpty) ...[const SizedBox(height: 8), _line(MgIcons.bike, r.motoName!)],
        if ((r.description ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: MgColors.white(0.10)))),
            child: Text(r.description!, style: MgType.body.copyWith(color: MgColors.onDarkBody, height: 1.55)),
          ),
        ],
      ]),
    );
  }

  Widget _note(String? icon, String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null)
            MgIcon(icon, size: 18, color: fg)
          else
            // Čárkovaná modrošedá = přesun během pauzy (jako v náčrtu stopy).
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 5,
                    height: 2.5,
                    margin: const EdgeInsets.only(right: 2),
                    decoration: BoxDecoration(color: kRidePauseLink, borderRadius: BorderRadius.circular(2)),
                  ),
              ]),
            ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: MgType.small.copyWith(color: fg))),
        ]),
      );

  Widget _line(String icon, String text) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: MgIcon(icon, size: 16, color: MgColors.neon)),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDarkLead)))),
      ]);

  Widget _grid(List<_Stat> items, int cols, {bool warn = false}) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += cols) {
      if (i > 0) rows.add(const SizedBox(height: 8));
      rows.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var j = i; j < i + cols; j++) ...[
            if (j > i) const SizedBox(width: 8),
            Expanded(child: j < items.length ? _tile(items[j], warn) : const SizedBox()),
          ],
        ]),
      ));
    }
    return Column(children: rows);
  }

  Widget _tile(_Stat s, bool warn) => MergeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 12, 8, 12),
          decoration: BoxDecoration(
            color: warn ? MgColors.warnDarkBg : MgColors.white(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: warn ? MgColors.warnDark.withValues(alpha: 0.28) : MgColors.neonA(0.12)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            MgIcon(s.$1, size: 18, color: warn ? MgColors.warnDark : MgColors.neon),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(s.$2, maxLines: 1, style: MgType.tab(MgType.title.copyWith(color: MgColors.onDark))),
            ),
            const SizedBox(height: 2),
            // r1: popisek na 2 řádky, dlouhé slovo („Höchsttempo",
            // „Unterbrechungen", „hoogtemeters") se zmenší, nerozdělí.
            MgWordFit(
              minScale: 0.7,
              child: Text(s.$3, maxLines: 2, style: MgType.meta.copyWith(color: MgColors.onDarkSecondary)),
            ),
          ]),
        ),
      );
}

/// Columns of a stat grid: 3 when the longest label word fits a tile
/// (tile padding 18 + border), else 2.
int rideStatColumns(BuildContext context, double width, List<String> labels, {double gap = 8, double inset = 20}) {
  final style = DefaultTextStyle.of(context).style.merge(MgType.meta);
  final scaler = MediaQuery.textScalerOf(context);
  var longest = 0.0;
  for (final l in labels) {
    for (final w in l.split(RegExp(r'\s+'))) {
      final tp = TextPainter(text: TextSpan(text: w, style: style), textDirection: Directionality.of(context), textScaler: scaler)
        ..layout();
      if (tp.width > longest) longest = tp.width;
      tp.dispose();
    }
  }
  final inner3 = (width - 2 * gap) / 3 - inset;
  return longest <= inner3 ? 3 : 2;
}
