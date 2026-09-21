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

  /// Vykreslit atribuci Mapy.com vlevo dole místo vpravo dole. Celoobrazovkové
  /// mapy mají v pravém dolním rohu kulatá tlačítka („moje poloha", „přidat
  /// místo"), takže by je ⓘ atribuce podlézala.
  final bool attributionOnLeft;

  final bool showAttribution;

  /// Zobrazit atribuci vůbec. V 160px náhledovém pruhu nad seznamem Míst se
  /// NEZOBRAZUJE: celý pruh je jedno velké tlačítko „otevři mapu na celou
  /// obrazovku" a ⓘ tlačítko atribuce by to kliknutí v rohu spolklo.
  /// Celoobrazovková mapa, kterou pruh otevírá, atribuci má.

  /// Klíče vybraných míst — vykreslí se zeleně a s fajfkou.
  final Set<String> selected;

  /// Tap na konkrétní místo (marker shluku se místo toho přiblíží).
  final void Function(PoiEntry entry)? onPlaceTap;

  /// Dlouhý stisk NA MÍSTĚ — otevře jeho detail; krátký tap přepíná výběr.
  final void Function(PoiEntry entry)? onPlaceLongPress;

  /// Klepnutí do mapy MIMO místo — náhled nad seznamem tím otevře mapu přes
  /// celou obrazovku (dřív to uměla jen malá ikonka v rohu).
  final VoidCallback? onMapTap;

  /// Odlišit body ležící NA TRASE (mapa tras) — zeleně, ostatní místa bíle.
  final bool markRouteStops;

  /// Trasa poskládaná uživatelem v editoru („Tvoje trasa") — kreslí se
  /// výrazně a nad ostatními čarami.
  final List<LatLng> draftLine;

  /// Dlouhý stisk do prázdné mapy — nabídne přidání nového místa.
  final void Function(LatLng point)? onLongPress;

  /// Trasy k vykreslení. Mapa míst je ve výchozím stavu BEZ tras — čáry se
  /// objeví až tehdy, když uživatel označí místo, a jen u tras, které to
  /// místo obsahují.
  final List<List<LatLng>> routeLines;

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
    this.attributionOnLeft = false,
    this.showAttribution = true,
    this.selected = const {},
    this.routeLines = const [],
    this.onPlaceTap,
    this.onPlaceLongPress,
    this.onMapTap,
    this.onLongPress,
    this.markRouteStops = false,
    this.draftLine = const [],
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
    // Body, u kterých se na velkém přiblížení vypíše i název. Bez popisků byla
    // mapa jen řada bílých koleček s emoji — uživatel z ní nepoznal, na co se
    // dívá, dokud na špendlík nepodržel prst.
    final labelled = <PoiEntry>[];
    if (showClusters) {
      // Vybraná místa se kreslí VŽDY samostatně — jinak zmizí ve shluku
      // a uživatel nevidí, co má v rozdělané trase.
      final picked = <PoiEntry>[];
      final cell = _cellSize(_zoom);
      // Klíč buňky → (počet, součet souřadnic pro těžiště, první bod).
      // `first` se drží kvůli osamoceným buňkám: dřív se i JEDINÉ místo v buňce
      // nakreslilo jako zelená bublina s číslicí „1" — na běžném zoomu tak byla
      // většina mapy jen číslíčka místo špendlíků, což je půlka toho, proč
      // mapa „vypadá stroze".
      final buckets = <String, ({int n, double lat, double lng, PoiEntry first})>{};
      for (final e in visible) {
        final p = e.latLng!;
        if (widget.selected.contains(e.key)) {
          picked.add(e);
          continue;
        }
        final key = '${(p.latitude / cell).floor()}:${(p.longitude / cell).floor()}';
        final cur = buckets[key];
        buckets[key] = cur == null
            ? (n: 1, lat: p.latitude, lng: p.longitude, first: e)
            : (n: cur.n + 1, lat: cur.lat + p.latitude, lng: cur.lng + p.longitude, first: cur.first);
      }
      for (final b in buckets.values) {
        if (b.n == 1) {
          markers.add(_placeMarker(b.first));
          labelled.add(b.first);
          continue;
        }
        // Těžiště dvou vzdálených bodů padá doprostřed pole, kde žádné místo
        // není. U malých shluků proto bublinu posadíme na skutečný bod.
        final center = b.n <= 3
            ? b.first.latLng!
            : LatLng(b.lat / b.n, b.lng / b.n);
        markers.add(_clusterMarker(center, b.n));
      }
      for (final e in picked) {
        markers.add(_placeMarker(e));
        labelled.add(e);
      }
    } else {
      for (final e in visible) {
        markers.add(_placeMarker(e));
        labelled.add(e);
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
        onTap: widget.onMapTap == null ? null : (_, __) => widget.onMapTap!(),
        onLongPress: widget.onLongPress == null
            ? null
            : (_, p) => widget.onLongPress!(p),
        onMapReady: _syncCamera,
        onPositionChanged: (_, hasGesture) {
          // Jen skutečný posun/zoom prstem znamená „uživatel si mapu srovnal
          // sám". Dřív stačil pointerDown, který chodí i při scrollu seznamu
          // přes náhled mapy — kamera se pak na dodatečně zjištěnou polohu
          // už nikdy neposunula a mapa zůstala nad středem ČR.
          if (hasGesture) _userMoved = true;
          _scheduleSync();
        },
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://api.mapy.cz/v1/maptiles/outdoor/256/{z}/{x}/{y}?apikey=$mapyApiKey',
          userAgentPackageName: 'com.motogo24.rental',
          maxZoom: 19,
        ),
        // Trasy pod markery, ať body zůstanou čitelné.
        if (widget.routeLines.isNotEmpty)
          PolylineLayer(
            polylines: [
              for (final pts in widget.routeLines)
                if (pts.length >= 2)
                  Polyline(
                    points: pts,
                    strokeWidth: 4,
                    color: MotoGoColors.greenDark.withValues(alpha: 0.85),
                  ),
            ],
          ),
        // „Tvoje trasa" z editoru — silná tmavá čára nad ostatními.
        if (widget.draftLine.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: widget.draftLine,
                strokeWidth: 6,
                color: MotoGoColors.greenDarker,
              ),
            ],
          ),
        MarkerLayer(markers: markers),
        // Popisky až od zoomu 12 a jen když jich není moc — jinak by se
        // překrývaly. `IgnorePointer` je nutný, aby popisek nekradl klepnutí
        // určené špendlíku pod ním.
        if (_zoom >= 12 && labelled.length <= 45)
          MarkerLayer(markers: [
            for (final e in labelled) _labelMarker(e),
          ]),
        // Vlastní poloha až NAD místy — dřív ji v hustém okolí překryl
        // kterýkoli 34px špendlík a jezdec nevěděl, kde je.
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
        // Povinná atribuce: podklad je z Mapy.com, část katalogu míst
        // (studánky, prameny a vyhlídky, dávky `osm-springs-cz-sk-*`)
        // pochází z OpenStreetMap a licence ODbL uvedení zdroje vyžaduje.
        // Roh si volí každá obrazovka sama — vpravo dole sedí kulatá
        // tlačítka („moje poloha", „přidat místo"), vlevo dole zase odznak
        // „Tvoje trasa" na mapě tras.
        if (widget.showAttribution)
          RichAttributionWidget(
            alignment: widget.attributionOnLeft
                ? AttributionAlignment.bottomLeft
                : AttributionAlignment.bottomRight,
            // Bez loga flutter_map — do zákaznické obrazovky cizí branding nepatří.
            showFlutterMapAttribution: false,
            attributions: const [
              TextSourceAttribution('Mapy.com · © OpenStreetMap'),
            ],
          ),
      ],
    );
  }

  /// Popisek místa pod špendlíkem (jen na velkém přiblížení).
  ///
  /// `Alignment.bottomCenter` znamená v flutter_map „celý rámeček je POD
  /// bodem" (viz marker_layer.dart: `top = 0.5*h*(y+1)`, `bottom = h - top`,
  /// `Positioned(top: pos.y - bottom)`) — opak toho, co by člověk čekal.
  /// S `topCenter` by popisek skončil nad špendlíkem a překryl ho.
  Marker _labelMarker(PoiEntry e) => Marker(
        point: e.latLng!,
        width: 148,
        height: 40,
        alignment: Alignment.bottomCenter,
        child: IgnorePointer(
          child: Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  e.poi.nameFor(widget.lang),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: MotoGoTypo.w900,
                    color: MotoGoColors.greenDarker,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

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
        behavior: HitTestBehavior.opaque,
        onTap: () => _ctrl.move(center, math.min(_zoom + 2.5, 17)),
        // I podržení shluku jen přiblíží — bez toho propadlo na mapu a otevřelo
        // „přidat nové místo", ačkoli uživatel chtěl detail bodu pod prstem.
        onLongPress: () => _ctrl.move(center, math.min(_zoom + 2.5, 17)),
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
    // Body tras mají na mapě tras VLASTNÍ barvu, aby šly odlišit od ostatních
    // míst (zadání uživatele).
    final onRoute = widget.markRouteStops && e.onRoute;
    return Marker(
      point: e.latLng!,
      width: 34,
      height: 34,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPlaceTap == null ? null : () => widget.onPlaceTap!(e),
        // Detail místa = PODRŽENÍ. Dvojklik tu záměrně NENÍ: gesture detektor
        // by pak musel u každého klepnutí čekat ~300 ms, jestli nepřijde druhé,
        // a výběr místa by působil, že mapa nereaguje.
        onLongPress: widget.onPlaceLongPress == null
            ? null
            : () => widget.onPlaceLongPress!(e),
        child: Container(
          decoration: BoxDecoration(
            color: sel
                ? MotoGoColors.green
                : (onRoute ? MotoGoColors.greenPale : Colors.white),
            shape: BoxShape.circle,
            border: Border.all(
              color: sel
                  ? MotoGoColors.greenDarker
                  : (onRoute ? MotoGoColors.greenDark : MotoGoColors.g300),
              width: onRoute && !sel ? 2.5 : 2,
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
