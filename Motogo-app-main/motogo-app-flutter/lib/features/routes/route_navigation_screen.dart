import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/theme.dart';
import '../../core/router.dart' show MotoGoBackNav;
import '../../core/i18n/i18n_provider.dart';
import '../../core/native/gps_service.dart';
import '../../core/supabase_client.dart';
import 'active_ride_provider.dart';
import 'routes_model.dart';
import 'routes_provider.dart';
import 'route_nav_loop.dart';
import 'route_nav_motion.dart';
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
/// - dojezd na zastávku/bod zájmu → vyskočí potvrzovací karta (hvězdičky +
///   komentář + Pokračovat); bod se odškrtne AŽ ručním potvrzením — NIKDY
///   sám. Potvrzením se místo označí jako OBJEVENÉ (Moje zážitky),
/// - bezejmenné průjezdní body (jen tvar trasy) se odbavují potichu,
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
  final bool isBranch; // návrat na pobočku MotoGo24 (aktivuje se ručně)
  _NavStop(this.point, {this.label, this.poi, this.isBranch = false});
}

class _RouteNavigationScreenState extends ConsumerState<RouteNavigationScreen>
    with SingleTickerProviderStateMixin {
  // Pod touto rychlostí (km/h) je GPS heading nespolehlivý → mapou neotáčíme.
  static const double _moveThreshold = 5;
  // Vybočení z trasy: dál než [_kOffRouteM] po [_kOffRouteFixes] po sobě
  // jdoucích GPS fixech → okamžitý přepočet trasy od aktuální polohy.
  static const double _kOffRouteM = 70;
  static const int _kOffRouteFixes = 2;
  // Jízda PROTI směru trasy (jsem na lince, ale jedu opačně) → přepočet
  // hned po [_kWrongWayFixes] detekcích — linka se nesmí držet stará.
  static const int _kWrongWayFixes = 2;
  // Mapy.com routing zvládá omezený počet průjezdních bodů — delší trasy se
  // počítají po okně; vzdálenější zastávky se přidají po dojezdu dřívějších.
  static const int _kMaxRoutingStops = 15;
  // Min. rozestup mezi automatickými přepočty (šetří API i baterii).
  static const Duration _kRerouteCooldown = Duration(seconds: 8);
  // Dojezd na zastávku (metry vzdušně) → potvrzovací karta.
  static const double _kReachM = 150;
  // Průjezdní bod je „projetý", když jsem po trase dál než bod + rezerva.
  static const double _kPassedSlackM = 400;

  final MapController _ctrl = MapController();
  // MapController je použitelný AŽ po vykreslení FlutterMap (onMapReady) —
  // GPS fix může přijít dřív (data trasy se ještě načítají a mapa není
  // v tree) a pohyb kamery by spadl na LateInitializationError.
  bool _mapReady = false;
  StreamSubscription<Position>? _sub;
  // Zobrazovaná (animovaná) poloha — plynule se blíží k predikované cílové
  // poloze; surový GPS fix je v [_fix]. Zbytek obrazovky pracuje s [_me].
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
  double _animZoom = 15; // plynule dopočítávaný zoom (žádné skoky mezi stupni)

  // Poslední GPS fix + jeho projekce na zobrazenou trasu (pro predikci).
  LatLng? _fix;
  DateTime? _fixAt;
  double _fixSpeedMps = 0;
  double? _fixAlongM; // pozice fixu PO TRASE (metry od startu polyline)
  double _fixSnapDistM = double.infinity; // kolmá vzdálenost fixu od trasy

  // Animační smyčka (per-frame interpolace polohy, rotace a zoomu).
  Ticker? _ticker;
  Duration _lastElapsed = Duration.zero;

  // Cache geometrií: zobrazená polyline + živá navigační polyline.
  RouteGeoCache? _dispCache; // geometrie právě vykreslené trasy
  RouteGeoCache? _dispBase; // cache pro základní (ne-nav) geometrii
  List<LatLng>? _dispSrc;
  int? _dispSegHint; // okno pro levnou projekci (poslední segment)
  RouteGeoCache? _navCache; // geometrie z routingu (_navGeo)
  int? _navSegHint;
  double? _riderAlongM; // postup jezdce po navigační trase (metry)

  // Cache projekce PŘÍŠTÍHO navigovaného bodu na zobrazenou polyline —
  // ořez zelené linky (počítá se jen při změně bodu / geometrie, ne každý frame).
  _NavStop? _clipStop;
  RouteGeoCache? _clipCache;
  double? _clipAlongM;

  // Projetá cesta (vzorky à ~30 m) — koridor pro „nejezdi zpátky po stejné
  // silnici": při přepočtu se nový nájezd porovnává s tím, kudy jezdec přijel.
  final List<LatLng> _traveled = [];

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
  int _wrongWayFixes = 0;
  DateTime? _lastRerouteAt;

  // Objevování míst + karty.
  final Set<String> _visitSent = {}; // POI, pro které už šel zápis návštěvy
  final Set<_NavStop> _prompted = {}; // zastávky s už vyskočenou potvrzovací kartou
  VisitResult? _lastVisit; // výsledek posledního zápisu (badge na kartě)
  _NavStop? _reachedCard; // dosažená zastávka čekající na RUČNÍ potvrzení
  bool _routeDone = false;
  bool _doneCardDismissed = false;

  // Persistence rozjeté jízdy (přežije zavření appky; ruší se jen křížkem).
  bool _rideSynced = false;

  @override
  void initState() {
    super.initState();
    // Během navigace se displej NIKDY nesmí vypnout (Android i iOS).
    WakelockPlus.enable();
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

  /// Nový GPS fix: uloží se surová poloha + její projekce na trasu. Zobrazení
  /// NEskáče — fix jen potvrdí/zkoriguje predikovanou polohu a animační
  /// smyčka [_onTick] k ní marker plynule dovede.
  void _onPosition(Position pos) {
    if (!mounted) return;
    final fix = LatLng(pos.latitude, pos.longitude);
    final hdg = (pos.heading >= 0 && pos.heading <= 360) ? pos.heading : null;
    final spd = pos.speed.isFinite && pos.speed > 0 ? pos.speed * 3.6 : 0.0;
    final alt = pos.altitude.isFinite && pos.altitude != 0 ? pos.altitude : null;

    _fix = fix;
    _fixAt = DateTime.now();
    _fixSpeedMps = spd / 3.6;
    _heading = hdg;
    _speedKmh = spd;
    _altitude = alt;
    _zoomSpeed = _zoomSpeed * 0.7 + spd * 0.3;

    // Snap fixu na zobrazenou polyline — potvrzení / korekce predikce.
    final cache = _dispCache;
    if (cache != null) {
      final p = cache.project(fix, hintSeg: _dispSegHint);
      _dispSegHint = p.segIndex;
      _fixAlongM = p.alongM;
      _fixSnapDistM = p.distM;
    } else {
      _fixAlongM = null;
      _fixSnapDistM = double.infinity;
    }

    // Záznam projeté cesty (po trase snapnuté, jinak surový fix).
    final rec = (_onRouteNow && cache != null && _fixAlongM != null)
        ? cache.pointAt(_fixAlongM!)
        : fix;
    if (_traveled.isEmpty ||
        const Distance().as(LengthUnit.Meter, _traveled.last, rec) >= 30) {
      _traveled.add(rec);
      if (_traveled.length > 400) _traveled.removeAt(0);
    }

    if (_firstFix) {
      _firstFix = false;
      _me = _onRouteNow && cache != null && _fixAlongM != null
          ? cache.pointAt(_fixAlongM!)
          : fix;
      _animZoom = _targetZoom(_zoomSpeed);
      final moving = spd > _moveThreshold && hdg != null;
      if (moving) _smoothHeading = hdg!;
      _mapRot = _follow && _headingUp && moving ? -_smoothHeading : 0.0;
      if (_mapReady) _ctrl.moveAndRotate(_me!, _animZoom, _mapRot);
      setState(() {});
    }
    _ticker ??= createTicker(_onTick)..start();
    _updateProgress(fix);
  }

  /// Jedu po trase? (fix je dost blízko polyline pro snap + predikci)
  bool get _onRouteNow => _fixSnapDistM <= 45;

  /// Směr šipky jezdce (stupně od severu): při jízdě VYHLAZENÝ reálný směr
  /// jízdy (po trase dotažený ke stabilnímu směru trasy), při stání nebo bez
  /// GPS headingu PŘEDPOKLÁDANÝ směr dle trasy, jinak poslední známý směr
  /// z projetých bodů. Šipka tak nikdy neukazuje do strany.
  double? _arrowBearing() {
    final cache = _dispCache;
    final onRoute = _onRouteNow && cache != null && _fixAlongM != null;
    final moving = _speedKmh > _moveThreshold;
    // [_smoothHeading] živí animační smyčka jen když má z čeho (GPS heading,
    // nebo segment trasy při reálné rychlosti) — jinak by byl zastaralý.
    if (moving && (_heading != null || (onRoute && _fixSpeedMps > 1.5))) {
      return _smoothHeading;
    }
    if (onRoute) {
      final routeBrg = cache.bearingAt(_fixAlongM!);
      final brg = _travelBearing();
      // Jedu-li jiným směrem, než vede trasa, má reálný směr přednost —
      // šipka se nesmí přetočit ke staré lince (do přepočtu trasy).
      if (brg != null && angleDiff(brg, routeBrg) > 100) return brg;
      return routeBrg;
    }
    return _travelBearing();
  }

  /// Cílová poloha markeru: fix promítnutý na trasu; mezi GPS fixy se
  /// PŘEDPOKLÁDÁ pokračování jízdy po trase aktuální rychlostí — další fix
  /// predikci jen potvrdí, nebo přehodnotí (koriguje). Mimo trasu drží fix.
  LatLng _predictedPosition() {
    final cache = _dispCache;
    final along = _fixAlongM;
    // Přísnější práh než [_onRouteNow]: po přepočtu začíná linka ~40 m před
    // jezdcem — marker se na ni nesmí přichytit skokem, doplyne po silnici.
    if (cache == null || along == null || _fixSnapDistM > 30) return _fix!;
    if (_fixSpeedMps < 1.5 || _fixAt == null) return cache.pointAt(along);
    // Dopředná predikce jen při jízdě VE směru trasy — v protisměru by
    // marker mezi fixy ujížděl špatným směrem a skákal zpět.
    final brg = _travelBearing();
    if (brg != null && angleDiff(brg, cache.bearingAt(along)) > 100) {
      return cache.pointAt(along);
    }
    final age = (DateTime.now().difference(_fixAt!).inMilliseconds / 1000.0)
        .clamp(0.0, 2.5);
    return cache.pointAt(along + _fixSpeedMps * age);
  }

  /// Animační smyčka: každý snímek se zobrazená poloha exponenciálně blíží
  /// k cílové (predikované), spojitě se dopočítává i směr mapy a zoom —
  /// výsledkem je plynulý pohyb bez skoků po GPS ficích.
  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _lastElapsed).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _lastElapsed = elapsed;
    if (!mounted || _fix == null || dt <= 0) return;

    final target = _predictedPosition();
    _me = _me == null ? target : lerpLatLng(_me!, target, expSmooth(dt, 4.5));

    // Směr: po trase (stabilní bearing segmentu), jinak GPS heading.
    // Bearing trasy se použije JEN když souhlasí s reálným směrem jízdy —
    // při jízdě protisměrem/jiným směrem by se mapa chaoticky přetáčela
    // mezi směrem trasy a GPS headingem tam a zpět.
    final moving = _speedKmh > _moveThreshold;
    double? desired;
    if (moving) {
      if (_onRouteNow && _dispSegHint != null && _fixSpeedMps > 1.5) {
        final segBrg = _dispCache?.segBearing(_dispSegHint!);
        if (segBrg != null &&
            (_heading == null || angleDiff(segBrg, _heading!) <= 100)) {
          desired = segBrg;
        }
      }
      desired ??= _heading;
    }
    if (desired != null) {
      _smoothHeading = lerpAngle(_smoothHeading, desired, expSmooth(dt, 4.0));
    }
    _animZoom += (_targetZoom(_zoomSpeed) - _animZoom) * expSmooth(dt, 2.5);

    if (_follow && _me != null && _mapReady) {
      if (_headingUp && moving) {
        _mapRot = -_smoothHeading;
        _ctrl.moveAndRotate(_me!, _animZoom, _mapRot);
      } else {
        _ctrl.move(_me!, _animZoom);
      }
    }
    setState(() {});
  }

  // ── Real-time průběh: zastávky, objevování, off-route reroute ──

  void _updateProgress(LatLng me) {
    final route = _route;
    if (route == null) return;
    final cache = _navCache;
    if (cache == null) {
      if (_stopsBuilt) _checkStops(me, route);
      _maybeComputeNav();
      return;
    }
    final prog = cache.project(me, hintSeg: _navSegHint);
    _navSegHint = prog.segIndex;
    _riderAlongM = prog.alongM;
    if (_stopsBuilt) _checkStops(me, route);
    if (prog.distM > _kOffRouteM) {
      // Mimo trasu — po několika fixech přepočítej od aktuální polohy.
      _offRouteFixes++;
      if (_offRouteFixes >= _kOffRouteFixes) _reroute();
    } else {
      _offRouteFixes = 0;
      _autoPassStops(prog);
      // Na lince, ale PROTI jejímu směru (otočka / jiná cesta po stejné
      // silnici) → taky přepočet, jinak zelená linka zůstane stará. Výjimka:
      // trasa tu legitimně vede oběma směry (tam a zpět ke slepému bodu).
      final brg = _travelBearing();
      if (_speedKmh > _moveThreshold &&
          brg != null &&
          angleDiff(brg, cache.bearingAt(prog.alongM)) > 120 &&
          !_hasForwardTwin(cache, me, brg)) {
        _wrongWayFixes++;
        if (_wrongWayFixes >= _kWrongWayFixes) _reroute();
      } else {
        _wrongWayFixes = 0;
      }
    }
  }

  /// Aktuální směr jízdy: GPS heading, jinak z posledních projetých bodů.
  double? _travelBearing() {
    if (_heading != null) return _heading;
    if (_traveled.length >= 2) {
      return bearingBetween(_traveled[_traveled.length - 2], _traveled.last);
    }
    return null;
  }

  /// Vede trasa poblíž [me] i SOUHLASNĚ se směrem [brg]? (úsek tam-a-zpět —
  /// jízda „proti" jedné polovině je pak v pořádku, jedu po té druhé.)
  bool _hasForwardTwin(RouteGeoCache cache, LatLng me, double brg) {
    const dist = Distance();
    for (var i = 0; i < cache.pts.length - 1; i++) {
      if (dist.as(LengthUnit.Meter, me, cache.pts[i]) > 60) continue;
      if (angleDiff(brg, cache.segBearing(i)) <= 60) return true;
    }
    return false;
  }

  /// Dojezd na zastávky trasy (vzdušná vzdálenost). Bod zájmu / pojmenovaná
  /// zastávka se NIKDY neodškrtne sama — vyskočí potvrzovací karta
  /// (hvězdičky + komentář + Pokračovat) a odškrtne se až ručně v
  /// [_confirmReached]. Bezejmenné průjezdní body se odbavují potichu.
  void _checkStops(LatLng me, RouteItem route) {
    const dist = Distance();
    // Vzdušný dojezd platí JEN pro PŘÍŠTÍ zastávku, případně pro bod, u
    // kterého jezdec je i podle postupu PO TRASE — u okruhu (start = cíl)
    // se jinak hned na startu chybně odbavil i poslední bod trasy.
    var changed = false;
    final nextIdx = _stops.indexWhere((s) => !s.reached);
    for (var i = 0; i < _stops.length; i++) {
      final s = _stops[i];
      if (s.reached) continue;
      if (dist.as(LengthUnit.Meter, me, s.point) > _kReachM) continue;
      final along = _stopAlongM[s];
      final byRoute = along != null &&
          _riderAlongM != null &&
          (along - _riderAlongM!).abs() <= _kPassedSlackM;
      if (i != nextIdx && !byRoute) continue;
      if (s.poi != null || (s.label ?? '').isNotEmpty) {
        _promptStop(s);
      } else {
        s.reached = true;
        changed = true;
      }
    }
    if (changed) {
      if (_stops.isNotEmpty && _stops.every((x) => x.reached) && !_routeDone) {
        _routeDone = true;
        _reachedCard = null;
      }
      _persistProgress();
      setState(() {});
    }
  }

  /// Zapíše objevené místo (best-effort, nesmí rušit navigaci).
  Future<void> _recordVisit(RoutePoi poi) async {
    final res = await markPlaceVisited(poi, routeId: widget.routeId);
    if (!mounted || res == null) return;
    setState(() => _lastVisit = res);
  }

  /// Vyskočí potvrzovací kartu zastávky (jen jednou na dojezd). Karta NEmizí
  /// sama — čeká, až jezdec ohodnotí a klikne na Pokračovat (nebo ji zavře).
  void _promptStop(_NavStop s) {
    if (_prompted.contains(s)) return;
    _prompted.add(s);
    _lastVisit = null; // badge objevení dorazí async až po potvrzení
    setState(() => _reachedCard = s);
  }

  /// Průjezdní body, které jsem po trase minul (jsem po trase DÁL než bod):
  /// bezejmenné (jen tvar trasy) se odškrtnou potichu; bod zájmu /
  /// pojmenovaná zastávka NIKDY sama — místo toho vyskočí potvrzovací karta.
  void _autoPassStops(RouteProgress prog) {
    final riderAlong = prog.alongM;
    var changed = false;
    for (final s in _stops) {
      if (s.reached) continue;
      final along = _stopAlongM[s];
      if (along == null) continue; // zastávka mimo aktuální polyline
      if (along < riderAlong - _kPassedSlackM) {
        if (s.poi != null || (s.label ?? '').isNotEmpty) {
          _promptStop(s);
        } else {
          s.reached = true;
          changed = true;
        }
      }
    }
    if (changed) {
      _persistProgress();
      setState(() {});
    }
  }

  /// První výpočet živé trasy od polohy jezdce přes zastávky trasy.
  Future<void> _maybeComputeNav() async {
    if (_navLoading || _navGeo != null) return;
    final me = _fix ?? _me;
    final route = _route;
    if (me == null || route == null) return;
    _buildStops(route);
    _syncRideStart(route);
    final pts = _routingPoints(me);
    if (pts.length < 2) return;
    _navLoading = true;
    // Výpočet s potlačením otoček — mezi body se nevracet po stejné silnici.
    final info = await fetchNavRouteInfo(pts,
        profile: widget.profile, traveled: _traveled);
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
    final me = _fix ?? _me;
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
    final info = await fetchNavRouteInfo(pts,
        profile: widget.profile, traveled: _traveled);
    if (!mounted) return;
    setState(() {
      if (info != null && info.geometry.length >= 2) {
        // Nová geometrie → zelená linka se překreslí hned v tomto framu.
        _applyNavInfo(info, fallback: pts);
        _offRouteFixes = 0;
        _wrongWayFixes = 0;
      } else {
        // Selhání (síť/API) → zkrať cooldown, ať se přepočet brzy zopakuje
        // a jezdec nezůstane koukat na starou linku.
        _lastRerouteAt =
            DateTime.now().subtract(_kRerouteCooldown - const Duration(seconds: 3));
      }
      _navLoading = false;
      _rerouting = false;
    });
  }

  List<LatLng> _routingPoints(LatLng me) {
    // Start mírně PŘED jezdcem ve směru jízdy — API neumí předat heading,
    // takže by jinak nová trasa klidně začala otočkou zpět. Takhle přepočet
    // pokračuje po silnici, kterou si jezdec právě vybral.
    var start = me;
    final brg = _travelBearing();
    if (brg != null && _speedKmh > _moveThreshold) {
      start = offsetLatLng(me, brg, 40);
    }
    final pts = <LatLng>[start];
    var added = 0;
    for (final s in _stops) {
      if (s.reached) continue;
      pts.add(s.point);
      if (++added >= _kMaxRoutingStops) break; // limit průjezdních bodů API
    }
    return pts;
  }

  void _applyNavInfo(MapyRouteInfo? info, {required List<LatLng> fallback}) {
    final geo = (info != null && info.geometry.length >= 2) ? info.geometry : fallback;
    _navGeo = geo;
    _navCache = RouteGeoCache.build(geo);
    _navSegHint = null;
    _navLengthM = info?.lengthM ?? polylineLengthM(geo);
    _navDurationS = info?.durationS;
    _computeStopAlong();
  }

  /// Pozice každé neprojeté zastávky PO TRASE (metry od startu) — cache pro
  /// levné auto-odškrtávání projetých bodů při každém GPS fixu.
  void _computeStopAlong() {
    _stopAlongM.clear();
    final cache = _navCache;
    if (cache == null) return;
    for (final s in _stops) {
      if (s.reached) continue;
      final p = cache.project(s.point);
      _stopAlongM[s] = p.distM <= 120 ? p.alongM : null;
    }
  }

  /// Zastávky trasy: waypointy (jinak body zájmu) + u okruhu návrat na pobočku.
  /// Bodům zájmu se přiřadí odpovídající zastávka (≤ 40 m).
  void _buildStops(RouteItem route) {
    if (_stopsBuilt) return;
    _stopsBuilt = true;
    var pts = <LatLng>[];
    if (route.waypoints.isNotEmpty) {
      pts.addAll(route.waypoints);
    } else {
      for (final p in route.pois) {
        final ll = p.latLng;
        if (ll != null) pts.add(ll);
      }
    }
    // LOGICKÉ pořadí bodů — navigace vede bod po bodu, po sobě jdoucí body
    // jsou blízko sebe (žádné 1 a 3 u sebe a 2 úplně jinde): s geometrií
    // podle pozice PO TRASE, bez ní (vlastní trasa) řetěz nejbližších
    // sousedů od polohy jezdce.
    if (pts.length > 2) {
      final geoCache =
          route.geometry.length >= 2 ? RouteGeoCache.build(route.geometry) : null;
      if (geoCache != null) {
        final along = [for (final p in pts) (p, geoCache.project(p).alongM)];
        along.sort((a, b) => a.$2.compareTo(b.$2));
        pts = [for (final e in along) e.$1];
      } else {
        // Od PRVNÍHO bodu (ne od jezdce) — pořadí je deterministické, takže
        // sedí s indexy odškrtnutých bodů uložené rozjeté jízdy.
        pts = _nearestChain(pts.first, pts);
      }
    }
    for (final p in pts) {
      if (_stops.isEmpty ||
          _stops.last.point.latitude != p.latitude ||
          _stops.last.point.longitude != p.longitude) {
        _stops.add(_NavStop(p));
      }
    }
    // Pobočka MotoGo24 (odkud motorka pochází) se NEpřidává automaticky —
    // u KAŽDÉ trasy je v seznamu zastávek jako NEAKTIVNÍ poslední bod
    // s možností „navigovat sem" (aktivace = [_activateBranchReturn]).
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

  /// Hladový řetěz nejbližších sousedů od [from] — každý další bod je ten
  /// nejbližší k předchozímu (logické pořadí bez geometrie trasy).
  List<LatLng> _nearestChain(LatLng from, List<LatLng> pts) {
    const dist = Distance();
    final remaining = [...pts];
    final out = <LatLng>[];
    var cur = from;
    while (remaining.isNotEmpty) {
      var bi = 0;
      var bd = double.infinity;
      for (var i = 0; i < remaining.length; i++) {
        final d = dist.as(LengthUnit.Meter, cur, remaining[i]);
        if (d < bd) {
          bd = d;
          bi = i;
        }
      }
      cur = remaining.removeAt(bi);
      out.add(cur);
    }
    return out;
  }

  _NavStop? get _nextStop {
    for (final s in _stops) {
      if (!s.reached) return s;
    }
    return null;
  }

  /// Pozice příštího navigovaného bodu PO zobrazené trase (metry od startu)
  /// pro ořez zelené linky. Cachované — projekce běží jen při změně bodu
  /// nebo geometrie. Bod daleko od polyline (> 150 m) → null (bez ořezu).
  double? _nextStopAlong(RouteGeoCache c, _NavStop next) {
    if (!identical(_clipStop, next) || !identical(_clipCache, c)) {
      _clipStop = next;
      _clipCache = c;
      final p = c.project(next.point);
      _clipAlongM = p.distM <= 150 ? p.alongM : null;
    }
    return _clipAlongM;
  }

  String _stopLabel(_NavStop s, String lang) {
    final poi = s.poi;
    if (poi != null) return poi.nameFor(lang);
    if ((s.label ?? '').isNotEmpty) return s.label!;
    final i = _stops.indexOf(s);
    return '${t(context).tr('routeBuilderStop')} ${i + 1}';
  }

  // ── Akce z karty dojezdu / sheetu zastávek ──

  /// „Pokračovat" na potvrzovací kartě — TEPRVE TEĎ se bod ručně odškrtne,
  /// zapíše se objevení bodu zájmu (Moje zážitky) a naviguje se na další bod.
  void _confirmReached() {
    final s = _reachedCard;
    if (s != null && !s.reached) {
      s.reached = true;
      final poi = s.poi;
      if (poi != null && poi.id.isNotEmpty && !_visitSent.contains(poi.id)) {
        _visitSent.add(poi.id);
        _recordVisit(poi);
      }
      if (_stops.isNotEmpty && _stops.every((x) => x.reached)) _routeDone = true;
      _persistProgress();
    }
    setState(() => _reachedCard = null);
    if (!_routeDone) _reroute(force: true);
  }

  /// Navigovat rovnou na zvolenou zastávku — dřívější nedojeté body se
  /// přeskočí (vědomá volba jezdce v seznamu zastávek, ne automatika).
  /// Jde i na UŽ NAVŠTÍVENÝ bod: fajfka se mu zruší a naviguje se na něj
  /// znovu — vrátí se po novém ručním potvrzení dojezdu.
  void _navigateToStop(int index) {
    if (index < 0 || index >= _stops.length) return;
    setState(() {
      for (var i = 0; i < index; i++) {
        _stops[i].reached = true;
      }
      final s = _stops[index];
      if (s.reached) {
        s.reached = false;
        _prompted.remove(s); // potvrzovací karta smí vyskočit znovu
        _routeDone = false;
        _doneCardDismissed = false;
      }
      _reachedCard = null;
    });
    _persistProgress();
    _reroute(force: true);
  }

  /// „Moje" pobočka pro vlastní trasu (bez pobočky trasy): nejbližší pobočka
  /// MotoGo24 ke startu trasy / poloze jezdce.
  RouteBranch? _nearestBranchFor(
      Map<String, RouteBranch> branches, RouteItem route) {
    var anchor =
        _fix ?? (route.waypoints.isNotEmpty ? route.waypoints.first : null);
    if (anchor == null && route.pois.isNotEmpty) {
      anchor = route.pois.first.latLng;
    }
    if (anchor == null) return null;
    const dist = Distance();
    RouteBranch? best;
    var bd = double.infinity;
    for (final b in branches.values) {
      final ll = b.latLng;
      if (ll == null) continue;
      final d = dist.as(LengthUnit.Meter, anchor, ll);
      if (d < bd) {
        bd = d;
        best = b;
      }
    }
    return best;
  }

  bool get _branchAdded => _stops.any((s) => s.isBranch);

  /// Aktivace návratu na pobočku MotoGo24: pobočka se přidá jako POSLEDNÍ
  /// zastávka trasy a rovnou se na ni naviguje. Dojezd se pak potvrzuje
  /// ručně stejně jako u bodů zájmu.
  void _activateBranchReturn() {
    final b = _branch;
    final ll = b?.latLng;
    if (b == null || ll == null || _branchAdded) return;
    setState(() {
      _stops.add(_NavStop(ll, label: b.name, isBranch: true));
      _routeDone = false;
      _doneCardDismissed = false;
    });
    _persistProgress();
    _reroute(force: true);
  }

  // ── Persistence rozjeté jízdy (FAB „Pokračovat v trase" + historie) ──

  /// Serializace vlastní trasy pro pozdější obnovu (DB trasa má jen routeId).
  Map<String, dynamic>? _customPayload(RouteItem route) {
    if (widget.routeId != null) return null;
    final wps = <Map<String, dynamic>>[];
    for (var i = 0; i < route.waypoints.length; i++) {
      final w = route.waypoints[i];
      wps.add({'lat': w.latitude, 'lng': w.longitude, 'order': i});
    }
    final pois = <Map<String, dynamic>>[];
    for (final p in route.pois) {
      pois.add({
        'id': p.id,
        'kind': p.isUserPoi ? 'user' : (p.isCatalogPoi ? 'catalog' : 'route'),
        'name': p.name,
        'lat': p.lat,
        'lng': p.lng,
        'image_url': p.imageUrl,
      });
    }
    return {
      'waypoints': wps,
      'pois': pois,
      'distance_km': route.distanceKm,
      'duration_min': route.durationMin,
    };
  }

  /// Po sestavení zastávek: obnov případnou rozjetou jízdu STEJNÉ trasy
  /// (dojeté body) a zapiš/aktualizuj aktivní jízdu — trasa pak přežije
  /// zavření appky a jde v ní pokračovat přes FAB nebo historii.
  void _syncRideStart(RouteItem route) {
    if (_rideSynced) return;
    final st = ref.read(activeRideProvider);
    if (!st.loaded) {
      // Persistence se ještě načítá — zkus to za chvíli znovu.
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted && !_rideSynced) _syncRideStart(route);
      });
      return;
    }
    _rideSynced = true;
    final key = widget.routeId ?? customRideKey(route);
    final existing =
        (st.active != null && st.active!.key == key) ? st.active : null;
    var restored = false;
    if (existing != null) {
      for (final i in existing.reached) {
        if (i >= 0 && i < _stops.length && !_stops[i].reached) {
          _stops[i].reached = true;
          restored = true;
        }
      }
      if (_stops.isNotEmpty && _stops.every((s) => s.reached)) _routeDone = true;
    }
    final lang = ref.read(localeProvider).languageCode;
    final name = route.nameFor(lang);
    ref.read(activeRideProvider.notifier).startRide(ActiveRide(
          id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
          key: key,
          name: name.isNotEmpty ? name : route.name,
          routeId: widget.routeId,
          profile: profileToString(widget.profile),
          reached: [
            for (var i = 0; i < _stops.length; i++)
              if (_stops[i].reached) i
          ],
          totalStops: _stops.length,
          done: _routeDone,
          startedAt: existing?.startedAt ?? DateTime.now(),
          updatedAt: DateTime.now(),
          custom: _customPayload(route),
        ));
    if (restored) {
      // Obnovené dojeté body → přepočítej trasu jen přes zbývající zastávky.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _navGeo != null && !_navLoading) _reroute(force: true);
      });
      setState(() {});
    }
  }

  /// Průběžný zápis postupu do aktivní jízdy.
  void _persistProgress() {
    if (!_rideSynced) return;
    ref.read(activeRideProvider.notifier).updateProgress(
      reached: [
        for (var i = 0; i < _stops.length; i++)
          if (_stops[i].reached) i
      ],
      totalStops: _stops.length,
      done: _routeDone,
    );
  }

  /// Křížek = definitivní zavření trasy (jízda se přesune do historie).
  Future<void> _endRide() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dc) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(t(dc).tr('routeEndConfirmTitle'),
            style: const TextStyle(
                fontSize: MotoGoTypo.sizeH3, fontWeight: MotoGoTypo.w900)),
        content: Text(t(dc).tr('routeEndConfirm')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dc, false),
              child: Text(t(dc).tr('routesFilterClear'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB91C1C),
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dc, true),
            child: Text(t(dc).tr('routeEndBtn')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    ref.read(activeRideProvider.notifier).endRide();
    context.backOr(
        widget.routeId != null ? '/routes/${widget.routeId}' : '/routes');
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
    final b = _branch;
    showNavStopsSheet(
      context,
      stops: views,
      onNavigateTo: _navigateToStop,
      // Pobočka MotoGo24 jako NEAKTIVNÍ poslední bod každé trasy — dokud
      // není přidaná; pak už je v seznamu jako běžná zastávka.
      branchLabel: (!_branchAdded && b?.latLng != null)
          ? 'MotoGo24 · ${b!.name}'
          : null,
      onNavigateToBranch: _activateBranchReturn,
    );
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
    WakelockPlus.disable();
    _sub?.cancel();
    _ticker?.dispose();
    super.dispose();
  }

  void _recenter() {
    setState(() {
      _follow = true;
      _headingUp = true;
    });
    final me = _me;
    if (me == null || !_mapReady) return;
    final moving = _speedKmh > _moveThreshold;
    if (moving) {
      _mapRot = -_smoothHeading;
      _ctrl.moveAndRotate(me, _animZoom, _mapRot);
    } else {
      _ctrl.move(me, _animZoom);
    }
  }

  /// Ruční zoom (tlačítka +/−). Ve follow režimu posune bias adaptivního zoomu
  /// (drží se i při jízdě), jinak jen přiblíží aktuální výřez.
  void _zoomBy(double d) {
    if (!_mapReady) return;
    if (_follow && _me != null) {
      setState(() => _zoomBias = (_zoomBias + d).clamp(-3.0, 4.0));
      _animZoom = _targetZoom(_zoomSpeed);
      _ctrl.move(_me!, _animZoom);
    } else {
      final c = _ctrl.camera;
      _ctrl.move(c.center, (c.zoom + d).clamp(3.0, 19.0));
    }
  }

  /// Cache pro právě zobrazovanou geometrii (navigační polyline sdílí cache
  /// s [_navCache]; základní geometrie trasy má vlastní).
  RouteGeoCache? _cacheFor(List<LatLng> geometry) {
    if (identical(geometry, _navGeo)) return _navCache;
    if (!identical(_dispSrc, geometry)) {
      _dispSrc = geometry;
      _dispBase = RouteGeoCache.build(geometry);
    }
    return _dispBase;
  }

  /// Přepnutí zobrazované polyline (základní → navigační, reroute) — přepočti
  /// projekci posledního fixu, ať predikce nejede po staré geometrii.
  void _setDispCache(RouteGeoCache? c) {
    if (identical(c, _dispCache)) return;
    _dispCache = c;
    _dispSegHint = null;
    if (c != null && _fix != null) {
      final p = c.project(_fix!);
      _dispSegHint = p.segIndex;
      _fixAlongM = p.alongM;
      _fixSnapDistM = p.distM;
    } else {
      _fixAlongM = null;
      _fixSnapDistM = double.infinity;
    }
  }

  void _resetNorth() {
    setState(() => _headingUp = false);
    _mapRot = 0;
    if (_mapReady) _ctrl.rotate(0);
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeProvider).languageCode;

    // Vlastní trasa z vybraných bodů zájmu — naviguj přímo, bez DB lookupu.
    final custom = widget.customRoute;
    if (custom != null) {
      _route = custom;
      // I vlastní trasa nabízí návrat na „moji" pobočku MotoGo24 —
      // bez pobočky trasy se vezme nejbližší ke startu / jezdci
      // (jednou nalezená se drží, ať se nabídka nemění za jízdy).
      final data = ref.watch(routesDataProvider).valueOrNull;
      _branch ??=
          data == null ? null : _nearestBranchFor(data.branches, custom);
      if (_fix != null && _navGeo == null && !_navLoading) {
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
          final listRoute = data.routes.firstWhere(
            (r) => r.id == widget.routeId,
            orElse: () => const RouteItem(id: '', name: ''),
          );
          if (listRoute.id.isEmpty) return _exit(context);
          // Plná trasa (geometry, POI popisy) — seznam je odlehčený.
          final route =
              ref.watch(routeFullProvider(listRoute.id)).valueOrNull ??
                  listRoute;
          final branch = route.branchId != null ? data.branches[route.branchId] : null;
          _route = route;
          _branch = branch;
          if (_fix != null && _navGeo == null && !_navLoading) {
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
    _setDispCache(_cacheFor(geometry));
    final prog = (_me != null && _dispCache != null)
        ? _dispCache!.project(_me!, hintSeg: _dispSegHint)
        : null;
    List<LatLng> doneGeo = const [];
    List<LatLng> aheadGeo = geometry;
    // Při navigaci se zelená linka kreslí JEN k příštímu navigovanému bodu —
    // celá trasa je přes křižující se úseky (mezi body 1–2 a zároveň 3–4)
    // zmatečná. Celá trasa zůstává jen v náhledu před prvním GPS fixem a
    // v detailu trasy; po potvrzení bodu / „navigovat na" jiný bod se
    // linka natáhne k dalšímu cíli.
    final navTarget = _nextStop;
    if (prog != null) {
      doneGeo = [...geometry.sublist(0, prog.segIndex + 1), prog.snapped];
      aheadGeo = [prog.snapped, ...geometry.sublist(prog.segIndex + 1)];
      if (navTarget != null) {
        final c = _dispCache!;
        final na = _nextStopAlong(c, navTarget);
        if (na != null && na > prog.alongM) {
          final endSeg = c.segAt(na);
          if (endSeg >= prog.segIndex) {
            aheadGeo = [
              prog.snapped,
              ...c.pts.sublist(prog.segIndex + 1, endSeg + 1),
              c.pointAt(na),
            ];
          }
        }
      }
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
    // Směr šipky jezdce — až PO [_setDispCache] (počítá se z aktuální trasy).
    final arrowBrg = _arrowBearing();

    // Příští zastávka trasy — pilulka nad HUD.
    final next = navTarget;
    // Další bod PO právě potvrzované zastávce (pro tlačítko na kartě) —
    // potvrzovaná zastávka ještě není odškrtnutá, takže se přeskakuje.
    _NavStop? afterCard;
    if (_reachedCard != null) {
      for (final s in _stops) {
        if (!s.reached && !identical(s, _reachedCard)) {
          afterCard = s;
          break;
        }
      }
    }
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
              // Kamera se smí ovládat až od teď — dřívější GPS fixy by na
              // neattachnutém controlleru spadly (LateInitializationError).
              onMapReady: () => _mapReady = true,
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
                    // Šipka drží reálný směr jízdy (na trase směr trasy) i při
                    // otočené mapě — viz [_arrowBearing].
                    child: NavMeMarker(
                      arrowDeg: arrowBrg == null ? null : arrowBrg + _mapRot,
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
                // Křížek = ZAVŘÍT trasu (šipka zpět ji nechává rozjetou —
                // jde v ní pokračovat přes FAB / historii / po startu appky).
                const SizedBox(width: 8),
                _circleBtn(Icons.close, _endRide, color: const Color(0xFFB91C1C)),
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

        // Potvrzovací karta dojezdu na bod / dokončení trasy — přednost před
        // pilulkou. Bod se odškrtne AŽ tlačítkem Pokračovat ([_confirmReached]).
        if (_reachedCard != null)
          Positioned(
            left: 12, right: 64, bottom: bottomInset + 134,
            child: StopReachedCard(
              name: _stopLabel(_reachedCard!, lang),
              visit: _lastVisit,
              // Další bod PO právě potvrzované zastávce (ta ještě NENÍ
              // odškrtnutá, takže ji z výběru vynech).
              nextLabel: afterCard == null ? null : _stopLabel(afterCard, lang),
              onNext: _confirmReached,
              onChoose: () => _openStopsSheet(lang),
              // Hodnocení + komentář dosaženého bodu zájmu přímo z karty.
              onRate: _reachedCard!.poi == null
                  ? null
                  : () {
                      final poi = _reachedCard!.poi!;
                      final idx = route.pois.indexOf(poi);
                      showRoutePoiSheet(context, poi, lang,
                          index: idx >= 0 ? idx : null);
                    },
              // Zavření karty bod NEpotvrzuje — zůstane neodškrtnutý.
              onClose: () => setState(() => _reachedCard = null),
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

  Widget _circleBtn(IconData icon, VoidCallback onTap, {Color? color}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(MotoGoRadius.lg),
            boxShadow: MotoGoShadows.cardSmall,
          ),
          child: Icon(icon, size: 20, color: color ?? MotoGoColors.black),
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

// Pozn.: projekce na trasu, predikce polohy mezi GPS fixy a úhlové/souřadnicové
// interpolace jsou v route_nav_motion.dart (RouteGeoCache, lerpAngle, …).
