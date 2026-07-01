import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import 'routes_provider.dart' show mapyApiKey, fetchMapyRoute, reverseGeocode;
import 'map_link.dart';

/// Jedna zastávka navrhované trasy.
class _Stop {
  LatLng point;
  String? name;
  _Stop(this.point, {this.name});
}

/// Plnohodnotné zadání trasy uživatelem — jako ve Velíně: vlož odkaz z Mapy.com
/// nebo Google Maps (body se automaticky načtou), nebo klikej do mapy. Body lze
/// mazat i přehazovat. Po odeslání jde návrh do moderace (status='pending').
class RouteSubmitScreen extends StatefulWidget {
  const RouteSubmitScreen({super.key});

  @override
  State<RouteSubmitScreen> createState() => _RouteSubmitScreenState();
}

class _RouteSubmitScreenState extends State<RouteSubmitScreen> {
  final MapController _ctrl = MapController();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _linkCtrl = TextEditingController();
  final List<_Stop> _stops = [];
  List<LatLng> _geometry = const [];
  String? _mapyUrl;
  bool _mapReady = false;
  bool _decoding = false;
  bool _busy = false;
  bool _showHelp = false;
  String? _linkMsg;
  String? _linkErr;
  Timer? _debounce;
  int _reqId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _linkCtrl.dispose();
    super.dispose();
  }

  // ── Načtení odkazu ──
  Future<void> _loadLink() async {
    final raw = _linkCtrl.text.trim();
    if (raw.isEmpty) return;
    setState(() { _decoding = true; _linkErr = null; _linkMsg = null; });
    try {
      final res = await decodeMapLink(raw);
      if (!mounted) return;
      setState(() {
        _stops
          ..clear()
          ..addAll(res.waypoints.map((p) => _Stop(p)));
        _mapyUrl = res.url;
        _linkMsg = '${res.waypoints.length} ${t(context).tr('routeSubmitLoaded')}';
      });
      _fit();
      _recompute();
      // Best-effort názvy bodů.
      for (final s in _stops) {
        reverseGeocode(s.point).then((name) {
          if (mounted && name != null) setState(() => s.name = name);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _linkErr = '${t(context).tr('routeSubmitDecodeErr')}: $e');
    } finally {
      if (mounted) setState(() => _decoding = false);
    }
  }

  // ── Body na mapě ──
  void _addPoint(LatLng p) {
    final s = _Stop(p);
    setState(() => _stops.add(s));
    _scheduleRecompute();
    reverseGeocode(p).then((name) {
      if (mounted && name != null) setState(() => s.name = name);
    });
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

  void _scheduleRecompute() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _recompute);
  }

  Future<void> _recompute() async {
    final pts = _stops.map((s) => s.point).toList();
    if (pts.length < 2) {
      if (mounted) setState(() => _geometry = const []);
      return;
    }
    final req = ++_reqId;
    final geo = await fetchMapyRoute(pts);
    if (!mounted || req != _reqId) return;
    setState(() => _geometry = geo ?? pts);
  }

  void _fit() {
    if (!_mapReady) return;
    final pts = _geometry.length >= 2 ? _geometry : _stops.map((s) => s.point).toList();
    if (pts.length < 2) {
      if (pts.length == 1) _ctrl.move(pts.first, 13);
      return;
    }
    try {
      _ctrl.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: const EdgeInsets.all(40),
      ));
    } catch (_) {}
  }

  Future<void> _submit() async {
    final uid = MotoGoSupabase.currentUser?.id;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context).tr('poiRateLogin'))));
      return;
    }
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context).tr('poiSubmitNameReq'))));
      return;
    }
    if (_stops.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context).tr('routeSubmitNeedPoints'))));
      return;
    }
    setState(() => _busy = true);
    try {
      final waypoints = <Map<String, dynamic>>[];
      for (var i = 0; i < _stops.length; i++) {
        final s = _stops[i];
        waypoints.add({
          'lat': s.point.latitude,
          'lng': s.point.longitude,
          'label': (s.name != null && s.name!.trim().isNotEmpty) ? s.name!.trim() : null,
          'order': i,
        });
      }
      await MotoGoSupabase.client.from('routes').insert({
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'route_type': 'poi',
        'waypoints': waypoints,
        'mapy_url': _mapyUrl,
        'created_by': uid,
        'status': 'pending',
        'is_active': false,
      });
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context).tr('routeSubmitThanks'))));
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context).tr('poiSubmitErr'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      appBar: AppBar(
        backgroundColor: MotoGoColors.dark,
        foregroundColor: Colors.white,
        title: Text(t(context).tr('routeSubmitTitle'),
            style: const TextStyle(fontSize: MotoGoTypo.sizeXl, fontWeight: MotoGoTypo.w800, color: Colors.white)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          TextField(controller: _nameCtrl, decoration: InputDecoration(labelText: t(context).tr('poiSubmitName'))),
          const SizedBox(height: 14),
          _linkRow(context),
          const SizedBox(height: 14),
          _mapBox(context),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(t(context).tr('routeSubmitOnMapHint'),
                style: const TextStyle(fontSize: MotoGoTypo.sizeMd, fontWeight: MotoGoTypo.w600, color: MotoGoColors.g500)),
          ),
          _stopsList(context),
          const SizedBox(height: 14),
          TextField(controller: _descCtrl, maxLines: 3, decoration: InputDecoration(labelText: t(context).tr('routeSubmitDescLabel'))),
        ],
      ),
      bottomSheet: Container(
        padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
        decoration: BoxDecoration(color: Colors.white, boxShadow: MotoGoShadows.stickyBar),
        child: SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _busy ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: MotoGoColors.green,
              foregroundColor: MotoGoColors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MotoGoRadius.pill)),
            ),
            child: Text(_busy ? '…' : t(context).tr('poiSubmitSend'),
                style: const TextStyle(fontSize: MotoGoTypo.sizeXl, fontWeight: MotoGoTypo.w800)),
          ),
        ),
      ),
    );
  }

  Widget _linkRow(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(t(context).tr('routeSubmitLinkLabel'),
                  style: const TextStyle(fontSize: MotoGoTypo.sizeLg, fontWeight: MotoGoTypo.w800, color: MotoGoColors.black)),
            ),
            GestureDetector(
              onTap: () => setState(() => _showHelp = !_showHelp),
              child: Container(
                width: 22, height: 22,
                decoration: const BoxDecoration(color: MotoGoColors.greenDark, shape: BoxShape.circle),
                child: const Center(child: Text('i', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14))),
              ),
            ),
          ],
        ),
        if (_showHelp)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: MotoGoColors.greenPale, borderRadius: BorderRadius.circular(MotoGoRadius.card)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t(context).tr('routeSubmitLinkHelpTitle'),
                    style: const TextStyle(fontSize: MotoGoTypo.sizeMd, fontWeight: MotoGoTypo.w900, color: MotoGoColors.greenDarker)),
                const SizedBox(height: 4),
                Text('• ${t(context).tr('routeSubmitLinkHelpMapy')}',
                    style: const TextStyle(fontSize: MotoGoTypo.sizeMd, color: MotoGoColors.greenDarker)),
                Text('• ${t(context).tr('routeSubmitLinkHelpGoogle')}',
                    style: const TextStyle(fontSize: MotoGoTypo.sizeMd, color: MotoGoColors.greenDarker)),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _linkCtrl,
                decoration: InputDecoration(hintText: t(context).tr('routeSubmitLinkHint'), isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: _decoding ? null : _loadLink,
                style: ElevatedButton.styleFrom(
                  backgroundColor: MotoGoColors.greenDark,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MotoGoRadius.pill)),
                ),
                child: Text(_decoding ? t(context).tr('routeSubmitLoading') : t(context).tr('routeSubmitLoad'),
                    style: const TextStyle(fontWeight: MotoGoTypo.w800, fontSize: MotoGoTypo.sizeMd)),
              ),
            ),
          ],
        ),
        if (_linkMsg != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('✓ $_linkMsg', style: const TextStyle(fontSize: MotoGoTypo.sizeMd, fontWeight: MotoGoTypo.w700, color: MotoGoColors.greenDark)),
          ),
        if (_linkErr != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_linkErr!, style: const TextStyle(fontSize: MotoGoTypo.sizeMd, color: Color(0xFFD93636))),
          ),
      ],
    );
  }

  Widget _mapBox(BuildContext context) {
    final markers = <Marker>[];
    for (var i = 0; i < _stops.length; i++) {
      markers.add(Marker(point: _stops[i].point, width: 28, height: 28, child: _numPin(i + 1)));
    }
    final center = _stops.isNotEmpty ? _stops.first.point : const LatLng(49.8175, 15.4730);
    return SizedBox(
      height: 240,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(MotoGoRadius.card),
        child: FlutterMap(
          mapController: _ctrl,
          options: MapOptions(
            initialCenter: center,
            initialZoom: _stops.isEmpty ? 7 : 11,
            onMapReady: () { _mapReady = true; _fit(); },
            onTap: (_, p) => _addPoint(p),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://api.mapy.cz/v1/maptiles/outdoor/256/{z}/{x}/{y}?apikey=$mapyApiKey',
              userAgentPackageName: 'com.motogo24.app',
              maxZoom: 19,
            ),
            if (_geometry.length >= 2)
              PolylineLayer(polylines: [
                Polyline(points: _geometry, strokeWidth: 5, color: MotoGoColors.greenDark),
              ]),
            MarkerLayer(markers: markers),
            RichAttributionWidget(attributions: const [TextSourceAttribution('Mapy.com')]),
          ],
        ),
      ),
    );
  }

  Widget _stopsList(BuildContext context) {
    if (_stops.isEmpty) return const SizedBox.shrink();
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _stops.length,
      onReorder: _reorder,
      itemBuilder: (context, i) {
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
          ),
          child: Row(
            children: [
              _numPin(i + 1),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: MotoGoTypo.sizeLg, fontWeight: MotoGoTypo.w800, color: MotoGoColors.black)),
              ),
              GestureDetector(
                onTap: () => _removeAt(i),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(color: const Color(0xFFD93636).withValues(alpha: 0.10), shape: BoxShape.circle),
                  child: const Icon(Icons.delete_outline, size: 20, color: Color(0xFFD93636)),
                ),
              ),
              const SizedBox(width: 4),
              ReorderableDragStartListener(
                index: i,
                child: Container(
                  width: 38, height: 38,
                  decoration: const BoxDecoration(color: MotoGoColors.greenPale, shape: BoxShape.circle),
                  child: const Icon(Icons.drag_indicator, size: 22, color: MotoGoColors.greenDark),
                ),
              ),
            ],
          ),
        );
      },
    );
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
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white, decoration: TextDecoration.none)),
        ),
      );
}
