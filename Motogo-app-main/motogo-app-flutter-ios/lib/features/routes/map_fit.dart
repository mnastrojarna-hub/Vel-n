import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Bezpečné přizpůsobení kamery na body trasy.
///
/// Degenerované ohraničení (všechny body ~stejné, případně jediný bod) dá ve
/// flutter_map při `CameraFit.bounds` NaN/nekonečný zoom → v dlaždicové vrstvě
/// spadne appka na `Unsupported operation: Infinity or NaN toInt`
/// (`_TileLayerState._clampToNativeZoom`). Řešíme tím, že u zanedbatelného
/// rozpětí jen odcentrujeme s daným zoomem a spočtený zoom vždy ohlídáme na
/// konečnou hodnotu.
void fitMapSafe(
  MapController ctrl,
  List<LatLng> points, {
  EdgeInsets padding = const EdgeInsets.all(36),
  double singleZoom = 13,
  double maxZoom = 16,
}) {
  final pts = points
      .where((p) => p.latitude.isFinite && p.longitude.isFinite)
      .toList();
  if (pts.isEmpty) return;

  double minLat = pts.first.latitude, maxLat = pts.first.latitude;
  double minLng = pts.first.longitude, maxLng = pts.first.longitude;
  for (final p in pts) {
    if (p.latitude < minLat) minLat = p.latitude;
    if (p.latitude > maxLat) maxLat = p.latitude;
    if (p.longitude < minLng) minLng = p.longitude;
    if (p.longitude > maxLng) maxLng = p.longitude;
  }
  final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);

  // Rozpětí menší než ~50 m → ber jako jeden bod (fitCamera by dal ∞/NaN zoom).
  const eps = 0.0005; // ~50 m
  if (maxLat - minLat < eps && maxLng - minLng < eps) {
    ctrl.move(center, singleZoom);
    return;
  }
  try {
    final cam = CameraFit.bounds(
      bounds: LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng)),
      padding: padding,
    ).fit(ctrl.camera);
    final z = cam.zoom.isFinite ? cam.zoom.clamp(3.0, maxZoom) : singleZoom;
    ctrl.move(cam.center, z);
  } catch (_) {
    ctrl.move(center, singleZoom);
  }
}
