import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../../core/theme.dart';
import '../../../core/i18n/i18n_provider.dart';

/// Fullscreen map picker — mirrors openMapPicker() from cart-address-geo.js.
/// Uses flutter_map + OpenStreetMap tiles + CARTO Voyager (no API key).
/// Center crosshair, reverse geocode via Nominatim on move.
class MapPickerScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;

  const MapPickerScreen({super.key, this.initialLat, this.initialLng});

  /// Show map picker and return selected address.
  static Future<MapPickerResult?> show(
    BuildContext context, {
    double? lat,
    double? lng,
  }) {
    return Navigator.of(context).push<MapPickerResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MapPickerScreen(initialLat: lat, initialLng: lng),
      ),
    );
  }

  @override
  State<MapPickerScreen> createState() => _MapPickerState();
}

class _MapPickerState extends State<MapPickerScreen> {
  // Branch location — Mezná 9, 393 01 Mezná
  static const _branchLat = 49.4147;
  static const _branchLng = 15.2953;
  static const _mapyKey = 'whg1ilj203oYhmsqkBHVtUqpk-tYr0E-HFTx4lGdue0';
  static const _mapyHeaders = <String, String>{
    'Accept': 'application/json',
    'X-Mapy-Api-Key': _mapyKey,
  };

  late final MapController _mapCtrl;
  late LatLng _center;
  String _address = ''; // initialized in build via i18n
  bool _loading = false;

  // Parsed address components from reverse geocode
  String _street = '';
  String _city = '';
  String _zip = '';

  @override
  void initState() {
    super.initState();
    _mapCtrl = MapController();
    _center = LatLng(
      widget.initialLat ?? _branchLat,
      widget.initialLng ?? _branchLng,
    );
  }

  Future<void> _onMapMoved(LatLng center) async {
    _center = center;
    if (_loading) return;
    setState(() => _loading = true);

    debugPrint('─── [MAP] _onMapMoved(${center.latitude}, ${center.longitude}) ───');
    bool filled = false;

    // 1) Mapy.cz rgeocode — precise for Czech addresses
    try {
      final mUrl = 'https://api.mapy.cz/v1/rgeocode'
        '?lat=${center.latitude}&lon=${center.longitude}'
        '&lang=cs&apikey=$_mapyKey';
      debugPrint('[MAP] rgeocode URL: $mUrl');
      final mUri = Uri.parse(mUrl);
      final mRes = await http.get(mUri, headers: _mapyHeaders)
          .timeout(const Duration(seconds: 4));
      debugPrint('[MAP] rgeocode status: ${mRes.statusCode}');
      debugPrint('[MAP] rgeocode body (first 400): '
          '${mRes.body.length > 400 ? mRes.body.substring(0, 400) : mRes.body}');
      if (mRes.statusCode == 200) {
        final data = jsonDecode(mRes.body);
        final items = (data['items'] as List?) ?? [];
        debugPrint('[MAP] rgeocode items: ${items.length}');
        if (items.isNotEmpty) {
          final item = items[0];
          final name = item['name'] as String? ?? '';
          debugPrint('[MAP] rgeocode item[0]: name="$name" zip="${item['zip']}"');
          final numMatch = RegExp(r'^(.+?)\s+(\d+\/?[\da-zA-Z]*)$').firstMatch(name);
          _street = numMatch != null
              ? '${numMatch.group(1)} ${numMatch.group(2)}' : name;
          final rs = (item['regionalStructure'] as List?) ?? [];
          _city = '';
          for (final r in rs) {
            if (r['type'] == 'regional.municipality') {
              _city = r['name'] as String? ?? '';
              break;
            }
          }
          _zip = item['zip'] as String? ?? '';
          debugPrint('[MAP] ✓ Mapy.cz: street="$_street" city="$_city" zip="$_zip"');
          setState(() {
            _address = [
              if (_street.isNotEmpty) _street,
              if (_city.isNotEmpty) _city,
              if (_zip.isNotEmpty) _zip,
            ].join(', ');
          });
          filled = true;
        }
      }
    } catch (e) {
      debugPrint('[MAP] ✗ Mapy.cz rgeocode error: $e');
    }

    // 2) Nominatim fallback
    if (!filled) {
      debugPrint('[MAP] trying Nominatim fallback...');
      try {
        final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse'
          '?format=json&lat=${center.latitude}&lon=${center.longitude}'
          '&zoom=18&addressdetails=1',
        );
        final res = await http.get(uri, headers: {
          'User-Agent': 'MotoGo24-App/1.0',
        }).timeout(const Duration(seconds: 5));
        debugPrint('[MAP] Nominatim status: ${res.statusCode}');

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final addr = data['address'] as Map<String, dynamic>?;
          debugPrint('[MAP] Nominatim addr: $addr');
          if (addr != null) {
            final road = addr['road'] ?? '';
            final house = addr['house_number'] ?? '';
            _city = (addr['city'] ?? addr['town'] ?? addr['village'] ?? '') as String;
            _zip = (addr['postcode'] ?? '') as String;
            _street = road.isNotEmpty
                ? '$road${house.isNotEmpty ? " $house" : ""}' : '';
            debugPrint('[MAP] ✓ Nominatim: street="$_street" city="$_city" zip="$_zip"');
            setState(() {
              _address = [
                if (_street.isNotEmpty) _street,
                if (_city.isNotEmpty) _city,
                if (_zip.isNotEmpty) _zip,
              ].join(', ');
            });
          }
        }
      } catch (e) {
        debugPrint('[MAP] ✗ Nominatim error: $e');
        setState(() => _address = '${center.latitude.toStringAsFixed(5)}, '
            '${center.longitude.toStringAsFixed(5)}');
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  void _confirm() {
    debugPrint('═══ [MAP] _confirm() ═══');
    debugPrint('[MAP] returning: lat=${_center.latitude} lng=${_center.longitude}');
    debugPrint('[MAP] returning: street="$_street" city="$_city" zip="$_zip"');
    debugPrint('[MAP] returning: fullAddress="$_address"');
    Navigator.of(context).pop(MapPickerResult(
      lat: _center.latitude,
      lng: _center.longitude,
      street: _street,
      city: _city,
      zip: _zip,
      fullAddress: _address,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 14,
              onPositionChanged: (pos, hasGesture) {
                if (hasGesture && pos.center != null) {
                  _onMapMoved(pos.center!);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'cz.motogo24.app',
              ),
            ],
          ),

          // Center crosshair
          const Center(
            child: Text('📍', style: TextStyle(fontSize: 32)),
          ),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                16, MediaQuery.of(context).padding.top + 8, 16, 12,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    MotoGoColors.dark,
                    MotoGoColors.dark.withValues(alpha: 0),
                  ],
                ),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: MotoGoColors.green,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Text('←',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Colors.black)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Vyberte místo na mapě',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom address preview + confirm
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                16, 12, 16, MediaQuery.of(context).padding.bottom + 12,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: MotoGoColors.black.withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text('📍',
                          style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _loading ? 'Hledám adresu...' : (_address.isEmpty ? t(context).tr('moveMapToPickup') : _address),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _loading
                                ? MotoGoColors.g400
                                : MotoGoColors.black,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _loading ? null : _confirm,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: const Text('Potvrdit adresu →'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Result from map picker.
class MapPickerResult {
  final double lat;
  final double lng;
  final String street;
  final String city;
  final String zip;
  final String fullAddress;

  const MapPickerResult({
    required this.lat,
    required this.lng,
    required this.street,
    required this.city,
    required this.zip,
    required this.fullAddress,
  });
}
