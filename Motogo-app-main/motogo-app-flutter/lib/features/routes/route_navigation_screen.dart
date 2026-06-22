import 'dart:async';
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

/// Navigace trasy PŘÍMO v aplikaci — fullscreen mapa Mapy.com, živá poloha
/// jezdce, sledování (follow), trasa + body zájmu. Bez závislosti na externí
/// navigaci.
class RouteNavigationScreen extends ConsumerStatefulWidget {
  final String routeId;
  const RouteNavigationScreen({super.key, required this.routeId});

  @override
  ConsumerState<RouteNavigationScreen> createState() => _RouteNavigationScreenState();
}

class _RouteNavigationScreenState extends ConsumerState<RouteNavigationScreen> {
  final MapController _ctrl = MapController();
  StreamSubscription<Position>? _sub;
  LatLng? _me;
  double? _heading;
  bool _follow = true;
  bool _locating = true;
  bool _denied = false;

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
          distanceFilter: 5,
        ),
      ).listen((pos) {
        if (!mounted) return;
        final me = LatLng(pos.latitude, pos.longitude);
        setState(() {
          _me = me;
          _heading = (pos.heading >= 0 && pos.heading <= 360) ? pos.heading : null;
        });
        if (_follow) {
          final z = _ctrl.camera.zoom;
          _ctrl.move(me, z < 14 ? 16 : z);
        }
      });
    } catch (_) {
      // bez streamu zkus aspoň jednorázovou polohu
      final p = await GpsService.getCurrentPosition();
      if (mounted && p != null) {
        setState(() => _me = LatLng(p.latitude, p.longitude));
        if (_follow) _ctrl.move(_me!, 16);
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _recenter() {
    setState(() => _follow = true);
    if (_me != null) _ctrl.move(_me!, 16);
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(localeProvider).languageCode;
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
          final geoAsync = ref.watch(routeGeometryProvider(route.id));
          final geometry = geoAsync.valueOrNull ?? route.geometry;
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

    final finish = geometry.isNotEmpty
        ? geometry.last
        : (route.waypoints.isNotEmpty ? route.waypoints.last : null);
    String? remaining;
    if (_me != null && finish != null) {
      final km = const Distance().as(LengthUnit.Kilometer, _me!, finish);
      remaining = km >= 1 ? '${km.toStringAsFixed(1)} km' : '${(km * 1000).round()} m';
    }

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
              initialZoom: 14,
              onPositionChanged: (pos, hasGesture) {
                if (hasGesture && _follow) setState(() => _follow = false);
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://api.mapy.cz/v1/maptiles/outdoor/256/{z}/{x}/{y}?apikey=$mapyApiKey',
                userAgentPackageName: 'com.motogo24.app',
                maxZoom: 19,
              ),
              if (geometry.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(points: geometry, strokeWidth: 7, color: MotoGoColors.dark.withValues(alpha: 0.3)),
                    Polyline(points: geometry, strokeWidth: 5, color: MotoGoColors.greenDark),
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
                    width: 30,
                    height: 30,
                    child: _MeMarker(heading: _heading),
                  ),
              ]),
              RichAttributionWidget(
                attributions: const [TextSourceAttribution('Mapy.com')],
              ),
            ],
          ),
        ),

        // Horní lišta — zpět + název + zbývající vzdálenost
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(12, MediaQuery.of(context).padding.top + 8, 12, 12),
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
                        remaining != null
                            ? '${t(context).tr('routeNavToFinish')} ~$remaining'
                            : (_locating ? t(context).tr('routeNavLocating') : t(context).tr('routeNavTitle')),
                        style: const TextStyle(fontSize: 12, fontWeight: MotoGoTypo.w600, color: Color(0xFF8AAB99), decoration: TextDecoration.none),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Banner při zamítnuté poloze
        if (_denied)
          Positioned(
            left: 16, right: 16, bottom: 96,
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

        // Recenter
        Positioned(
          right: 16, bottom: 28,
          child: FloatingActionButton(
            heroTag: 'route-nav-recenter',
            backgroundColor: _follow ? MotoGoColors.greenDark : Colors.white,
            foregroundColor: _follow ? Colors.white : MotoGoColors.greenDark,
            onPressed: _recenter,
            child: const Icon(Icons.my_location),
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

/// Modrý marker aktuální polohy (volitelně se šipkou směru).
class _MeMarker extends StatelessWidget {
  final double? heading;
  const _MeMarker({this.heading});

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
    if (heading == null) return dot;
    return Transform.rotate(
      angle: heading! * 3.1415926535 / 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned(top: 0, child: Icon(Icons.navigation, size: 14, color: Color(0xFF2563EB))),
          dot,
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
