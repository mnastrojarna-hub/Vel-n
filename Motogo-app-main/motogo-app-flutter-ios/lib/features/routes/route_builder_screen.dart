import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';
import '../../core/router.dart' show MotoGoBackNav;
import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import '../../core/widgets/moto_fx.dart';
import 'poi_suggest.dart';
import 'map_fit.dart';
import 'routes_model.dart';
import 'routes_provider.dart';
import 'submit_common.dart';
import 'all_pois_screen.dart';
import 'my_experiences_provider.dart';

/// Jedna zastávka editoru trasy.
class _Stop {
  LatLng point;
  String? name; // null = obecný popisek „Zastávka N"
  RoutePoi? poi; // odkud pochází (bod zájmu), když je z katalogu
  _Stop(this.point, {this.name, this.poi});
}

/// Editor trasy — zákazník si trasu poskládá/upraví: přidá libovolné místo
/// klikem do mapy, přidá body zájmu z katalogu, mění pořadí tažením, vybere
/// profil (doporučené bez dálnic / nejrychlejší / nejkratší) a živě vidí trasu,
/// délku i čas. „Trasa je jen doporučení" — tady vzniká vlastní vyjížďka.
class RouteBuilderScreen extends ConsumerStatefulWidget {
  final RouteItem route;
  /// Explicitní zastávky (uložená trasa z Mých zážitků) — mají přednost před
  /// odvozením z route.pois/waypoints, drží popisky i vazbu na body zájmu.
  final List<BuilderStopSpec>? initialStops;
  const RouteBuilderScreen({super.key, required this.route, this.initialStops});

  @override
  ConsumerState<RouteBuilderScreen> createState() => _RouteBuilderScreenState();
}

class _RouteBuilderScreenState extends ConsumerState<RouteBuilderScreen> {
  final MapController _ctrl = MapController();
  final List<_Stop> _stops = [];
  RouteProfile _profile = RouteProfile.recommended;
  List<LatLng> _geometry = const [];
  double? _distanceM;
  bool _computing = false;
  bool _mapReady = false;
  Timer? _debounce;
  int _reqId = 0;

  @override
  void initState() {
    super.initState();
    final r = widget.route;
    final init = widget.initialStops;
    if (init != null && init.isNotEmpty) {
      for (final s in init) {
        _stops.add(_Stop(s.point, name: s.name, poi: s.poi));
      }
    } else if (r.pois.isNotEmpty) {
      for (final p in r.pois) {
        if (p.latLng != null) _stops.add(_Stop(p.latLng!, name: p.name, poi: p));
      }
    } else {
      for (final w in r.waypoints) {
        _stops.add(_Stop(w));
      }
    }
    _geometry = r.geometry;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fit();
      _recompute();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  // ── Změny zastávek ──
  void _addPoint(LatLng p) {
    final stop = _Stop(p);
    setState(() => _stops.add(stop));
    _scheduleRecompute();
    // Best-effort doplnění názvu místa.
    reverseGeocode(p).then((name) {
      if (!mounted || name == null) return;
      setState(() => stop.name = name);
    });
  }

  /// Přidání bodu z panelu „v okolí trasy" (návrhy do X km od zastávek).
  void _addSuggestedPoi(RoutePoi p) {
    final ll = p.latLng;
    if (ll == null) return;
    setState(() => _stops.add(_Stop(ll, name: p.name, poi: p)));
    _fit();
    _scheduleRecompute();
  }

  Future<void> _addFromPois() async {
    final picked = await Navigator.of(context).push<List<RoutePoi>>(
      MaterialPageRoute(builder: (_) => const AllPoisScreen(pickMode: true)),
    );
    if (picked == null || picked.isEmpty) return;
    setState(() {
      for (final p in picked) {
        if (p.latLng != null) _stops.add(_Stop(p.latLng!, name: p.name, poi: p));
      }
    });
    _fit();
    _recompute();
  }

  void _removeAt(int i) {
    setState(() => _stops.removeAt(i));
    _scheduleRecompute();
  }

  void _reorder(int oldI, int newI) {
    setState(() {
      if (newI > oldI) newI -= 1;
      final s = _stops.removeAt(oldI);
      _stops.insert(newI, s);
    });
    _scheduleRecompute();
  }

  void _setProfile(RouteProfile p) {
    if (p == _profile) return;
    setState(() => _profile = p);
    _recompute();
  }

  // ── Výpočet trasy ──
  void _scheduleRecompute() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _recompute);
  }

  Future<void> _recompute() async {
    final pts = _stops.map((s) => s.point).toList();
    if (pts.length < 2) {
      setState(() {
        _geometry = const [];
        _distanceM = null;
        _computing = false;
      });
      return;
    }
    final req = ++_reqId;
    setState(() => _computing = true);
    final info = await fetchMapyRouteInfo(pts, profile: _profile);
    if (!mounted || req != _reqId) return;
    final g = info?.geometry ?? pts;
    setState(() {
      _geometry = g;
      // Reálná délka po silnici z API; fallback = délka vrácené polyline.
      _distanceM = info?.lengthM ?? polylineLengthM(g);
      _computing = false;
    });
  }

  void _fit() {
    if (!_mapReady) return;
    final pts = _geometry.length >= 2 ? _geometry : _stops.map((s) => s.point).toList();
    fitMapSafe(_ctrl, pts, padding: const EdgeInsets.all(40));
  }

  void _navigate() {
    if (_stops.isEmpty) return;
    final pois = _stops.where((s) => s.poi != null).map((s) => s.poi!).toList();
    final route = RouteItem(
      id: 'custom',
      name: widget.route.name.isNotEmpty ? widget.route.name : t(context).tr('poiCustomRouteTitle'),
      routeType: 'poi',
      waypoints: _stops.map((s) => s.point).toList(),
      pois: pois,
    );
    context.push('/route-nav-custom', extra: CustomNavArgs(route, _profile));
  }

  @override
  Widget build(BuildContext context) {
    // Navigovat lze i k JEDNOMU bodu (naviguje se od živé polohy jezdce k němu).
    // Návrh trasy „ostatním" ale dává smysl až od 2 bodů (jedno místo není trasa).
    final canNav = _stops.isNotEmpty;
    final canSuggest = _stops.length >= 2;
    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: Column(
        children: [
          _mapSection(context),
          _statsBar(context),
          NearbyPoiPanel(
            stops: _stops.map((s) => s.point).toList(),
            excludedPoiIds:
                _stops.map((s) => s.poi?.id).whereType<String>().toSet(),
            onAdd: _addSuggestedPoi,
          ),
          Expanded(child: _stopsList(context)),
          _bottomBar(context, canNav, canSuggest),
        ],
      ),
    );
  }

  // ── Mapa ──
  Widget _mapSection(BuildContext context) {
    final markers = <Marker>[];
    for (var i = 0; i < _stops.length; i++) {
      markers.add(Marker(
        point: _stops[i].point,
        width: 30,
        height: 30,
        child: _numPin(i + 1),
      ));
    }
    final center = _stops.isNotEmpty
        ? _stops.first.point
        : (_geometry.isNotEmpty ? _geometry.first : const LatLng(49.8175, 15.4730));
    return SizedBox(
      height: 260,
      child: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _ctrl,
              options: MapOptions(
                initialCenter: center,
                initialZoom: _stops.isEmpty ? 7 : 11,
                onMapReady: () {
                  _mapReady = true;
                  _fit();
                },
                onTap: (_, p) => _addPoint(p),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://api.mapy.cz/v1/maptiles/outdoor/256/{z}/{x}/{y}?apikey=$mapyApiKey',
                  userAgentPackageName: 'com.motogo24.rental',
                  maxZoom: 19,
                ),
                if (_geometry.length >= 2)
                  PolylineLayer(polylines: [
                    Polyline(points: _geometry, strokeWidth: 7, color: MotoGoColors.dark.withValues(alpha: 0.25)),
                    Polyline(points: _geometry, strokeWidth: 5, color: MotoGoColors.greenDark),
                  ]),
                MarkerLayer(markers: markers),
                RichAttributionWidget(
                  attributions: const [TextSourceAttribution('Mapy.com')],
                ),
              ],
            ),
          ),
          // Zpět
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: _circleBtn(Icons.arrow_back, () => context.backOr('/routes')),
          ),
          // Indikátor počítání
          if (_computing)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                  boxShadow: MotoGoShadows.cardSmall,
                ),
                child: const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: MotoGoColors.greenDark),
                ),
              ),
            ),
          // Nápověda
          Positioned(
            left: 12, right: 12,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                boxShadow: MotoGoShadows.cardSmall,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.touch_app, size: 15, color: MotoGoColors.greenDark),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      t(context).tr('routeBuilderHint'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: MotoGoTypo.sizeMd,
                        fontWeight: MotoGoTypo.w700,
                        color: MotoGoColors.black,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Lišta: délka + čas + profil ──
  Widget _statsBar(BuildContext context) {
    final km = _distanceM == null ? '–' : '${(_distanceM! / 1000).toStringAsFixed(1)} km';
    String tmin = '–';
    if (_distanceM != null) {
      final spd = _profile == RouteProfile.fastest ? 75.0 : 55.0; // km/h odhad
      final mins = (_distanceM! / 1000 / spd * 60).round();
      tmin = mins >= 60 ? '${mins ~/ 60} h ${mins % 60} min' : '$mins min';
    }
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        children: [
          Row(
            children: [
              _statChip(Icons.straighten, km),
              const SizedBox(width: 10),
              _statChip(Icons.schedule, tmin),
              const Spacer(),
              Text('${_stops.length} × ${t(context).tr('routeBuilderStop').toLowerCase()}',
                  style: const TextStyle(
                      fontSize: MotoGoTypo.sizeMd,
                      fontWeight: MotoGoTypo.w700,
                      color: MotoGoColors.g500,
                      decoration: TextDecoration.none)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _profileChip(RouteProfile.recommended, t(context).tr('routeProfileRecommended')),
              const SizedBox(width: 8),
              _profileChip(RouteProfile.fastest, t(context).tr('routeProfileFastest')),
              const SizedBox(width: 8),
              _profileChip(RouteProfile.shortest, t(context).tr('routeProfileShortest')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: MotoGoColors.greenDark),
          const SizedBox(width: 5),
          Text(text,
              style: const TextStyle(
                  fontSize: MotoGoTypo.sizeLg,
                  fontWeight: MotoGoTypo.w900,
                  color: MotoGoColors.black,
                  decoration: TextDecoration.none)),
        ],
      );

  Widget _profileChip(RouteProfile p, String label) {
    final active = _profile == p;
    return Expanded(
      child: PressableScale(
        pressedScale: 0.95,
        onTap: () => _setProfile(p),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? MotoGoColors.greenDark : MotoGoColors.greenPale,
            borderRadius: BorderRadius.circular(MotoGoRadius.pill),
            border: Border.all(color: active ? MotoGoColors.greenDark : MotoGoColors.g200, width: 1.5),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: MotoGoTypo.sizeMd,
              fontWeight: active ? MotoGoTypo.w800 : MotoGoTypo.w700,
              color: active ? Colors.white : MotoGoColors.greenDarker,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }

  // ── Seznam zastávek (přehazovatelný) ──
  Widget _stopsList(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  t(context).tr('routePoisHeader'),
                  style: const TextStyle(
                      fontSize: MotoGoTypo.sizeH3,
                      fontWeight: MotoGoTypo.w900,
                      color: MotoGoColors.black,
                      decoration: TextDecoration.none),
                ),
              ),
              PressableScale(
                pressedScale: 0.96,
                onTap: _addFromPois,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: MotoGoColors.greenPale,
                    borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                    border: Border.all(color: MotoGoColors.green, width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_location_alt, size: 15, color: MotoGoColors.greenDarker),
                      const SizedBox(width: 5),
                      Text(
                        t(context).tr('routeBuilderAddPoi'),
                        style: const TextStyle(
                            fontSize: MotoGoTypo.sizeMd,
                            fontWeight: MotoGoTypo.w800,
                            color: MotoGoColors.greenDarker,
                            decoration: TextDecoration.none),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _stops.isEmpty
              ? Center(
                  child: Text(
                    t(context).tr('routeBuilderEmpty'),
                    style: const TextStyle(
                        fontSize: MotoGoTypo.sizeLg,
                        fontWeight: MotoGoTypo.w700,
                        color: MotoGoColors.g500,
                        decoration: TextDecoration.none),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  itemCount: _stops.length,
                  onReorder: _reorder,
                  itemBuilder: (context, i) => _stopTile(context, i),
                ),
        ),
      ],
    );
  }

  Widget _stopTile(BuildContext context, int i) {
    final s = _stops[i];
    final label = s.name ?? '${t(context).tr('routeBuilderStop')} ${i + 1}';
    return Container(
      key: ValueKey(s),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoRadius.xl),
        border: Border.all(color: MotoGoColors.g200),
        boxShadow: MotoGoShadows.cardSmall,
      ),
      child: Row(
        children: [
          _numPin(i + 1),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: MotoGoTypo.sizeLg,
                      fontWeight: MotoGoTypo.w800,
                      color: MotoGoColors.black,
                      decoration: TextDecoration.none),
                ),
                Text(
                  '${s.point.latitude.toStringAsFixed(4)}, ${s.point.longitude.toStringAsFixed(4)}',
                  style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: MotoGoTypo.w600,
                      color: MotoGoColors.g400,
                      decoration: TextDecoration.none),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _removeAt(i),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFD93636).withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline, size: 22, color: Color(0xFFD93636)),
            ),
          ),
          const SizedBox(width: 6),
          ReorderableDragStartListener(
            index: i,
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: MotoGoColors.greenPale,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.drag_indicator, size: 24, color: MotoGoColors.greenDark),
            ),
          ),
        ],
      ),
    );
  }

  // ── Spodní lišta: Navrhnout ostatním + Navigovat ──
  Widget _bottomBar(BuildContext context, bool canNav, bool canSuggest) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(color: Colors.white, boxShadow: MotoGoShadows.stickyBar),
      child: Row(
        children: [
          // Uložit trasu jen pro sebe (Moje zážitky → Moje trasy).
          PressableScale(
            pressedScale: 0.97,
            onTap: canSuggest ? _openSaveSheet : () {},
            child: Opacity(
              opacity: canSuggest ? 1 : 0.45,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: MotoGoColors.greenPale,
                  borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                  border: Border.all(color: MotoGoColors.green, width: 1.4),
                ),
                child: const Icon(Icons.bookmark_add_outlined,
                    size: 22, color: MotoGoColors.greenDarker),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Sekundární akce: odeslat poskládanou trasu jako návrh do moderace.
          PressableScale(
            pressedScale: 0.97,
            onTap: canSuggest ? _openSuggestSheet : () {},
            child: Opacity(
              opacity: canSuggest ? 1 : 0.45,
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: MotoGoColors.greenPale,
                  borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                  border: Border.all(color: MotoGoColors.green, width: 1.4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.outgoing_mail, size: 20, color: MotoGoColors.greenDarker),
                    const SizedBox(width: 6),
                    Text(
                      t(context).tr('routeSuggestBtn'),
                      style: const TextStyle(
                          fontSize: MotoGoTypo.sizeLg,
                          fontWeight: MotoGoTypo.w800,
                          color: MotoGoColors.greenDarker,
                          decoration: TextDecoration.none),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: PressableScale(
              pressedScale: 0.97,
              onTap: canNav ? _navigate : () {},
              child: Opacity(
                opacity: canNav ? 1 : 0.45,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: MotoGoColors.green,
                    borderRadius: BorderRadius.circular(MotoGoRadius.pill),
                    boxShadow: [
                      BoxShadow(color: MotoGoColors.green.withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.navigation, size: 20, color: MotoGoColors.black),
                        const SizedBox(width: 8),
                        Text(
                          t(context).tr('routeBuilderNavigate'),
                          style: const TextStyle(
                              fontSize: MotoGoTypo.sizeXl,
                              fontWeight: MotoGoTypo.w800,
                              color: MotoGoColors.black,
                              letterSpacing: MotoGoTypo.lsMedium,
                              decoration: TextDecoration.none),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Uložení trasy JEN PRO SEBE (Moje zážitky → Moje trasy) ──
  void _openSaveSheet() {
    if (MotoGoSupabase.currentUser == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t(context).tr('routeSaveLogin'))));
      return;
    }
    if (_stops.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(context).tr('routeSubmitNeedPoints'))));
      return;
    }
    final nameCtrl = TextEditingController(
        text: widget.route.id == 'custom' ? '' : widget.route.name);
    final descCtrl = TextEditingController();
    var busy = false;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                20, 16, 20, MediaQuery.of(sheetCtx).viewInsets.bottom + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t(sheetCtx).tr('routeSaveTitle'),
                  style: const TextStyle(
                      fontSize: MotoGoTypo.sizeH2,
                      fontWeight: MotoGoTypo.w900,
                      color: MotoGoColors.black,
                      decoration: TextDecoration.none),
                ),
                const SizedBox(height: 6),
                Text(
                  t(sheetCtx).tr('routeSaveHint'),
                  style: const TextStyle(
                      fontSize: MotoGoTypo.sizeMd,
                      fontWeight: MotoGoTypo.w600,
                      color: MotoGoColors.g500,
                      decoration: TextDecoration.none),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration:
                      InputDecoration(labelText: t(sheetCtx).tr('routeSaveName')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                      labelText: t(sheetCtx).tr('routeSaveDesc')),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: busy
                        ? null
                        : () async {
                            if (nameCtrl.text.trim().isEmpty) {
                              ScaffoldMessenger.of(sheetCtx).showSnackBar(SnackBar(
                                  content:
                                      Text(t(sheetCtx).tr('poiSubmitNameReq'))));
                              return;
                            }
                            setSheet(() => busy = true);
                            final ok = await _saveMyRoute(
                                nameCtrl.text.trim(), descCtrl.text.trim());
                            if (!sheetCtx.mounted) return;
                            if (ok) {
                              Navigator.of(sheetCtx).pop();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content:
                                        Text(t(context).tr('routeSaved'))));
                              }
                            } else {
                              setSheet(() => busy = false);
                              ScaffoldMessenger.of(sheetCtx).showSnackBar(SnackBar(
                                  content: Text(t(sheetCtx).tr('routeSaveErr'))));
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MotoGoColors.green,
                      foregroundColor: MotoGoColors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(MotoGoRadius.pill)),
                    ),
                    child: Text(
                      t(sheetCtx).tr(busy ? 'submitSending' : 'routeSaveBtn'),
                      style: const TextStyle(
                          fontSize: MotoGoTypo.sizeXl,
                          fontWeight: MotoGoTypo.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _saveMyRoute(String name, String desc) async {
    final waypoints = <Map<String, dynamic>>[];
    final poiRefs = <Map<String, dynamic>>[];
    for (var i = 0; i < _stops.length; i++) {
      final s = _stops[i];
      waypoints.add({
        'lat': s.point.latitude,
        'lng': s.point.longitude,
        'label': (s.name != null && s.name!.trim().isNotEmpty) ? s.name!.trim() : null,
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
    final km = _distanceM == null
        ? null
        : double.parse((_distanceM! / 1000).toStringAsFixed(1));
    final ok = await saveUserRoute(
      name: name,
      description: desc.isEmpty ? null : desc,
      sourceRouteId: widget.route.id == 'custom' ? null : widget.route.id,
      waypoints: waypoints,
      poiRefs: poiRefs,
      profile: _profile,
      distanceKm: km,
      durationMin: km == null ? null : (km / 55 * 60).round(),
    );
    if (ok) ref.invalidate(mySavedRoutesProvider);
    return ok;
  }

  // ── Návrh trasy ostatním (moderace ve Velíně, status='pending') ──
  void _openSuggestSheet() {
    if (MotoGoSupabase.currentUser == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t(context).tr('poiRateLogin'))));
      return;
    }
    if (_stops.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(context).tr('routeSubmitNeedPoints'))));
      return;
    }
    final nameCtrl = TextEditingController(
        text: widget.route.id == 'custom' ? '' : widget.route.name);
    final descCtrl = TextEditingController();
    var busy = false;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                20, 16, 20, MediaQuery.of(sheetCtx).viewInsets.bottom + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t(sheetCtx).tr('routeSuggestTitle'),
                  style: const TextStyle(
                      fontSize: MotoGoTypo.sizeH2,
                      fontWeight: MotoGoTypo.w900,
                      color: MotoGoColors.black,
                      decoration: TextDecoration.none),
                ),
                const SizedBox(height: 12),
                const SubmitIntroBanner(),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration:
                      InputDecoration(labelText: t(sheetCtx).tr('poiSubmitName')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                      labelText: t(sheetCtx).tr('routeSubmitDescLabel')),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: busy
                        ? null
                        : () async {
                            if (nameCtrl.text.trim().isEmpty) {
                              ScaffoldMessenger.of(sheetCtx).showSnackBar(SnackBar(
                                  content:
                                      Text(t(sheetCtx).tr('poiSubmitNameReq'))));
                              return;
                            }
                            setSheet(() => busy = true);
                            final ok = await _submitSuggestion(
                                nameCtrl.text.trim(), descCtrl.text.trim());
                            if (!sheetCtx.mounted) return;
                            if (ok) {
                              Navigator.of(sheetCtx).pop();
                              if (mounted) await showSubmitSuccess(context);
                            } else {
                              setSheet(() => busy = false);
                              ScaffoldMessenger.of(sheetCtx).showSnackBar(SnackBar(
                                  content: Text(t(sheetCtx).tr('poiSubmitErr'))));
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MotoGoColors.green,
                      foregroundColor: MotoGoColors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(MotoGoRadius.pill)),
                    ),
                    child: Text(
                      t(sheetCtx).tr(busy ? 'submitSending' : 'poiSubmitSend'),
                      style: const TextStyle(
                          fontSize: MotoGoTypo.sizeXl,
                          fontWeight: MotoGoTypo.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Uloží poskládanou trasu jako zákaznický návrh (stejné flow jako
  /// „Navrhnout trasu" — řádek v `routes` se status='pending', schvaluje Velín).
  Future<bool> _submitSuggestion(String name, String desc) async {
    final uid = MotoGoSupabase.currentUser?.id;
    if (uid == null) return false;
    try {
      final waypoints = <Map<String, dynamic>>[];
      for (var i = 0; i < _stops.length; i++) {
        final s = _stops[i];
        waypoints.add({
          'lat': s.point.latitude,
          'lng': s.point.longitude,
          'label': (s.name != null && s.name!.trim().isNotEmpty)
              ? s.name!.trim()
              : null,
          'order': i,
        });
      }
      final km = _distanceM == null
          ? null
          : double.parse((_distanceM! / 1000).toStringAsFixed(1));
      await MotoGoSupabase.client.from('routes').insert({
        'name': name,
        'description': desc.isEmpty ? null : desc,
        'route_type': 'poi',
        'waypoints': waypoints,
        'distance_km': km,
        'duration_min': km == null ? null : (km / 55 * 60).round(),
        'created_by': uid,
        'status': 'pending',
        'is_active': false,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Widget _numPin(int n) => Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: MotoGoColors.greenDarker,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Center(
          child: Text('$n',
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white, decoration: TextDecoration.none)),
        ),
      );

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
}
