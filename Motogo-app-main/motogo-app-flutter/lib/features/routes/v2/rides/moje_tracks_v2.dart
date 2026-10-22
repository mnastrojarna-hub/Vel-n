import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_shadows.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../ride_model.dart';

/// "Tvoje stopy" (V22 §2.4 Zazitky): every ride of the active filter on one
/// dark card — neon = S MotoGo, light = soukromá. Drawn from the rides'
/// own points already in the app (no tiles, no network, read-only). A tap
/// near a start dot opens that ride exactly like its card (`/ride/:id` with
/// the shown list for swiping). Hidden when no ride has a drawable track.
class MojeTracksV2 extends StatelessWidget {
  final List<UserRide> rides;
  final List<String> siblingIds;
  const MojeTracksV2({super.key, required this.rides, required this.siblingIds});

  /// At most ~160 points per ride — enough for a 200 px sketch.
  static List<LatLng> _thin(List<LatLng> pts) {
    if (pts.length <= 160) return pts;
    final step = pts.length / 160;
    return [for (var i = 0.0; i < pts.length; i += step) pts[i.floor()], pts.last];
  }

  @override
  Widget build(BuildContext context) {
    final tracks = <(UserRide, List<LatLng>)>[
      for (final r in rides)
        if (r.mapPoints.length >= 2) (r, _thin(r.mapPoints)),
    ];
    if (tracks.isEmpty) return const SizedBox.shrink();
    final tr = t(context);
    Widget legend(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 14, height: 3, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 6),
          Text(label, style: MgType.micro.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDarkLead)),
        ]);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: MgGradients.dark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MgColors.neonA(0.18)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(tr.tr('v2RideTracksTitle').toUpperCase(), style: MgType.eyebrow.copyWith(color: MgColors.neonText)),
          legend(MgColors.neon, tr.tr('v2RideFilterMg')),
          legend(MgColors.onDarkLead, tr.tr('v2RideFilterPriv')),
        ]),
        const SizedBox(height: 10),
        Semantics(
          label: tr.trArgs('v2RideTracksA11y', {'n': tracks.length}),
          child: SizedBox(
            height: 200,
            child: LayoutBuilder(builder: (context, c) {
              final size = Size(c.maxWidth, 200);
              final proj = _Projection(tracks.map((t) => t.$2), size);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  UserRide? best;
                  var bestD = 28.0; // finger-sized radius around a start dot
                  for (final t in tracks) {
                    final dist = (proj.map(t.$2.first) - d.localPosition).distance;
                    if (dist < bestD) {
                      bestD = dist;
                      best = t.$1;
                    }
                  }
                  if (best != null) context.push('/ride/${best.id}', extra: siblingIds);
                },
                child: CustomPaint(size: size, painter: _TracksPainter(tracks, proj)),
              );
            }),
          ),
        ),
        const SizedBox(height: 6),
        MgEnter(
          child: Text(tr.tr('v2RideTracksHint'), style: MgType.meta.copyWith(color: MgColors.onDarkMeta)),
        ),
      ]),
    );
  }
}

/// Lat/lng → card pixels (equirectangular with a latitude correction).
class _Projection {
  late final double _minLat, _maxLat, _minLng, _k, _scale, _ox, _oy;

  _Projection(Iterable<List<LatLng>> lines, Size size) {
    var minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;
    for (final l in lines) {
      for (final p in l) {
        minLat = math.min(minLat, p.latitude);
        maxLat = math.max(maxLat, p.latitude);
        minLng = math.min(minLng, p.longitude);
        maxLng = math.max(maxLng, p.longitude);
      }
    }
    _minLat = minLat;
    _maxLat = maxLat;
    _minLng = minLng;
    _k = math.cos((minLat + maxLat) / 2 * math.pi / 180).abs().clamp(0.2, 1.0);
    final w = math.max((maxLng - minLng) * _k, 1e-6);
    final h = math.max(maxLat - minLat, 1e-6);
    const pad = 16.0;
    _scale = math.min((size.width - 2 * pad) / w, (size.height - 2 * pad) / h);
    _ox = (size.width - w * _scale) / 2;
    _oy = (size.height - h * _scale) / 2;
  }

  Offset map(LatLng p) => Offset(_ox + (p.longitude - _minLng) * _k * _scale, _oy + (_maxLat - p.latitude) * _scale);

  double get spanLat => _maxLat - _minLat;
}

class _TracksPainter extends CustomPainter {
  final List<(UserRide, List<LatLng>)> tracks;
  final _Projection proj;
  _TracksPainter(this.tracks, this.proj);

  @override
  void paint(Canvas canvas, Size size) {
    Paint stroke(Color c, double w) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Private rides first, MotoGo rides on top (the brand line stays visible).
    final ordered = [
      ...tracks.where((t) => t.$1.bookingId == null),
      ...tracks.where((t) => t.$1.bookingId != null),
    ];
    for (final t in ordered) {
      final mg = t.$1.bookingId != null;
      final path = Path();
      final first = proj.map(t.$2.first);
      path.moveTo(first.dx, first.dy);
      for (final p in t.$2.skip(1)) {
        final o = proj.map(p);
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, stroke(MgColors.black(0.45), 5));
      canvas.drawPath(path, stroke(mg ? MgColors.neon : MgColors.onDarkLead, 2.4));
    }
    for (final t in ordered) {
      final s = proj.map(t.$2.first);
      canvas.drawCircle(s, 6, Paint()..color = MgColors.night);
      canvas.drawCircle(s, 4, Paint()..color = t.$1.bookingId != null ? MgColors.neon : MgColors.onDark);
    }
  }

  @override
  bool shouldRepaint(covariant _TracksPainter old) => old.tracks != tracks || old.proj.spanLat != proj.spanLat;
}
