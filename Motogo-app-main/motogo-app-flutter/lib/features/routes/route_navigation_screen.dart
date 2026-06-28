import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';
import '../../core/router.dart' show MotoGoBackNav;
import '../../core/i18n/i18n_provider.dart';
import '../../core/native/gps_service.dart';
import 'routes_model.dart';
import 'routes_provider.dart';
import 'route_poi_sheet.dart';

/// Navigace trasy PŘÍMO v aplikaci — plnohodnotný navigátor: fullscreen mapa
/// Mapy.com, živá poloha jezdce, sledování (follow) s otáčením mapy po směru
/// jízdy (heading-up), projetá část trasy se odečítá (šedne) a HUD ukazuje
/// rychlost, zbývající vzdálenost PO TRASE, čas dojezdu, čas příjezdu a
/// nadmořskou výšku. Bez závislosti na externí navigaci.
class RouteNavigationScreen extends ConsumerStatefulWidget {
  final String? routeId;
  /// Vlastní trasa složená ze zákazníkem vybraných bodů zájmu (katalog POI).
  /// Když je zadaná, naviguje se přímo přes ni (bez načítání trasy z DB).
  final RouteItem? customRoute;
  /// Profil routingu (doporučené bez dálnic / nejrychlejší / nejkratší).
  final RouteProfile profile;

  const RouteNavigationScreen({super.key, required this.routeId})
      : customRoute = null,
        profile = RouteProfile.recommended;
  const RouteNavigationScreen.custom({
    super.key,
    required RouteItem route,
    this.profile = RouteProfile.recommended,
  })  : routeId = null,
        customRoute = route;

  @override
  ConsumerState<RouteNavigationScreen> createState() => _RouteNavigationScreenState();
}

class _RouteNavigationScreenState extends ConsumerState<RouteNavigationScreen> {
  // Zoom při navigaci — dost blízko, ať jezdec vidí odbočky.
  static const double _navZoom = 16.5;
  // Pod touto rychlostí (km/h) je GPS heading nespolehlivý → mapou neotáčíme.
  static const double _moveThreshold = 6;

  final MapController _ctrl = MapController();
  StreamSubscription<Position>? _sub;
  LatLng? _me;
  double? _heading;
  double _speedKmh = 0;
  double? _altitude;
  bool _follow = true;
  bool _headingUp = true; // otáčet mapu po směru jízdy
  bool _locating = true;
  bool _denied = false;
  bool _firstFix = true;
  double _smoothHeading = 0; // vyhlazený směr (proti cukání mapy)
  double _mapRot = 0; // aktuální rotace mapy (pro kompas)

  // Živá trasa od aktuální polohy — nejrychlejší BEZ dálnic (Mapy.com routing).
  RouteItem? _route;
  RouteBranch? _branch;
  List<LatLng>? _navGeo;
  bool _navLoading = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final ok = await GpsService.ensurePermission();
    if (!mounted) return;
    if (!ok) {
      setState(() { _locating = false; _denied = true; });
      return;
    }
    setState(() => _locating = false);
    try {
      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 4,
        ),
      ).listen(_onPosition);
    } catch (_) {
      // bez streamu zkus aspoň jednorázovou polohu
      final p = await GpsService.getCurrentPosition();
      if (mounted && p != null) _onPosition(p);
    }
  }

  void _onPosition(Position pos) {
    if (!mounted) return;
    final me = LatLng(pos.latitude, pos.longitude);
    final hdg = (pos.heading >= 0 && pos.heading <= 360) ? pos.heading : null;
    final spd = pos.speed.isFinite && pos.speed > 0 ? pos.speed * 3.6 : 0.0;
    final alt = pos.altitude.isFinite && pos.altitude != 0 ? pos.altitude : null;
    final moving = spd > _moveThreshold && hdg != null;
    if (moving) _smoothHeading = _lerpAngle(_smoothHeading, hdg!, 0.35);

    setState(() {
      _me = me;
      _heading = hdg;
      _speedKmh = spd;
      _altitude = alt;
    });

    // Sledování polohy + (volitelně) otáčení mapy po směru jízdy.
    final wantRot = _follow && _headingUp && moving;
    final rot = wantRot ? -_smoothHeading : (_headingUp ? _mapRot : 0.0);
    if (_firstFix) {
      _firstFix = false;
      _ctrl.moveAndRotate(me, _navZoom, wantRot ? rot : _mapRot);
      _mapRot = wantRot ? rot : _mapRot;
    } else if (_follow) {
      final z = _ctrl.camera.zoom;
      final nz = z < 14 ? _navZoom : z;
      if (wantRot) {
        _ctrl.moveAndRotate(me, nz, rot);
        _mapRot = rot;
      } else {
        _ctrl.move(me, nz);
      }
    }
    _maybeComputeNav();
  }

  /// Spočte živou trasu od aktuální polohy přes body trasy — nejrychleji BEZ
  /// dálnic (Mapy.com routing). Počítá se jen jednou (po prvním GPS fixu).
  Future<void> _maybeComputeNav() async {
    if (_navLoading || _navGeo != null) return;
    final me = _me;
    final route = _route;
    if (me == null || route == null) return;
    _navLoading = true;
    final loopBack = route.isLoop ? _branch?.latLng : null;
    final pts = navPointsFrom(me, route, loopBack);
    if (pts.length < 2) {
      _navLoading = false;
      return;
    }
    final geo = await fetchMapyRoute(pts, profile: widget.profile);
    if (!mounted) {
      _navLoading = false;
      return;
    }
    setState(() {
      _navGeo = geo ?? pts;
      _navLoading = false;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _recenter() {
    setState(() {
      _follow = true;
      _headingUp = true;
    });
    final me = _me;
    if (me == null) return;
    final moving = _speedKmh > _moveThreshold && _heading != null;
    if (moving) {
      _mapRot = -_smoothHeading;
      _ctrl.moveAndRotate(me, _navZoom, _mapRot);
    } else {
      _ctrl.move(me, _navZoom);
    }
  }

  void _resetNorth() {
    setState(() => _headingUp = false);
    _mapRot = 0;
    _ctrl.rotate(0);
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeProvider).languageCode;

    // Vlastní trasa z vybraných bodů zájmu — naviguj přímo, bez DB lookupu.
    final custom = widget.customRoute;
    if (custom != null) {
      _route = custom;
      _branch = null;
      if (_me != null && _navGeo == null && !_navLoading) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _maybeComputeNav());
      }
      final geometry = _navGeo ?? custom.geometry;
      return Scaffold(
        backgroundColor: MotoGoColors.bg,
        body: _content(context, custom, null, geometry, lang),
      );
    }

    final dataAsync = ref.watch(routesDataProvider);

    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: MotoGoColors.greenDark)),
        error: (_, __) => _exit(context),
        data: (data) {
          final route = data.routes.firstWhere(
            (r) => r.id == widget.routeId,
            orElse: () => const RouteItem(id: '', name: ''),
          );
          if (route.id.isEmpty) return _exit(context);
          final branch = route.branchId != null ? data.branches[route.branchId] : null;
          _route = route;
          _branch = branch;
          if (_me != null && _navGeo == null && !_navLoading) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _maybeComputeNav());
          }
          final displayAsync = ref.watch(routeDisplayProvider(route.id));
          final baseGeometry = displayAsync.valueOrNull?.geometry ?? route.geometry;
          // Po prvním GPS fixu navigujeme po živé trase od polohy (bez dálnic).
          final geometry = _navGeo ?? baseGeometry;
          return _content(context, route, branch, geometry, lang);
        },
      ),
    );
  }

  Widget _content(BuildContext context, RouteItem route, RouteBranch? branch,
      List<LatLng> geometry, String lang) {
    final pois = <Marker>[];
    for (var i = 0; i < route.pois.length; i++) {
      final idx = i; // zachyť index do closure
      final poi = route.pois[idx];
      final ll = poi.latLng;
      if (ll != null) {
        pois.add(Marker(
          point: ll,
          width: 34,
          height: 34,
          child: GestureDetector(
            onTap: () => showRoutePoiSheet(context, poi, lang, index: idx),
            child: _NumPin(index: idx),
          ),
        ));
      }
    }

    // Projekce polohy na trasu → rozdělení na PROJETOU (šedá) a ZBÝVAJÍCÍ (zelená)
    // + zbývající a celková vzdálenost PO TRASE (ne vzdušnou čarou).
    final prog = (_me != null && geometry.length >= 2)
        ? _projectOnRoute(geometry, _me!)
        : null;
    List<LatLng> doneGeo = const [];
    List<LatLng> aheadGeo = geometry;
    if (prog != null) {
      doneGeo = [...geometry.sublist(0, prog.segIndex + 1), prog.snapped];
      aheadGeo = [prog.snapped, ...geometry.sublist(prog.segIndex + 1)];
    }
    final fraction = (prog != null && prog.totalM > 0)
        ? ((prog.totalM - prog.remainingM) / prog.totalM).clamp(0.0, 1.0)
        : 0.0;

    // Nejbližší bod zájmu (vzdušně) — drobná nápověda „co tě čeká".
    final nextPoi = _nearestPoi(route, _me);

    final initialCenter = _me ??
        branch?.latLng ??
        (geometry.isNotEmpty ? geometry.first : const LatLng(49.3464, 15.2119));

    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            mapController: _ctrl,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: _me != null ? _navZoom : 13,
              onPositionChanged: (position, hasGesture) {
                if (hasGesture) {
                  // MapPosition nemá rotation → vezmi ji z controlleru.
                  _mapRot = _ctrl.camera.rotation;
                  if (_follow) setState(() => _follow = false);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://api.mapy.cz/v1/maptiles/outdoor/256/{z}/{x}/{y}?apikey=$mapyApiKey',
                userAgentPackageName: 'com.motogo24.app',
                maxZoom: 19,
              ),
              // Projetá část — zešedne (vizuálně se „odečte").
              if (doneGeo.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(points: doneGeo, strokeWidth: 5, color: MotoGoColors.g400.withValues(alpha: 0.55)),
                  ],
                ),
              // Zbývající část — výrazná zelená s tmavým podkladem.
              if (aheadGeo.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(points: aheadGeo, strokeWidth: 9, color: MotoGoColors.dark.withValues(alpha: 0.3)),
                    Polyline(points: aheadGeo, strokeWidth: 6, color: MotoGoColors.greenDark),
                  ],
                ),
              MarkerLayer(markers: [
                if (branch?.latLng != null)
                  Marker(
                    point: branch!.latLng!,
                    width: 36,
                    height: 36,
                    child: Container(
                      decoration: BoxDecoration(
                        color: MotoGoColors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: const Icon(Icons.flag, size: 18, color: MotoGoColors.black),
                    ),
                  ),
                ...pois,
                if (_me != null)
                  Marker(
                    point: _me!,
                    width: 34,
                    height: 34,
                    // Šipka ukazuje skutečný směr jízdy i při otočené mapě.
                    child: _MeMarker(
                      arrowDeg: _heading == null ? null : _heading! + _mapRot,
                    ),
                  ),
              ]),
              RichAttributionWidget(
                attributions: const [TextSourceAttribution('Mapy.com')],
              ),
            ],
          ),
        ),

        // Horní lišta — zpět + název trasy
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(12, MediaQuery.of(context).padding.top + 8, 12, 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [MotoGoColors.dark.withValues(alpha: 0.9), MotoGoColors.dark.withValues(alpha: 0.0)],
              ),
            ),
            child: Row(
              children: [
                _circleBtn(Icons.arrow_back, () => context.backOr('/routes/${route.id}')),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        route.nameFor(lang),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: MotoGoTypo.w800, color: Colors.white, decoration: TextDecoration.none),
                      ),
                      Text(
                        _locating
                            ? t(context).tr('routeNavLocating')
                            : (_navLoading ? t(context).tr('routeNavComputing') : t(context).tr('routeNavTitle')),
                        style: const TextStyle(fontSize: 12, fontWeight: MotoGoTypo.w600, color: Color(0xFF8AAB99), decoration: TextDecoration.none),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Kompas — objeví se, když je mapa otočená; klik = zpět na sever.
        if (_mapRot.abs() > 1)
          Positioned(
            top: MediaQuery.of(context).padding.top + 64,
            right: 16,
            child: _CompassButton(rotationDeg: _mapRot, onTap: _resetNorth),
          ),

        // Banner při zamítnuté poloze
        if (_denied)
          Positioned(
            left: 16, right: 16, bottom: 150,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(MotoGoRadius.xl),
                boxShadow: MotoGoShadows.cardSmall,
              ),
              child: Row(
                children: [
                  const Text('📍', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t(context).tr('routeNavNoLocation'),
                      style: const TextStyle(fontSize: 12, fontWeight: MotoGoTypo.w600, color: MotoGoColors.black, decoration: TextDecoration.none),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Příští bod zájmu — drobná pilulka nad HUD.
        if (nextPoi != null)
          Positioned(
            left: 16, right: 72, bottom: 150,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _NextPoiPill(name: nextPoi.$1.nameFor(lang), distanceM: nextPoi.$2),
            ),
          ),

        // Recenter — nad spodním HUD
        Positioned(
          right: 16, bottom: 150,
          child: FloatingActionButton(
            heroTag: 'route-nav-recenter',
            mini: true,
            backgroundColor: _follow ? MotoGoColors.greenDark : Colors.white,
            foregroundColor: _follow ? Colors.white : MotoGoColors.greenDark,
            onPressed: _recenter,
            child: const Icon(Icons.navigation_outlined),
          ),
        ),

        // Spodní HUD — rychlost / zbývá / čas / příjezd / výška + progress
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: _NavHud(
            remainingM: prog?.remainingM,
            speedKmh: _speedKmh,
            altitude: _altitude,
            fraction: fraction,
          ),
        ),
      ],
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(MotoGoRadius.lg),
            boxShadow: MotoGoShadows.cardSmall,
          ),
          child: Icon(icon, size: 20, color: MotoGoColors.black),
        ),
      );

  Widget _exit(BuildContext context) => Center(
        child: ElevatedButton(
          onPressed: () => context.backOr('/routes'),
          child: Text(t(context).tr('routeNotFound')),
        ),
      );
}

/// Nejbližší bod zájmu (vzdušnou čarou) od polohy — vrací (POI, metry) nebo null.
(RoutePoi, double)? _nearestPoi(RouteItem route, LatLng? me) {
  if (me == null) return null;
  const dist = Distance();
  RoutePoi? best;
  double bestM = double.infinity;
  for (final p in route.pois) {
    final ll = p.latLng;
    if (ll == null) continue;
    final d = dist.as(LengthUnit.Meter, me, ll);
    if (d < bestM) {
      bestM = d;
      best = p;
    }
  }
  if (best == null || bestM > 30000) return null; // přes 30 km už nezobrazuj
  return (best, bestM);
}

/// Vyhlazení úhlu nejkratší cestou (zamezí skoku 359°→0°).
double _lerpAngle(double a, double b, double t) {
  double d = (b - a) % 360;
  if (d > 180) d -= 360;
  if (d < -180) d += 360;
  return a + d * t;
}

/// Výsledek projekce polohy na polyline trasy.
class _RouteProgress {
  final int segIndex; // index počátku segmentu, na který poloha spadla
  final LatLng snapped; // nejbližší bod na trase
  final double remainingM; // metry do cíle PO TRASE
  final double totalM; // celková délka trasy
  const _RouteProgress(this.segIndex, this.snapped, this.remainingM, this.totalM);
}

/// Promítne polohu na nejbližší segment trasy a spočítá zbývající i celkovou délku.
_RouteProgress? _projectOnRoute(List<LatLng> geo, LatLng me) {
  if (geo.length < 2) return null;
  const dist = Distance();
  double best = double.infinity;
  int bestSeg = 0;
  LatLng bestSnap = geo.first;
  final segLen = <double>[];
  double total = 0;
  for (var i = 0; i < geo.length - 1; i++) {
    final l = dist.as(LengthUnit.Meter, geo[i], geo[i + 1]);
    segLen.add(l);
    total += l;
    final snap = _closestOnSeg(geo[i], geo[i + 1], me);
    final d = dist.as(LengthUnit.Meter, me, snap);
    if (d < best) {
      best = d;
      bestSeg = i;
      bestSnap = snap;
    }
  }
  double rem = dist.as(LengthUnit.Meter, bestSnap, geo[bestSeg + 1]);
  for (var i = bestSeg + 1; i < geo.length - 1; i++) {
    rem += segLen[i];
  }
  return _RouteProgress(bestSeg, bestSnap, rem, total);
}

/// Nejbližší bod na úsečce a-b k bodu p (lokální rovinná aproximace v metrech).
LatLng _closestOnSeg(LatLng a, LatLng b, LatLng p) {
  const mPerLat = 111320.0;
  final mPerLng = 111320.0 * math.cos(a.latitude * math.pi / 180);
  final bx = (b.longitude - a.longitude) * mPerLng;
  final by = (b.latitude - a.latitude) * mPerLat;
  final px = (p.longitude - a.longitude) * mPerLng;
  final py = (p.latitude - a.latitude) * mPerLat;
  final len2 = bx * bx + by * by;
  double t = len2 == 0 ? 0 : (px * bx + py * by) / len2;
  t = t.clamp(0.0, 1.0);
  final sx = t * bx, sy = t * by;
  return LatLng(a.latitude + sy / mPerLat, a.longitude + sx / mPerLng);
}

/// Kompas — ukazuje sever; klik vrátí mapu na sever.
class _CompassButton extends StatelessWidget {
  final double rotationDeg;
  final VoidCallback onTap;
  const _CompassButton({required this.rotationDeg, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: MotoGoShadows.cardSmall,
        ),
        child: Transform.rotate(
          angle: rotationDeg * math.pi / 180,
          child: const Icon(Icons.navigation, size: 22, color: Color(0xFFD93636)),
        ),
      ),
    );
  }
}

/// Pilulka „příští bod zájmu" + vzdálenost.
class _NextPoiPill extends StatelessWidget {
  final String name;
  final double distanceM;
  const _NextPoiPill({required this.name, required this.distanceM});

  @override
  Widget build(BuildContext context) {
    final d = distanceM >= 1000
        ? '${(distanceM / 1000).toStringAsFixed(1)} km'
        : '${distanceM.round()} m';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoRadius.pill),
        boxShadow: MotoGoShadows.cardSmall,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.place, size: 15, color: MotoGoColors.greenDark),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              '${t(context).tr('routeNavNext')}: $name · $d',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: MotoGoTypo.sizeMd,
                  fontWeight: MotoGoTypo.w700,
                  color: MotoGoColors.black,
                  decoration: TextDecoration.none),
            ),
          ),
        ],
      ),
    );
  }
}

/// Spodní HUD navigace — velký tachometr + zbývá / čas / příjezd / výška + progress.
class _NavHud extends StatelessWidget {
  final double? remainingM;
  final double speedKmh;
  final double? altitude;
  final double fraction;
  const _NavHud({
    required this.remainingM,
    required this.speedKmh,
    required this.altitude,
    required this.fraction,
  });

  @override
  Widget build(BuildContext context) {
    final arrived = remainingM != null && remainingM! < 40;
    final remTxt = remainingM == null
        ? '–'
        : (remainingM! >= 1000
            ? '${(remainingM! / 1000).toStringAsFixed(1)} km'
            : '${remainingM!.round()} m');
    // ETA: jede-li jezdec rozumně rychle, počítej z aktuální rychlosti, jinak
    // odhad 50 km/h (vedlejší silnice).
    String etaTxt = '–';
    String arrTxt = '–';
    if (remainingM != null) {
      final mPerS = speedKmh > 8 ? speedKmh / 3.6 : 50 / 3.6;
      final mins = (remainingM! / mPerS / 60).round();
      etaTxt = mins < 1 ? '<1 min' : (mins >= 60 ? '${mins ~/ 60} h ${mins % 60} min' : '$mins min');
      final arr = DateTime.now().add(Duration(minutes: mins));
      arrTxt = '${arr.hour.toString().padLeft(2, '0')}:${arr.minute.toString().padLeft(2, '0')}';
    }
    final altTxt = altitude == null ? '–' : '${altitude!.round()} m';

    return Container(
      margin: EdgeInsets.fromLTRB(12, 0, 12, MediaQuery.of(context).padding.bottom + 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoRadius.card),
        boxShadow: MotoGoShadows.cardSmall,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress trasy.
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 5,
              backgroundColor: MotoGoColors.g200,
              valueColor: const AlwaysStoppedAnimation(MotoGoColors.greenDark),
            ),
          ),
          const SizedBox(height: 12),
          arrived
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    t(context).tr('routeNavArrived'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: MotoGoTypo.sizeH3,
                        fontWeight: MotoGoTypo.w900,
                        color: MotoGoColors.greenDarker,
                        decoration: TextDecoration.none),
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _speedBlock(),
                    Container(width: 1, height: 56, color: MotoGoColors.g200),
                    Expanded(
                      child: Column(
                        children: [
                          Row(children: [
                            _stat(Icons.flag_outlined, remTxt, t(context).tr('routeNavRemaining')),
                            _stat(Icons.schedule, etaTxt, t(context).tr('routeNavEta')),
                          ]),
                          const SizedBox(height: 10),
                          Row(children: [
                            _stat(Icons.access_time_filled, arrTxt, t(context).tr('routeNavArrival')),
                            _stat(Icons.terrain, altTxt, t(context).tr('routeNavAltitude')),
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),
        ],
      ),
    );
  }

  Widget _speedBlock() => Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${speedKmh.round()}',
              style: const TextStyle(
                  fontSize: 34,
                  height: 1.0,
                  fontWeight: MotoGoTypo.w900,
                  color: MotoGoColors.black,
                  decoration: TextDecoration.none),
            ),
            const Text(
              'km/h',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: MotoGoTypo.w700,
                  color: MotoGoColors.g500,
                  decoration: TextDecoration.none),
            ),
          ],
        ),
      );

  Widget _stat(IconData icon, String value, String label) => Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: MotoGoColors.greenDark),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: MotoGoTypo.sizeLg,
                        fontWeight: MotoGoTypo.w900,
                        color: MotoGoColors.black,
                        decoration: TextDecoration.none),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: MotoGoTypo.w600,
                  color: MotoGoColors.g500,
                  decoration: TextDecoration.none),
            ),
          ],
        ),
      );
}

/// Modrý marker aktuální polohy se šipkou směru jízdy.
class _MeMarker extends StatelessWidget {
  final double? arrowDeg; // směr šipky na obrazovce (stupně, po směru hod. ručiček)
  const _MeMarker({this.arrowDeg});

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2563EB),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withValues(alpha: 0.5), blurRadius: 8)],
      ),
    );
    if (arrowDeg == null) return dot;
    return Transform.rotate(
      angle: arrowDeg! * math.pi / 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned(top: 0, child: Icon(Icons.navigation, size: 16, color: Color(0xFF2563EB))),
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withValues(alpha: 0.5), blurRadius: 8)],
            ),
          ),
        ],
      ),
    );
  }
}

class _NumPin extends StatelessWidget {
  final int index;
  const _NumPin({required this.index});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MotoGoColors.greenDarker,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Center(
        child: Text('${index + 1}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white, decoration: TextDecoration.none)),
      ),
    );
  }
}
