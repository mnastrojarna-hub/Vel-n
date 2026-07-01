import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';
import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import '../../core/native/gps_service.dart';
import 'routes_provider.dart' show mapyApiKey, reverseGeocode;
import 'route_submit_screen.dart';

/// Menu „Přidat" (z FAB v Trasách) — uživatel navrhne trasu (odkaz z Mapy.com)
/// nebo bod zájmu. Návrhy jdou do moderace (status='pending'); admin ve Velíně
/// jen potvrdí.
void showCommunityAddMenu(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: MotoGoColors.g200, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          _menuItem(c, Icons.route, t(c).tr('routeSubmitTitle'), () {
            Navigator.pop(c);
            if (MotoGoSupabase.currentUser == null) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context).tr('poiRateLogin'))));
              return;
            }
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RouteSubmitScreen()));
          }),
          _menuItem(c, Icons.add_location_alt, t(c).tr('poiSubmitPoi'), () {
            Navigator.pop(c);
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PoiSubmitScreen()));
          }),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

Widget _menuItem(BuildContext c, IconData icon, String label, VoidCallback onTap) => ListTile(
      leading: Icon(icon, color: MotoGoColors.greenDarker),
      title: Text(label,
          style: const TextStyle(fontSize: MotoGoTypo.sizeXl, fontWeight: MotoGoTypo.w800, color: MotoGoColors.black)),
      onTap: onTap,
    );

/// Obrazovka návrhu bodu zájmu — poloha (mapa / GPS), název, popis, foto.
class PoiSubmitScreen extends StatefulWidget {
  const PoiSubmitScreen({super.key});
  @override
  State<PoiSubmitScreen> createState() => _PoiSubmitScreenState();
}

class _PoiSubmitScreenState extends State<PoiSubmitScreen> {
  final MapController _ctrl = MapController();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  LatLng _point = const LatLng(49.8175, 15.4730);
  XFile? _photo;
  bool _busy = false;
  bool _located = false;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    final p = await GpsService.getCurrentPosition();
    if (!mounted || p == null) return;
    setState(() {
      _point = LatLng(p.latitude, p.longitude);
      _located = true;
    });
    _ctrl.move(_point, 14);
    final name = await reverseGeocode(_point);
    if (mounted && name != null && _nameCtrl.text.isEmpty) _nameCtrl.text = name;
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 2048);
    if (x != null) setState(() => _photo = x);
  }

  Future<String?> _uploadPhoto(String uid) async {
    final x = _photo;
    if (x == null) return null;
    try {
      final bytes = await x.readAsBytes();
      final ext = x.name.contains('.') ? x.name.split('.').last : 'jpg';
      final path = 'user-pois/$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await MotoGoSupabase.client.storage.from('media').uploadBinary(path, bytes);
      return MotoGoSupabase.client.storage.from('media').getPublicUrl(path);
    } catch (_) {
      return null;
    }
  }

  Future<void> _submit() async {
    final uid = MotoGoSupabase.currentUser?.id;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context).tr('poiRateLogin'))));
      return;
    }
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context).tr('poiSubmitNameReq'))));
      return;
    }
    setState(() => _busy = true);
    try {
      final imageUrl = await _uploadPhoto(uid);
      await MotoGoSupabase.client.from('user_pois').insert({
        'user_id': uid,
        'name': name,
        'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'lat': _point.latitude,
        'lng': _point.longitude,
        'image_url': imageUrl,
        'status': 'pending',
      });
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t(context).tr('poiSubmitThanks'))));
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
        title: Text(t(context).tr('poiSubmitPoi'),
            style: const TextStyle(fontSize: MotoGoTypo.sizeXl, fontWeight: MotoGoTypo.w800, color: Colors.white)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          // Mapa – klepnutím nastavíš polohu
          SizedBox(
            height: 220,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(MotoGoRadius.card),
              child: FlutterMap(
                mapController: _ctrl,
                options: MapOptions(
                  initialCenter: _point,
                  initialZoom: _located ? 14 : 7,
                  onTap: (_, p) => setState(() => _point = p),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://api.mapy.cz/v1/maptiles/outdoor/256/{z}/{x}/{y}?apikey=$mapyApiKey',
                    userAgentPackageName: 'com.motogo24.app',
                    maxZoom: 19,
                  ),
                  MarkerLayer(markers: [
                    Marker(
                      point: _point,
                      width: 38, height: 38,
                      child: const Icon(Icons.location_on, color: Color(0xFF1A8A18), size: 38),
                    ),
                  ]),
                  RichAttributionWidget(attributions: const [TextSourceAttribution('Mapy.com')]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _initLocation,
              icon: const Icon(Icons.my_location, size: 18, color: MotoGoColors.greenDark),
              label: Text(t(context).tr('poiUseMyLocation'),
                  style: const TextStyle(color: MotoGoColors.greenDark, fontWeight: MotoGoTypo.w700)),
            ),
          ),
          const SizedBox(height: 4),
          TextField(controller: _nameCtrl, decoration: InputDecoration(labelText: t(context).tr('poiSubmitName'))),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            maxLines: 3,
            decoration: InputDecoration(labelText: t(context).tr('poiSubmitDesc')),
          ),
          const SizedBox(height: 16),
          // Foto
          GestureDetector(
            onTap: _pickPhoto,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: MotoGoColors.greenPale,
                borderRadius: BorderRadius.circular(MotoGoRadius.xl),
                border: Border.all(color: MotoGoColors.green, width: 1.2),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_photo == null ? Icons.add_a_photo : Icons.check_circle, size: 20, color: MotoGoColors.greenDarker),
                  const SizedBox(width: 8),
                  Text(_photo == null ? t(context).tr('poiAddPhoto') : (_photo!.name),
                      style: const TextStyle(fontWeight: MotoGoTypo.w800, color: MotoGoColors.greenDarker)),
                ],
              ),
            ),
          ),
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
}
