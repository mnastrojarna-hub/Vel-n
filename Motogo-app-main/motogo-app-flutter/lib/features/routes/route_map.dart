import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';
import 'routes_provider.dart' show mapyApiKey;

/// Interaktivní náhled trasy v Mapy.com dlaždicích — polyline + start pobočky
/// + markery bodů zájmu. Sám se přizpůsobí (fit) na celou trasu.
class RouteMapView extends StatefulWidget {
  final List<LatLng> geometry;
  final LatLng? start; // pobočka
  final List<({LatLng point, int index})> pois;
  final bool interactive;
  final int? activePoi; // zvýrazněný POI (z karuselu detailu)
  final void Function(int index)? onPoiTap; // klik na bod zájmu na mapě

  const RouteMapView({
    super.key,
    required this.geometry,
    this.start,
    this.pois = const [],
    this.interactive = true,
    this.activePoi,
    this.onPoiTap,
  });

  @override
  State<RouteMapView> createState() => _RouteMapViewState();
}

class _RouteMapViewState extends State<RouteMapView> {
  final MapController _ctrl = MapController();
  bool _ready = false;

  List<LatLng> get _allPoints => [
        ...widget.geometry,
        if (widget.start != null) widget.start!,
        ...widget.pois.map((p) => p.point),
      ];

  LatLng get _center {
    final pts = _allPoints;
    if (pts.isEmpty) return const LatLng(49.3464, 15.2119); // Mezná fallback
    double lat = 0, lng = 0;
    for (final p in pts) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / pts.length, lng / pts.length);
  }

  void _fit() {
    final pts = _allPoints;
    if (pts.length < 2) return;
    try {
      _ctrl.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(pts),
          padding: const EdgeInsets.all(36),
        ),
      );
    } catch (_) {}
  }

  @override
  void didUpdateWidget(RouteMapView old) {
    super.didUpdateWidget(old);
    // Při změně zvýrazněného POI plynule odcentruj.
    if (_ready &&
        widget.activePoi != old.activePoi &&
        widget.activePoi != null &&
        widget.activePoi! >= 0 &&
        widget.activePoi! < widget.pois.length) {
      final p = widget.pois[widget.activePoi!].point;
      _ctrl.move(p, 13.5);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: _ctrl,
      options: MapOptions(
        initialCenter: _center,
        initialZoom: 11,
        interactionOptions: InteractionOptions(
          flags: widget.interactive ? InteractiveFlag.all : InteractiveFlag.none,
        ),
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
        if (widget.geometry.length >= 2)
          PolylineLayer(
            polylines: [
              // Tmavý podklad pro kontrast + zelená trasa navrch.
              Polyline(
                points: widget.geometry,
                strokeWidth: 7,
                color: MotoGoColors.dark.withValues(alpha: 0.35),
              ),
              Polyline(
                points: widget.geometry,
                strokeWidth: 4.5,
                color: MotoGoColors.greenDark,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (widget.start != null)
              Marker(
                point: widget.start!,
                width: 40,
                height: 40,
                child: const _StartPin(),
              ),
            for (final p in widget.pois)
              Marker(
                point: p.point,
                width: 34,
                height: 34,
                child: GestureDetector(
                  onTap: () => widget.onPoiTap?.call(p.index),
                  child: _PoiPin(
                    index: p.index,
                    active: widget.activePoi == p.index,
                  ),
                ),
              ),
          ],
        ),
        // Povinná atribuce Mapy.com
        RichAttributionWidget(
          attributions: const [
            TextSourceAttribution('Mapy.com'),
          ],
        ),
      ],
    );
  }
}

class _StartPin extends StatelessWidget {
  const _StartPin();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MotoGoColors.green,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.3), blurRadius: 6),
        ],
      ),
      child: const Icon(Icons.flag, size: 20, color: MotoGoColors.black),
    );
  }
}

class _PoiPin extends StatelessWidget {
  final int index;
  final bool active;
  const _PoiPin({required this.index, required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: active ? 1.25 : 1.0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      child: Container(
        decoration: BoxDecoration(
          color: active ? MotoGoColors.greenDarker : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: MotoGoColors.greenDarker, width: 2.5),
          boxShadow: [
            BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.25), blurRadius: 5),
          ],
        ),
        child: Center(
          child: Text(
            '${index + 1}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: active ? Colors.white : MotoGoColors.greenDarker,
            ),
          ),
        ),
      ),
    );
  }
}
