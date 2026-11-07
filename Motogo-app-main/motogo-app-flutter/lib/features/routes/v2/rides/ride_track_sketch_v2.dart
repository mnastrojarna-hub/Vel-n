import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_word_fit.dart';
import '../../ride_model.dart';

/// Blue-grey of a move during a pause (ferry, trailer — SPEC §9.1).
const Color kRidePauseLink = Color(0xFF5F86A0);

/// Track thumbnail of a ride (board Zazitky `.rd-tk`): the recorded line
/// drawn from the ride's own points — no map tiles, no network. Gaps (no
/// GPS while riding) are dotted grey; a pause where the bike moved (> 300
/// m: ferry, trailer) is a dashed blue-grey line; a pause in place (night,
/// lunch) draws nothing. Start = green dot, end = ink dot. A ride without
/// at least two points shows the bike glyph instead.
class RideTrackSketch extends StatelessWidget {
  final List<List<LatLng>> lines;

  /// Breaks to draw: (from, to, moved during a pause = dashed blue-grey).
  final List<(LatLng, LatLng, bool)> gaps;
  final double size;
  final bool dark;
  final String fallbackIcon;

  RideTrackSketch({super.key, required UserRide ride, this.size = 88, this.dark = false})
      : lines = _lines(ride),
        gaps = _gaps(ride),
        fallbackIcon = MgIcons.bike;

  /// A plain line (saved route waypoints).
  RideTrackSketch.line(List<LatLng> points, {super.key, this.size = 64, this.dark = true})
      : lines = points.length >= 2 ? [points] : const [],
        gaps = const [],
        fallbackIcon = MgIcons.route;

  @override
  Widget build(BuildContext context) {
    final bg = dark ? MgColors.panel : MgColors.tintFeatureA;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: dark ? MgColors.neonA(0.16) : MgColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: lines.isEmpty
            ? Center(child: MgIcon(fallbackIcon, size: size * 0.36, color: dark ? MgColors.neon : MgColors.routeGreen))
            : CustomPaint(painter: _SketchPainter(lines, gaps, dark: dark)),
      ),
    );
  }

  static List<List<LatLng>> _lines(UserRide r) {
    if (r.segments.isNotEmpty) {
      final out = [for (final s in r.segments) if (s.points.length >= 2) s.points];
      if (out.isNotEmpty) return out;
    }
    final pts = r.mapPoints;
    return pts.length >= 2 ? [pts] : const [];
  }

  static List<(LatLng, LatLng, bool)> _gaps(UserRide r) => [
        for (final s in r.segments)
          if (s.gapBefore case final g?)
            if (!g.isPause || g.km > kRideStillKm) (g.from, g.to, g.isPause),
      ];
}

class _SketchPainter extends CustomPainter {
  final List<List<LatLng>> lines;
  final List<(LatLng, LatLng, bool)> gaps;
  final bool dark;
  _SketchPainter(this.lines, this.gaps, {required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    var minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;
    for (final l in lines) {
      for (final p in l) {
        minLat = math.min(minLat, p.latitude);
        maxLat = math.max(maxLat, p.latitude);
        minLng = math.min(minLng, p.longitude);
        maxLng = math.max(maxLng, p.longitude);
      }
    }
    final k = math.cos((minLat + maxLat) / 2 * math.pi / 180).abs().clamp(0.2, 1.0);
    final w = math.max((maxLng - minLng) * k, 1e-6);
    final h = math.max(maxLat - minLat, 1e-6);
    const pad = 12.0;
    final scale = math.min((size.width - 2 * pad) / w, (size.height - 2 * pad) / h);
    final ox = (size.width - w * scale) / 2;
    final oy = (size.height - h * scale) / 2;
    Offset map(LatLng p) => Offset(ox + (p.longitude - minLng) * k * scale, oy + (maxLat - p.latitude) * scale);

    final line = dark ? MgColors.neon : MgColors.routeGreen;
    final under = Paint()
      ..color = dark ? MgColors.black(0.5) : MgColors.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final paint = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final l in lines) {
      final path = Path()..moveTo(map(l.first).dx, map(l.first).dy);
      for (final p in l.skip(1)) {
        final o = map(p);
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, under);
      canvas.drawPath(path, paint);
    }
    final dot = Paint()..color = dark ? MgColors.onDarkMeta : MgColors.meta;
    final dash = Paint()
      ..color = kRidePauseLink
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final g in gaps) {
      final a = map(g.$1), b = map(g.$2);
      final d = (b - a).distance;
      if (d < 1) continue;
      if (g.$3) {
        // Přesun během pauzy: čárkovaně (5 + 4 px).
        for (var x = 0.0; x < d; x += 9) {
          canvas.drawLine(Offset.lerp(a, b, x / d)!, Offset.lerp(a, b, math.min(x + 5, d) / d)!, dash);
        }
        continue;
      }
      final n = (d / 6).floor();
      for (var i = 0; i <= n; i++) {
        canvas.drawCircle(Offset.lerp(a, b, i / math.max(n, 1))!, 1.2, dot);
      }
    }
    final start = map(lines.first.first), end = map(lines.last.last);
    final ring = Paint()..color = dark ? MgColors.panel : MgColors.surface;
    canvas.drawCircle(end, 5, ring);
    canvas.drawCircle(end, 3.4, Paint()..color = dark ? MgColors.onDark : MgColors.ink);
    canvas.drawCircle(start, 5, ring);
    canvas.drawCircle(start, 3.4, Paint()..color = MgColors.neonLo);
  }

  @override
  bool shouldRepaint(covariant _SketchPainter old) => old.lines != lines || old.gaps != gaps || old.dark != dark;
}

/// Small 20 px tag of a ride (S MotoGo / Soukromá / Sdíleno / Nahrávám /
/// Pozastaveno / "3 dny" / CESTA).
enum RideBadgeKind { motogo, private, shared, live, paused, days, trip }

class RideBadgeV2 extends StatelessWidget {
  final RideBadgeKind kind;
  final String label;
  final bool dark;
  const RideBadgeV2({super.key, required this.kind, required this.label, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (kind) {
      RideBadgeKind.motogo => (dark ? MgColors.neonA(0.14) : MgColors.panel, MgColors.neon),
      RideBadgeKind.private => (dark ? MgColors.white(0.10) : MgColors.well, dark ? MgColors.onDarkLead : MgColors.body2),
      RideBadgeKind.shared => (dark ? MgColors.white(0.10) : MgColors.tintOk, dark ? MgColors.onDarkLead : MgColors.onTintOk),
      RideBadgeKind.live => (MgColors.errBg, MgColors.err),
      RideBadgeKind.paused => (dark ? MgColors.white(0.14) : MgColors.well, dark ? MgColors.onDark : MgColors.ink),
      RideBadgeKind.days => (dark ? MgColors.white(0.10) : MgColors.tintFeatureA, dark ? MgColors.onDarkLead : MgColors.link),
      RideBadgeKind.trip => (MgColors.ink, MgColors.neon),
    };
    final icon = switch (kind) {
      RideBadgeKind.shared => MgIcons.globe,
      RideBadgeKind.paused => MgIcons.pause,
      RideBadgeKind.days => MgIcons.moon,
      RideBadgeKind.trip => MgIcons.route,
      _ => null,
    };
    return Container(
      constraints: const BoxConstraints(minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: (kind == RideBadgeKind.private || kind == RideBadgeKind.paused) && !dark ? Border.all(color: MgColors.line) : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (kind == RideBadgeKind.live) ...[
          Container(width: 7, height: 7, decoration: const BoxDecoration(color: MgColors.sosDot, shape: BoxShape.circle)),
          const SizedBox(width: 5),
        ],
        if (icon != null) ...[
          MgIcon(icon, size: 12, color: fg, stroke: kind == RideBadgeKind.paused ? 2.8 : 2),
          const SizedBox(width: 4),
        ],
        // Štítek celý (zmenší se), nikdy „TRAVESÍA · 3 d…".
        Flexible(
          child: MgWordFit(
            minScale: 0.7,
            child: Text(label, maxLines: 1, softWrap: false, style: MgType.micro.copyWith(fontWeight: FontWeight.w800, color: fg, height: 1.2)),
          ),
        ),
      ]),
    );
  }
}

/// One "icon + value" meta of a ride / route line.
class RideMetaV2 extends StatelessWidget {
  final String icon;
  final String text;
  final bool strong;
  final bool dark;
  const RideMetaV2(this.icon, this.text, {super.key, this.strong = false, this.dark = false});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        MgIcon(icon, size: 15, color: dark ? MgColors.neon : MgColors.routeGreen),
        const SizedBox(width: 4),
        // Úzká karta + velké písmo: hodnota se zalomí, nikdy nepřeteče.
        Flexible(
          child: Text(text,
              style: MgType.tab(MgType.small.copyWith(
                  fontWeight: strong ? FontWeight.w800 : FontWeight.w700,
                  color: dark ? MgColors.onDarkBody : (strong ? MgColors.ink : MgColors.body2)))),
        ),
      ]);
}
