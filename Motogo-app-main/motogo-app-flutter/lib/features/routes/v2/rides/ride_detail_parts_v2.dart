import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/rank/rank_hero.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_shadows.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_back_v2.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../ride_card.dart' show rideDate, rideDateTime, rideDuration, rideKm, rideSpeed;
import '../../ride_model.dart';
import 'ride_track_sketch_v2.dart';

/// Dark ride header (board `.rdh`): back, name (tap = the old "Upravit
/// jízdu" dialog), share, delete; date · bike; tags.
class RideDetailHeaderV2 extends StatelessWidget {
  final UserRide ride;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  const RideDetailHeaderV2({
    super.key,
    required this.ride,
    required this.onBack,
    required this.onEdit,
    required this.onShare,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final name = ride.name.isNotEmpty ? ride.name : tr.tr('rideUntitled');
    final sub = [rideDate(ride.startedAt), if ((ride.motoName ?? '').isNotEmpty) ride.motoName!].join(' · ');
    final mg = ride.bookingId != null;
    return MgRankHero(
      ambientKey: 'ride',
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          MgV2Back(onTap: onBack, style: MgBackStyle.dark),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              button: true,
              label: '$name, ${tr.tr('v2RideEditA11y')}',
              excludeSemantics: true,
              child: MgPress(
                scale: 0.98,
                onTap: onEdit,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Flexible(
                        child: Text(name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: MgType.h3.copyWith(color: MgColors.onDark)),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(left: 6, top: 4),
                        child: MgIcon(MgIcons.edit, size: 16, color: MgColors.onDarkMeta),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
          MgIconButton(icon: MgIcons.share, semanticLabel: tr.tr('rideShareTitle'), onTap: onShare),
          const SizedBox(width: 4),
          MgIconButton(icon: MgIcons.trash, semanticLabel: tr.tr('v2RideDelete'), iconColor: MgColors.errDark, onTap: onDelete),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(52, 2, 0, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: MgType.tab(MgType.small.copyWith(color: MgColors.onDarkLead))),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (ride.isRecording) RideBadgeV2(kind: RideBadgeKind.live, label: tr.tr('rideRecording'), dark: true),
              RideBadgeV2(
                kind: mg ? RideBadgeKind.motogo : RideBadgeKind.private,
                label: tr.tr(mg ? 'v2RideFilterMg' : 'v2RideTagPriv'),
                dark: true,
              ),
              if (ride.isPublic) RideBadgeV2(kind: RideBadgeKind.shared, label: tr.tr('rideShared'), dark: true),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// The one dark stats card (board `.stc`): the old 3 × 3 facts, the gap row
/// + `rideGapNotice` when the track has holes, start → end, bike and the
/// description.
class RideStatsCardV2 extends StatelessWidget {
  final UserRide ride;
  const RideStatsCardV2({super.key, required this.ride});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final r = ride;
    final stats = <(String, String, String)>[
      (MgIcons.ruler, rideKm(r.distanceKm), tr.tr('rideStatDistance')),
      (MgIcons.clock, rideDuration(r.totalMin), tr.tr('rideStatDuration')),
      (MgIcons.ride, r.movingSec > 0 ? rideDuration(r.movingMin) : '—', tr.tr('rideStatMoving')),
      (MgIcons.pause, r.idleSec > 0 ? rideDuration(r.idleMin) : '—', tr.tr('rideStatIdle')),
      (MgIcons.speed, rideSpeed(r.avgSpeedKmh ?? r.avgOverallKmh), tr.tr('rideStatAvg')),
      (MgIcons.gauge, rideSpeed(r.maxSpeedKmh), tr.tr('rideStatMax')),
      (MgIcons.up, r.elevationGainM > 0 ? '${r.elevationGainM} m' : '—', tr.tr('rideStatClimb')),
      (MgIcons.pin, '${r.stops.length}', tr.tr('rideStatStops')),
      (MgIcons.camera, '${r.photoCount}', tr.tr('rideStatPhotos')),
    ];
    final gaps = r.gapSec <= 0
        ? const <(String, String, String)>[]
        : [
            (MgIcons.signalOff, rideDuration(r.gapMin), tr.tr('rideStatGap')),
            (MgIcons.satellite, '${r.track.length}', tr.tr('rideStatPoints')),
            (MgIcons.cut, '${r.segments.where((s) => s.gapBefore != null).length}', tr.tr('rideStatBreaks')),
          ];
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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: MgColors.warnBg, borderRadius: BorderRadius.circular(12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const MgIcon(MgIcons.signalOff, size: 18, color: MgColors.warn),
              const SizedBox(width: 8),
              Expanded(child: Text(tr.tr('rideGapNotice'), style: MgType.small.copyWith(color: MgColors.warn))),
            ]),
          ),
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

  Widget _line(String icon, String text) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: MgIcon(icon, size: 16, color: MgColors.neon)),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDarkLead)))),
      ]);

  Widget _grid(List<(String, String, String)> items, int cols, {bool warn = false}) {
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

  Widget _tile((String, String, String) s, bool warn) => MergeSemantics(
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
            Text(s.$3, style: MgType.meta.copyWith(color: MgColors.onDarkSecondary)),
          ]),
        ),
      );
}

/// "Sdílet ostatním" (board `.vis`): the EXISTING visibility switch
/// (disabled while saving, as before).
class RideVisibilityCardV2 extends StatelessWidget {
  final bool isPublic;
  final bool busy;
  final ValueChanged<bool> onChanged;
  const RideVisibilityCardV2({super.key, required this.isPublic, required this.busy, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: MgColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MgColors.line),
        boxShadow: MgShadows.card,
      ),
      child: MergeSemantics(
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isPublic ? MgColors.tintOk : MgColors.well,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: MgIcon(isPublic ? MgIcons.globe : MgIcons.lock, size: 20, color: isPublic ? MgColors.onTintOk : MgColors.meta)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr.tr('rideVisibility'), style: MgType.title.copyWith(color: MgColors.ink)),
              Text(tr.tr(isPublic ? 'rideVisibilityOn' : 'rideVisibilityOff'), style: MgType.small.copyWith(color: MgColors.meta)),
            ]),
          ),
          Switch(
            value: isPublic,
            onChanged: busy ? null : onChanged,
            activeThumbColor: MgColors.onNeon,
            activeTrackColor: MgColors.neon,
            inactiveThumbColor: MgColors.meta,
            inactiveTrackColor: MgColors.well,
            trackOutlineColor: const WidgetStatePropertyAll(MgColors.lineInput),
          ),
        ]),
      ),
    );
  }
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
