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
import '../../core/supabase_client.dart';
import 'routes_model.dart';
import 'routes_provider.dart';
import 'route_poi_sheet.dart';
import 'route_nav_widgets.dart';
import 'route_reviews.dart';
import 'my_experiences_provider.dart';

/// Navigace trasy PŘÍMO v aplikaci — plnohodnotný navigátor: fullscreen mapa
/// Mapy.com, živá poloha jezdce, sledování (follow) s otáčením mapy po směru
/// jízdy (heading-up), projetá část trasy se odečítá (šedne) a HUD ukazuje
/// rychlost, zbývající vzdálenost PO TRASE, čas dojezdu, čas příjezdu a
/// nadmořskou výšku.
///
/// REAL-TIME chování:
/// - vybočení z trasy → trasa se do pár vteřin PŘEPOČÍTÁ od aktuální polohy,
/// - dojezd na zastávku/bod zájmu → bod se odškrtne, místo se označí jako
///   OBJEVENÉ (Moje zážitky) a karta nabídne navigaci na DALŠÍ bod trasy
///   (nebo výběr jiného bodu),
/// - projeté průjezdní body se odečítají automaticky (reroute je nevrací),
/// - po dokončení trasy nabídne hodnocení / uložení vlastní vyjížďky.
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

/// Zastávka trasy pro navigaci — waypoint, případně s přiřazeným bodem zájmu.
class _NavStop {
  final LatLng point;
  String? label;
  RoutePoi? poi;
  bool reached = false;
  _NavStop(this.point, {this.label, this.poi});
}

class _RouteNavigationScreenState extends ConsumerState<RouteNavigationScreen> {
  // Pod touto rychlostí (km/h) je GPS heading nespolehlivý → mapou neotáčíme.
  static const double _moveThreshold = 5;
  // Vybočení z trasy: dál než [_kOffRouteM] po [_kOffRouteFixes] po sobě
  // jdoucích GPS fixech → přepočet trasy od aktuální polohy.
  static const double _kOffRouteM = 70;
  static const int _kOffRouteFixes = 3;
  // Min. rozestup mezi automatickými přepočty (šetří API i baterii).
  static const Duration _kRerouteCooldown = Duration(seconds: 8);
  // Dojezd na zastávku / objevení bodu zájmu (metry vzdušně).
  static const double _kReachM = 150;
  static const double _kPoiVisitM = 200;
  // Průjezdní bod je „projetý", když jsem po trase dál než bod + rezerva.
  static const double _kPassedSlackM = 400;

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
  double _zoomBias = 0; // ruční doladění zoomu (tlačítka +/−)
  double _zoomSpeed = 0; // vyhlazená rychlost pro adaptivní zoom (proti blikání)

  /// Adaptivní zoom podle rychlosti: pomalu (obec, odbočka, sjezd) → blíž,
  /// rychle (silnice, dálnice) → dál. Plus ruční bias z tlačítek +/−.
  double _targetZoom(double kmh) {
    double z;
    if (kmh < 5) {
      z = 17.0; // stojím / pomalu (křižovatka, sjezd)
    } else if (kmh < 30) {
      z = 16.7; // obec
    } else if (kmh < 55) {
      z = 15.8; // okreska
    } else if (kmh < 85) {
      z = 14.8; // silnice
    } else {
      z = 13.8; // rychle / dálnice
    }
    return (z + _zoomBias).clamp(10.0, 18.5);
  }

  // Živá trasa od aktuální polohy — dle zvoleného profilu (Mapy.com routing).
  RouteItem? _route;
  RouteBranch? _branch;
  List<LatLng>? _navGeo;
  bool _navLoading = false;
  bool _rerouting = false; // přepočet po vybočení (odlišný text ve stavové liště)
  double? _navLengthM; // reálná délka aktuální trasy (pro přesné ETA)
  int? _navDurationS; // reálný čas jízdy z routingu

  // Zastávky trasy + průběh.
  final List<_NavStop> _stops = [];
  bool _stopsBuilt = false;
  final Map<_NavStop, double?> _stopAlongM = {}; // pozice zastávky po trase (cache)
  int _offRouteFixes = 0;
  DateTime? _lastRerouteAt;

  // Objevování míst + karty.
  final Set<String> _visitSent = {}; // POI, pro které už šel zápis návštěvy
  VisitResult? _lastVisit; // výsledek posledního zápisu (badge na kartě)
  _NavStop? _reachedCard; // právě dosažená zastávka (karta s dalším bodem)
  bool _routeDone = false;
  bool _doneCardDismissed = false;
  Timer? _cardTimer;

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
    _zoomSpeed = _zoomSpeed * 0.7 + spd * 0.3;

    setState(() {
      _me = me;
      _heading = hdg;
      _speedKmh = spd;
      _altitude = alt;
    });

    // Sledování polohy + adaptivní zoom + (volitelně) otáčení po směru jízdy.
    final wantRot = _follow && _headingUp && moving;
    final rot = wantRot ? -_smoothHeading : _mapRot;
    final z = _targetZoom(_zoomSpeed);
    if (_firstFix) {
      _firstFix = false;
      _ctrl.moveAndRotate(me, z, rot);
      _mapRot = rot;
    } else if (_follow) {
      if (wantRot) {
        _ctrl.moveAndRotate(me, z, rot);
        _mapRot = rot;
      } else {
        _ctrl.move(me, z);
      }
    }
    _updateProgress(me);
  }

  // ── Real-time průběh: zastávky, objevování, off-route reroute ──

  void _updateProgress(LatLng me) {
    final route = _route;
    if (route == null) return;
    if (_stopsBuilt) _checkStops(me, route);

    final geo = _navGeo;
    if (geo == null || geo.length < 2) {
      _maybeComputeNav();
      return;
    }
    final prog = _projectOnRoute(geo, me);
    if (prog == null) return;
    if (prog.distM > _kOffRouteM) {
      // Mimo trasu — po několika fixech přepočítej od aktuální polohy.
      _offRouteFixes++;
      if (_offRouteFixes >= _kOffRouteFixes) _reroute();
    } else {
      _offRouteFixes = 0;
      _autoPassStops(prog);
    }
  }

  /// Dojezd na zastávky + objevení bodů zájmu (vzdušná vzdálenost).
  void _checkStops(LatLng me, RouteItem route) {
    const dist = Distance();
    // 1) Objevení bodů zájmu — nezávisle na zastávkách (Moje zážitky).
    for (final poi in route.pois) {
      final ll = poi.latLng;
      if (ll == null || poi.id.isEmpty || _visitSent.contains(poi.id)) continue;
      if (dist.as(LengthUnit.Meter, me, ll) <= _kPoiVisitM) {
        _visitSent.add(poi.id);
        _recordVisit(poi);
      }
    }
    // 2) Dojezd na zastávky trasy.
    var changed = false;
    for (final s in _stops) {
      if (s.reached) continue;
      if (dist.as(LengthUnit.Meter, me, s.point) <= _kReachM) {
        s.reached = true;
        changed = true;
        // Karta „dojel jsi" jen u pojmenované zastávky / bodu zájmu —
        // bezejmenné průjezdní body se odškrtávají potichu.
        if (s.poi != null || (s.label ?? '').isNotEmpty) _showReachedCard(s);
      }
    }
    if (changed) {
      if (_stops.isNotEmpty && _stops.every((x) => x.reached) && !_routeDone) {
        _routeDone = true;
        _reachedCard = null;
        _cardTimer?.cancel();
      }
      setState(() {});
    }
  }

  /// Zapíše objevené místo (best-effort, nesmí rušit navigaci).
  Future<void> _recordVisit(RoutePoi poi) async {
    final res = await markPlaceVisited(poi, routeId: widget.routeId);
    if (!mounted || res == null) return;
    setState(() => _lastVisit = res);
  }

  void _showReachedCard(_NavStop s) {
    _cardTimer?.cancel();
    _lastVisit = null; // badge dorazí async z _recordVisit
    _reachedCard = s;
    _cardTimer = Timer(const Duration(seconds: 45), () {
      if (mounted) setState(() => _reachedCard = null);
    });
  }

  /// Průjezdní body, které jsem po trase minul (jsem po trase DÁL než bod),
  /// odškrtni automaticky — přepočet trasy se k nim už nevrací.
  void _autoPassStops(_RouteProgress prog) {
    final riderAlong = prog.totalM - prog.remainingM;
    var changed = false;
    for (final s in _stops) {
      if (s.reached) continue;
      final along = _stopAlongM[s];
      if (along == null) continue; // zastávka mimo aktuální polyline
      if (along < riderAlong - _kPassedSlackM) {
        s.reached = true;
        changed = true;
      }
    }
    if (changed) setState(() {});
  }

  /// První výpočet živé trasy od polohy jezdce přes zastávky trasy.
  Future<void> _maybeComputeNav() async {
    if (_navLoading || _navGeo != null) return;
    final me = _me;
    final route = _route;
    if (me == null || route == null) return;
    _buildStops(route);
    final pts = _routingPoints(me);
    if (pts.length < 2) return;
    _navLoading = true;
    final info = await fetchMapyRouteInfo(pts, profile: widget.profile);
    if (!mounted) {
      _navLoading = false;
      return;
    }
    setState(() {
      _applyNavInfo(info, fallback: pts);
      _navLoading = false;
    });
  }

  /// Přepočet trasy od aktuální polohy přes NEprojeté zastávky. Throttlované
  /// (cooldown), `force` = vyžádané uživatelem (tlačítko další bod / výběr).
  Future<void> _reroute({bool force = false}) async {
    final me = _me;
    if (me == null || _navLoading) return;
    final now = DateTime.now();
    if (!force &&
        _lastRerouteAt != null &&
        now.difference(_lastRerouteAt!) < _kRerouteCooldown) {
      return;
    }
    final pts = _routingPoints(me);
    if (pts.length < 2) return;
    _lastRerouteAt = now;
    setState(() {
      _navLoading = true;
      _rerouting = true;
    });
    final info = await fetchMapyRouteInfo(pts, profile: widget.profile);
    if (!mounted) return;
    setState(() {
      if (info != null && info.geometry.length >= 2) {
        _applyNavInfo(info, fallback: pts);
      }
      _navLoading = false;
      _rerouting = false;
      _offRouteFixes = 0;
    });
  }

  List<LatLng> _routingPoints(LatLng me) {
    final pts = <LatLng>[me];
    for (final s in _stops) {
      if (!s.reached) pts.add(s.point);
    }
    return pts;
  }

  void _applyNavInfo(MapyRouteInfo? info, {required List<LatLng> fallback}) {
    final geo = (info != null && info.geometry.length >= 2) ? info.geometry : fallback;
    _navGeo = geo;
    _navLengthM = info?.lengthM ?? polylineLengthM(geo);
    _navDurationS = info?.durationS;
    _computeStopAlong(geo);
  }

  /// Pozice každé neprojeté zastávky PO TRASE (metry od startu) — cache pro
  /// levné auto-odškrtávání projetých bodů při každém GPS fixu.
  void _computeStopAlong(List<LatLng> geo) {
    _stopAlongM.clear();
    if (geo.length < 2) return;
    for (final s in _stops) {
      if (s.reached) continue;
      final p = _projectOnRoute(geo, s.point);
      _stopAlongM[s] =
          (p != null && p.distM <= 120) ? (p.totalM - p.remainingM) : null;
    }
  }

  /// Zastávky trasy: waypointy (jinak body zájmu) + u okruhu návrat na pobočku.
  /// Bodům zájmu se přiřadí odpovídající zastávka (≤ 40 m).
  void _buildStops(RouteItem route) {
    if (_stopsBuilt) return;
    _stopsBuilt = true;
    final pts = <LatLng>[];
    if (route.waypoints.isNotEmpty) {
      pts.addAll(route.waypoints);
    } else {
      for (final p in route.pois) {
        final ll = p.latLng;
        if (ll != null) pts.add(ll);
      }
    }
    for (final p in pts) {
      if (_stops.isEmpty ||
          _stops.last.point.latitude != p.latitude ||
          _stops.last.point.longitude != p.longitude) {
        _stops.add(_NavStop(p));
      }
    }
    // Okruh se vrací na pobočku jen když je poblíž trasy — u vzdálené
    // (zahraniční) trasy se návrat přes půl Evropy neplánuje.
    if (route.isLoop && startIsNearRoute(route, _branch?.latLng)) {
      final b = _branch?.latLng;
      if (b != null) _stops.add(_NavStop(b, label: _branch?.name));
    }
    const dist = Distance();
    for (final poi in route.pois) {
      final ll = poi.latLng;
      if (ll == null) continue;
      _NavStop? best;
      double bestM = 40;
      for (final s in _stops) {
        if (s.poi != null) continue;
        final d = dist.as(LengthUnit.Meter, ll, s.point);
        if (d < bestM) {
          bestM = d;
          best = s;
        }
      }
      if (best != null) {
        best.poi = poi;
        best.label ??= poi.name;
      }
    }
  }

  _NavStop? get _nextStop {
    for (final s in _stops) {
      if (!s.reached) return s;
    }
    return null;
  }

  String _stopLabel(_NavStop s, String lang) {
    final poi = s.poi;
    if (poi != null) return poi.nameFor(lang);
    if ((s.label ?? '').isNotEmpty) return s.label!;
    final i = _stops.indexOf(s);
    return '${t(context).tr('routeBuilderStop')} ${i + 1}';
  }

  // ── Akce z karty dojezdu / sheetu zastávek ──

  void _goToNextStop() {
    _cardTimer?.cancel();
    setState(() => _reachedCard = null);
    _reroute(force: true);
  }

  /// Navigovat rovnou na zvolenou zastávku — dřívější nedojeté body se přeskočí.
  void _navigateToStop(int index) {
    if (index < 0 || index >= _stops.length) return;
    _cardTimer?.cancel();
    setState(() {
      for (var i = 0; i < index; i++) {
        _stops[i].reached = true;
      }
      _reachedCard = null;
    });
    _reroute(force: true);
  }

  void _openStopsSheet(String lang) {
    if (_stops.isEmpty) return;
    final next = _nextStop;
    final views = <NavStopView>[];
    for (var i = 0; i < _stops.length; i++) {
      final s = _stops[i];
      views.add(NavStopView(
        index: i,
        label: _stopLabel(s, lang),
        reached: s.reached,
        isNext: identical(s, next),
        hasPoi: s.poi != null,
      ));
    }
    showNavStopsSheet(context, stops: views, onNavigateTo: _navigateToStop);
  }

  /// Uložení vlastní vyjížďky do Mých tras (po dokončení navigace).
  Future<void> _saveCustomRoute() async {
    final route = _route;
    if (route == null) return;
    if (MotoGoSupabase.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(context).tr('routeSaveLogin'))));
      return;
    }
    final nameCtrl = TextEditingController(
        text: route.name.isNotEmpty ? route.name : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (dc) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(t(dc).tr('routeSaveTitle'),
            style: const TextStyle(
                fontSize: MotoGoTypo.sizeH3, fontWeight: MotoGoTypo.w900)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: InputDecoration(labelText: t(dc).tr('routeSaveName')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dc, false),
              child: Text(t(dc).tr('routesFilterClear'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: MotoGoColors.green,
                foregroundColor: MotoGoColors.black),
            onPressed: () => Navigator.pop(dc, true),
            child: Text(t(dc).tr('routeSaveBtn')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    final waypoints = <Map<String, dynamic>>[];
    final poiRefs = <Map<String, dynamic>>[];
    for (var i = 0; i < _stops.length; i++) {
      final s = _stops[i];
      waypoints.add({
        'lat': s.point.latitude,
        'lng': s.point.longitude,
        'label': (s.label ?? '').isEmpty ? null : s.label,
        'order': i,
      });
      final poi = s.poi;
      if (poi != null && poi.id.isNotEmpty) {
        poiRefs.add({
          'order': i,
          'kind': poi.isUserPoi ? 'user' : (poi.isCatalogPoi ? 'catalog' : 'route'),
          'id': poi.id,
          'name': poi.name,
          'lat': poi.lat,
          'lng': poi.lng,
          'image_url': poi.imageUrl,
        });
      }
    }
    final saved = await saveUserRoute(
      name: name,
      sourceRouteId: widget.routeId,
      waypoints: waypoints,
      poiRefs: poiRefs,
      profile: widget.profile,
      distanceKm:
          _navLengthM == null ? null : double.parse((_navLengthM! / 1000).toStringAsFixed(1)),
      durationMin: _navDurationS == null ? null : (_navDurationS! / 60).round(),
    );
    if (!mounted) return;
    ref.invalidate(mySavedRoutesProvider);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t(context).tr(saved ? 'routeSaved' : 'routeSaveErr'))));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _cardTimer?.cancel();
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
    final z = _targetZoom(_speedKmh);
    if (moving) {
      _mapRot = -_smoothHeading;
      _ctrl.moveAndRotate(me, z, _mapRot);
    } else {
      _ctrl.move(me, z);
    }
  }

  /// Ruční zoom (tlačítka +/−). Ve follow režimu posune bias adaptivního zoomu
  /// (drží se i při jízdě), jinak jen přiblíží aktuální výřez.
  void _zoomBy(double d) {
    if (_follow && _me != null) {
      setState(() => _zoomBias = (_zoomBias + d).clamp(-3.0, 4.0));
      _ctrl.move(_me!, _targetZoom(_speedKmh));
    } else {
      final c = _ctrl.camera;
      _ctrl.move(c.center, (c.zoom + d).clamp(3.0, 19.0));
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
          // Po prvním GPS fixu navigujeme po živé trase od polohy jezdce.
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
            child: NavNumPin(index: idx, visited: _visitSent.contains(poi.id)),
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
    // Přesné ETA z routingu, škálované na zbytek trasy.
    double? etaMin;
    if (prog != null &&
        _navGeo != null &&
        _navLengthM != null &&
        _navLengthM! > 0 &&
        _navDurationS != null) {
      etaMin = _navDurationS! / 60 * (prog.remainingM / _navLengthM!);
    }

    // Příští zastávka trasy (odškrtává se průjezdem) — pilulka nad HUD.
    final next = _nextStop;
    final reachedCount = _stops.where((s) => s.reached).length;
    double? nextDistM;
    if (next != null && _me != null) {
      nextDistM = const Distance().as(LengthUnit.Meter, _me!, next.point);
    }

    final initialCenter = _me ??
        (geometry.isNotEmpty ? geometry.first : null) ??
        branch?.latLng ??
        const LatLng(49.3464, 15.2119);

    final showDoneCard = _routeDone && !_doneCardDismissed;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            mapController: _ctrl,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: _me != null ? _targetZoom(_speedKmh) : 13,
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
                    Polyline(points: doneGeo, strokeWidth: 3.5, color: MotoGoColors.g400.withValues(alpha: 0.5)),
                  ],
                ),
              // Zbývající část — výrazná zelená s jemným tmavým podkladem.
              if (aheadGeo.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(points: aheadGeo, strokeWidth: 6, color: MotoGoColors.dark.withValues(alpha: 0.22)),
                    Polyline(points: aheadGeo, strokeWidth: 4, color: MotoGoColors.greenDark),
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
                    child: NavMeMarker(
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

        // Horní lišta — zpět + název trasy + seznam zastávek
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
                _circleBtn(Icons.arrow_back, () => context.backOr(
                    widget.routeId != null ? '/routes/${widget.routeId}' : '/routes')),
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
                        _statusLine(context),
                        style: const TextStyle(fontSize: 12, fontWeight: MotoGoTypo.w600, color: Color(0xFF8AAB99), decoration: TextDecoration.none),
                      ),
                    ],
                  ),
                ),
                if (_stops.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _openStopsSheet(lang),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(MotoGoRadius.lg),
                        boxShadow: MotoGoShadows.cardSmall,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.checklist, size: 18, color: MotoGoColors.greenDarker),
                          const SizedBox(width: 4),
                          Text(
                            '$reachedCount/${_stops.length}',
                            style: const TextStyle(
                                fontSize: MotoGoTypo.sizeMd,
                                fontWeight: MotoGoTypo.w800,
                                color: MotoGoColors.black,
                                decoration: TextDecoration.none),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Kompas — objeví se, když je mapa otočená; klik = zpět na sever.
        if (_mapRot.abs() > 1)
          Positioned(
            top: MediaQuery.of(context).padding.top + 64,
            right: 16,
            child: NavCompassButton(rotationDeg: _mapRot, onTap: _resetNorth),
          ),

        // Banner při zamítnuté poloze
        if (_denied)
          Positioned(
            left: 16, right: 16, bottom: bottomInset + 134,
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

        // Karta dojezdu na bod / dokončení trasy — má přednost před pilulkou.
        if (_reachedCard != null)
          Positioned(
            left: 12, right: 64, bottom: bottomInset + 134,
            child: StopReachedCard(
              name: _stopLabel(_reachedCard!, lang),
              visit: _lastVisit,
              nextLabel: next == null ? null : _stopLabel(next, lang),
              onNext: _goToNextStop,
              onChoose: () => _openStopsSheet(lang),
              onClose: () {
                _cardTimer?.cancel();
                setState(() => _reachedCard = null);
              },
            ),
          )
        else if (showDoneCard)
          Positioned(
            left: 12, right: 64, bottom: bottomInset + 134,
            child: RouteDoneCard(
              canRate: widget.routeId != null,
              canSave: widget.routeId == null,
              onRate: () {
                setState(() => _doneCardDismissed = true);
                showRouteReviewsSheet(context,
                    routeId: route.id, routeName: route.nameFor(lang));
              },
              onSave: () {
                setState(() => _doneCardDismissed = true);
                _saveCustomRoute();
              },
              onClose: () => setState(() => _doneCardDismissed = true),
            ),
          )
        // Příští zastávka trasy — pilulka nad HUD (klik = seznam zastávek).
        else if (next != null && !_denied)
          Positioned(
            left: 16, right: 72, bottom: bottomInset + 134,
            child: Align(
              alignment: Alignment.centerLeft,
              child: NavNextStopPill(
                name: _stopLabel(next, lang),
                distanceM: nextDistM,
                progress: '${reachedCount + 1}/${_stops.length}',
                onTap: () => _openStopsSheet(lang),
              ),
            ),
          ),

        // Ovládání mapy — zoom +/− a recenter (nad spodním HUD)
        Positioned(
          right: 16, bottom: bottomInset + 134,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _mapBtn(Icons.add, () => _zoomBy(0.8)),
              const SizedBox(height: 8),
              _mapBtn(Icons.remove, () => _zoomBy(-0.8)),
              const SizedBox(height: 14),
              FloatingActionButton(
                heroTag: 'route-nav-recenter',
                mini: true,
                backgroundColor: _follow ? MotoGoColors.greenDark : Colors.white,
                foregroundColor: _follow ? Colors.white : MotoGoColors.greenDark,
                onPressed: _recenter,
                child: const Icon(Icons.navigation_outlined),
              ),
            ],
          ),
        ),

        // Spodní HUD — rychlost / zbývá / čas / příjezd / výška + progress
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: NavHud(
            remainingM: prog?.remainingM,
            speedKmh: _speedKmh,
            altitude: _altitude,
            fraction: fraction,
            etaMinutes: etaMin,
          ),
        ),
      ],
    );
  }

  String _statusLine(BuildContext context) {
    if (_locating) return t(context).tr('routeNavLocating');
    if (_navLoading) {
      return t(context).tr(_rerouting ? 'routeNavRerouting' : 'routeNavComputing');
    }
    if (_offRouteFixes >= _kOffRouteFixes) return t(context).tr('routeNavOffRoute');
    return t(context).tr('routeNavTitle');
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

  Widget _mapBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: MotoGoShadows.cardSmall,
          ),
          child: Icon(icon, size: 22, color: MotoGoColors.greenDarker),
        ),
      );

  Widget _exit(BuildContext context) => Center(
        child: ElevatedButton(
          onPressed: () => context.backOr('/routes'),
          child: Text(t(context).tr('routeNotFound')),
        ),
      );
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
  final double distM; // vzdálenost polohy od trasy (off-route detekce)
  const _RouteProgress(
      this.segIndex, this.snapped, this.remainingM, this.totalM, this.distM);
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
  return _RouteProgress(bestSeg, bestSnap, rem, total, best);
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
