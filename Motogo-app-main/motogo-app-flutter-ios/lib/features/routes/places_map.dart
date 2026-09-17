import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';
import 'poi_categories.dart';
import 'routes_provider.dart' show PoiEntry, mapyApiKey;

/// Mapa MÍST (bodů zájmu) — sdílená mezi pruhem nad seznamem a celoobrazovkovou
/// mapou.
///
/// VÝKON: katalog má desítky tisíc bodů a `MarkerLayer` staví jeden widget na
/// každý marker, takže vykreslit všechno je jistý pád. Řešíme dvěma kroky bez
/// jakékoli nové závislosti (iOS strom pinuje starší balíčky, viz CLAUDE.md):
///   1. ořez na aktuální výřez kamery (+ malá rezerva),
///   2. shlukování do mřížky, jejíž velikost se odvozuje od zoomu — v jedné
///      buňce se vykreslí JEDEN marker s počtem bodů.
/// Nad [_kMaxMarkers] bodů ve výřezu se zobrazují jen shluky.
class PlacesMapView extends StatefulWidget {
  final List<PoiEntry> places;
  final String lang;

  /// Klíče vybraných míst — vykreslí se zeleně a s fajfkou.
  final Set<String> selected;

  /// Tap na konkrétní místo (marker shluku se místo toho přiblíží).
  final void Function(PoiEntry entry)? onPlaceTap;

  /// Dlouhý stisk do mapy — nabídne přidání nového místa na daném bodě.
  final void Function(LatLng point)? onLongPress;

  /// Poloha jezdce — vykreslí se jako modrý bod a použije pro tlačítko
  /// „vycentrovat na mě".
  final LatLng? me;

  /// Výchozí výřez; null = přizpůsobí se datům (nebo střed ČR).
  final LatLng? initialCenter;
  final double initialZoom;
  final bool interactive;

  /// Povolit posun prstem. Uvnitř scrollovaného seznamu se vypíná — jinak
  /// si mapa vezme svislý drag a seznamem přes ni nejde scrollovat.
  final bool allowDrag;

  const PlacesMapView({
    super.key,
    required this.places,
    required this.lang,
    this.selected = const {},
    this.onPlaceTap,
    this.onLongPress,
    this.me,
    this.initialCenter,
    this.initialZoom = 7.2,
    this.interactive = true,
    this.allowDrag = true,
  });

  @override
  State<PlacesMapView> createState() => PlacesMapViewState();
}

/// Kolik jednotlivých markerů maximálně vykreslíme, než přepneme na shluky.
const int _kMaxMarkers = 220;

/// Střed ČR — výchozí pohled, když není poloha ani data.
const LatLng _kCzCenter = LatLng(49.75, 15.35);

class PlacesMapViewState extends State<PlacesMapView> {
  final MapController _ctrl = MapController();
  LatLngBounds? _bounds;
  double _zoom = 7.2;
  // Throttle překreslení: onPositionChanged chodí při každém snímku posunu
  // a ořez výřezu prochází celý katalog (desítky tisíc bodů). Bez omezení by
  // se ten průchod dělal 60× za sekundu a mapa by sekala.
  Timer? _syncThrottle;
  bool _syncPending = false;
  /// Uživatel už s mapou sám hnul — pak ji poloha nepřetahuje pod rukama.
  bool _userMoved = false;

  @override
  void initState() {
    super.initState();
    _zoom = widget.initialZoom;
  }

  @override
  void didUpdateWidget(PlacesMapView old) {
    super.didUpdateWidget(old);
    // `initialCenter`/`initialZoom` platí jen pro PRVNÍ snímek. Poloha ale
    // často dorazí až potom (uživatel ji zrovna povolil), takže se na ni
    // musí kamera posunout ručně — jinak mapa zůstane nad středem ČR.
    final me = widget.me;
    if (me != null && old.me == null && !_userMoved) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ctrl.move(me, math.max(_zoom, 10.5));
      });
    }
  }

  @override
  void dispose() {
    _syncThrottle?.cancel();
    super.dispose();
  }

  /// Přesune kameru na dané místo (volá ji celoobrazovková mapa z hledání).
  void moveTo(LatLng p, {double zoom = 13}) => _ctrl.move(p, zoom);

  /// Vycentruje na polohu jezdce, pokud je známá.
  void centerOnMe() {
    final me = widget.me;
    if (me != null) _ctrl.move(me, math.max(_zoom, 11));
  }

  /// Hrana shlukovací buňky ve stupních — na nižším zoomu hrubší mřížka.
  double _cellSize(double zoom) {
    if (zoom >= 13) return 0.01;
    if (zoom >= 11) return 0.04;
    if (zoom >= 9) return 0.15;
    if (zoom >= 7) return 0.5;
    return 1.5;
  }

  /// Body ve výřezu (s rezervou), aby se při posunu mapy nedoplňovaly skokem.
  List<PoiEntry> _visible() {
    final b = _bounds;
    if (b == null) return widget.places;
    final padLat = (b.north - b.south) * 0.25;
    final padLng = (b.east - b.west) * 0.25;
    final south = b.south - padLat, north = b.north + padLat;
    final west = b.west - padLng, east = b.east + padLng;
    final out = <PoiEntry>[];
    for (final e in widget.places) {
      final p = e.latLng;
      if (p == null) continue;
      if (p.latitude < south || p.latitude > north) continue;
      if (p.longitude < west || p.longitude > east) continue;
      out.add(e);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible();
    final showClusters = visible.length > _kMaxMarkers;

    final markers = <Marker>[];
    if (showClusters) {
      final cell = _cellSize(_zoom);
      // Klíč buňky → (počet, součet souřadnic pro těžiště).
      final buckets = <String, ({int n, double lat, double lng})>{};
      for (final e in visible) {
        final p = e.latLng!;
        final key = '${(p.latitude / cell).floor()}:${(p.longitude / cell).floor()}';
        final cur = buckets[key];
        buckets[key] = cur == null
            ? (n: 1, lat: p.latitude, lng: p.longitude)
            : (n: cur.n + 1, lat: cur.lat + p.latitude, lng: cur.lng + p.longitude);
      }
      for (final b in buckets.values) {
        final center = LatLng(b.lat / b.n, b.lng / b.n);
        markers.add(_clusterMarker(center, b.n));
      }
    } else {
      for (final e in visible) {
        markers.add(_placeMarker(e));
      }
    }

    return FlutterMap(
      mapController: _ctrl,
      options: MapOptions(
        initialCenter: widget.initialCenter ?? widget.me ?? _kCzCenter,
        initialZoom: widget.initialZoom,
        minZoom: 3,
        maxZoom: 18,
        interactionOptions: InteractionOptions(
          flags: !widget.interactive
              ? InteractiveFlag.none
              : widget.allowDrag
                  ? InteractiveFlag.all & ~InteractiveFlag.rotate
                  : (InteractiveFlag.pinchZoom |
                      InteractiveFlag.doubleTapZoom |
                      InteractiveFlag.scrollWheelZoom),
        ),
        onLongPress: widget.onLongPress == null
            ? null
            : (_, p) => widget.onLongPress!(p),
        onPointerDown: (_, __) => _userMoved = true,
        onMapReady: _syncCamera,
        onPositionChanged: (_, __) => _scheduleSync(),
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://api.mapy.cz/v1/maptiles/outdoor/256/{z}/{x}/{y}?apikey=$mapyApiKey',
          userAgentPackageName: 'com.motogo24.rental',
          maxZoom: 19,
        ),
        if (widget.me != null)
          MarkerLayer(markers: [
            Marker(
              point: widget.me!,
              width: 22,
              height: 22,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF2B7FFF),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
          ]),
        MarkerLayer(markers: markers),
      ],
    );
  }

  /// Naplánuje přepočet výřezu nejvýš ~8× za sekundu.
  void _scheduleSync() {
    if (_syncThrottle?.isActive ?? false) {
      _syncPending = true;
      return;
    }
    _syncCamera();
    _syncThrottle = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      if (_syncPending) {
        _syncPending = false;
        _syncCamera();
      }
    });
  }

  /// Uloží aktuální výřez a zoom. Překreslí se jen to, co je vidět.
  void _syncCamera() {
    if (!mounted) return;
    final cam = _ctrl.camera;
    final b = cam.visibleBounds;
    final z = cam.zoom;
    if (!z.isFinite) return;
    final changed = _bounds == null ||
        (z - _zoom).abs() > 0.05 ||
        (b.south - _bounds!.south).abs() > 0.0005 ||
        (b.west - _bounds!.west).abs() > 0.0005 ||
        (b.north - _bounds!.north).abs() > 0.0005 ||
        (b.east - _bounds!.east).abs() > 0.0005;
    if (!changed) return;
    setState(() {
      _bounds = b;
      _zoom = z;
    });
  }

  Marker _clusterMarker(LatLng center, int n) {
    final size = n >= 500
        ? 54.0
        : n >= 100
            ? 46.0
            : n >= 25
                ? 40.0
                : 34.0;
    return Marker(
      point: center,
      width: size,
      height: size,
      child: GestureDetector(
        onTap: () => _ctrl.move(center, math.min(_zoom + 2.5, 17)),
        child: Container(
          decoration: BoxDecoration(
            color: MotoGoColors.greenDark.withValues(alpha: 0.92),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(
              n > 999 ? '${(n / 1000).floor()}k' : '$n',
              style: TextStyle(
                fontSize: size >= 46 ? 14 : 12,
                fontWeight: MotoGoTypo.w900,
                color: Colors.white,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Marker _placeMarker(PoiEntry e) {
    final sel = widget.selected.contains(e.key);
    return Marker(
      point: e.latLng!,
      width: 34,
      height: 34,
      child: GestureDetector(
        onTap: widget.onPlaceTap == null ? null : () => widget.onPlaceTap!(e),
        child: Container(
          decoration: BoxDecoration(
            color: sel ? MotoGoColors.green : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: sel ? MotoGoColors.greenDarker : MotoGoColors.g300,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: sel
                ? const Icon(Icons.check, size: 18, color: Colors.white)
                : Text(poiCatEmoji(e.poi), style: const TextStyle(fontSize: 15)),
          ),
        ),
      ),
    );
  }
}
