import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';
import 'map_fit.dart';
import 'ride_model.dart';
import 'routes_provider.dart' show mapyApiKey;

/// Mapa projeté jízdy — stopa GPS + značky start / cíl / zastávky.
/// Používá se jako náhled v kartě jízdy (neinteraktivní) i jako velká mapa
/// v detailu jízdy (interaktivní, klepnutí do mapy přidá zastávku).
class RideTrackMap extends StatefulWidget {
  final List<LatLng> track;

  /// Stopa rozdělená na souvislé úseky (viz `UserRide.segments`). Když je
  /// prázdná, kreslí se `track` jako jedna čára — to je správně u ručně
  /// poskládaných jízd, které žádné časy nemají.
  final List<RideSegment> segments;
  final List<RidePoint> points;
  final bool interactive;
  final int? activePoint; // zvýrazněná zastávka (index v `points`)
  final void Function(int index)? onPointTap;
  final void Function(LatLng point)? onMapTap;

  const RideTrackMap({
    super.key,
    required this.track,
    this.segments = const [],
    this.points = const [],
    this.interactive = false,
    this.activePoint,
    this.onPointTap,
    this.onMapTap,
  });

  @override
  State<RideTrackMap> createState() => _RideTrackMapState();
}

class _RideTrackMapState extends State<RideTrackMap> {
  final MapController _ctrl = MapController();
  bool _ready = false;

  List<LatLng> get _all => [
        ...widget.track,
        ...widget.points.map((p) => p.latLng),
      ];

  /// Čáry ke kreslení — souvislé úseky, jinak celá stopa vcelku.
  List<List<LatLng>> get _lines {
    if (widget.segments.isEmpty) {
      return widget.track.length >= 2 ? [widget.track] : const [];
    }
    return [
      for (final s in widget.segments)
        if (s.points.length >= 2) s.points,
    ];
  }

  /// Mezery mezi úseky (tečkovaná spojnice).
  List<RideGap> get _gaps => [
        for (final s in widget.segments)
          if (s.gapBefore != null) s.gapBefore!,
      ];

  /// Body start / cíl. Vznikají až ukončením jízdy, takže u PRÁVĚ NAHRÁVANÉ
  /// jízdy je `points` prázdné a mapa by neměla ani jednu značku — jezdec by
  /// nepoznal, kde vyjel. Dopočítáme je proto z krajů stopy.
  ({LatLng? start, LatLng? end}) get _ends {
    final hasStart = widget.points.any((p) => p.isStart);
    final hasEnd = widget.points.any((p) => p.isEnd);
    if (hasStart && hasEnd) return (start: null, end: null);
    final line = _lines;
    if (line.isEmpty) return (start: null, end: null);
    final first = line.first.first;
    final last = line.last.last;
    return (
      start: hasStart ? null : first,
      end: (hasEnd || last == first) ? null : last,
    );
  }

  LatLng get _center {
    final pts = _all;
    if (pts.isEmpty) return const LatLng(49.3464, 15.2119); // Mezná fallback
    double lat = 0, lng = 0;
    for (final p in pts) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / pts.length, lng / pts.length);
  }

  void _fit() {
    final pts = _all;
    if (pts.length < 2) return;
    fitMapSafe(_ctrl, pts, padding: const EdgeInsets.all(28));
  }

  @override
  void didUpdateWidget(covariant RideTrackMap old) {
    super.didUpdateWidget(old);
    if (_ready && old.points.length != widget.points.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
    }
  }

  @override
  Widget build(BuildContext context) {
    final stops = <({RidePoint p, int index})>[];
    for (var i = 0; i < widget.points.length; i++) {
      if (widget.points[i].isStop) stops.add((p: widget.points[i], index: i));
    }
    final start = widget.points.where((p) => p.isStart).toList();
    final end = widget.points.where((p) => p.isEnd).toList();

    return FlutterMap(
      mapController: _ctrl,
      options: MapOptions(
        initialCenter: _center,
        initialZoom: 11,
        interactionOptions: InteractionOptions(
          flags: widget.interactive
              ? (InteractiveFlag.pinchZoom |
                  InteractiveFlag.drag |
                  InteractiveFlag.doubleTapZoom)
              : InteractiveFlag.none,
        ),
        onTap: widget.onMapTap == null
            ? null
            : (_, p) => widget.onMapTap!(p),
        onMapReady: () {
          _ready = true;
          _fit();
        },
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://api.mapy.cz/v1/maptiles/outdoor/256/{z}/{x}/{y}?apikey=$mapyApiKey',
          userAgentPackageName: 'com.motogo24.app',
          maxZoom: 19,
        ),
        // Souvislé úseky = plná zelená čára. Mezery (appka na pozadí / bez
        // signálu) = šedá tečkovaná spojnice: tudy jezdec MOŽNÁ jel, ale
        // nevíme to, takže to nekreslíme jako projetou trasu.
        if (_lines.isNotEmpty)
          PolylineLayer(
            polylines: [
              for (final seg in _lines)
                Polyline(
                  points: seg,
                  strokeWidth: 7,
                  color: MotoGoColors.dark.withValues(alpha: 0.35),
                ),
              for (final seg in _lines)
                Polyline(
                  points: seg,
                  strokeWidth: 4,
                  color: MotoGoColors.greenDark,
                ),
              for (final gap in _gaps)
                Polyline(
                  points: [gap.from, gap.to],
                  strokeWidth: 3,
                  color: MotoGoColors.g400,
                  isDotted: true,
                ),
            ],
          ),
        MarkerLayer(
          markers: [
            // Dopočtené kraje stopy (běžící jízda ještě nemá body start/cíl).
            if (_ends.start != null)
              Marker(
                point: _ends.start!,
                width: 30,
                height: 30,
                child: _pin('🏁', MotoGoColors.green),
              ),
            if (_ends.end != null)
              Marker(
                point: _ends.end!,
                width: 30,
                height: 30,
                child: _pin('📍', MotoGoColors.dark, fg: Colors.white),
              ),
            for (final s in start)
              Marker(
                point: s.latLng,
                width: 30,
                height: 30,
                child: _pin('🏁', MotoGoColors.green),
              ),
            for (final e in end)
              Marker(
                point: e.latLng,
                width: 30,
                height: 30,
                child: _pin('🏆', MotoGoColors.dark, fg: Colors.white),
              ),
            for (var i = 0; i < stops.length; i++)
              Marker(
                point: stops[i].p.latLng,
                width: 30,
                height: 30,
                child: GestureDetector(
                  onTap: widget.onPointTap == null
                      ? null
                      : () => widget.onPointTap!(stops[i].index),
                  child: _numPin(i + 1, widget.activePoint == stops[i].index),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _pin(String emoji, Color bg, {Color fg = MotoGoColors.black}) => Container(
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: MotoGoShadows.cardSmall,
        ),
        alignment: Alignment.center,
        child: Text(emoji, style: TextStyle(fontSize: 13, color: fg)),
      );

  Widget _numPin(int n, bool active) => Container(
        decoration: BoxDecoration(
          color: active ? MotoGoColors.green : MotoGoColors.greenDarker,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: MotoGoShadows.cardSmall,
        ),
        alignment: Alignment.center,
        child: Text(
          '$n',
          style: TextStyle(
            fontSize: 12,
            fontWeight: MotoGoTypo.w900,
            color: active ? MotoGoColors.black : Colors.white,
            decoration: TextDecoration.none,
          ),
        ),
      );
}
