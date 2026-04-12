import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../../core/theme.dart';

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

  late final MapController _mapCtrl;
  late LatLng _center;
  String _address = 'Přesuňte mapu na místo přistavení';
  bool _loading = false;

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

    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=json&lat=${center.latitude}&lon=${center.longitude}'
        '&zoom=18&addressdetails=1',
      );
      final res = await http.get(uri, headers: {
        'User-Agent': 'MotoGo24-App/1.0',
      }).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final addr = data['address'] as Map<String, dynamic>?;
        if (addr != null) {
          final street = addr['road'] ?? '';
          final house = addr['house_number'] ?? '';
          final city = addr['city'] ?? addr['town'] ?? addr['village'] ?? '';
          final zip = addr['postcode'] ?? '';
          setState(() {
            _address = [
              if (street.isNotEmpty) '$street${house.isNotEmpty ? " $house" : ""}',
              if (city.isNotEmpty) city,
              if (zip.isNotEmpty) zip,
            ].join(', ');
          });
        }
      }
    } catch (_) {
      setState(() => _address = '${center.latitude.toStringAsFixed(5)}, ${center.longitude.toStringAsFixed(5)}');
    }

    if (mounted) setState(() => _loading = false);
  }

  void _confirm() {
    // Parse address components
    final parts = _address.split(', ');
    Navigator.of(context).pop(MapPickerResult(
      lat: _center.latitude,
      lng: _center.longitude,
      street: parts.isNotEmpty ? parts[0] : '',
      city: parts.length > 1 ? parts[1] : '',
      zip: parts.length > 2 ? parts[2] : '',
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
                                color: Colors.white)),
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
                          _loading ? 'Hledám adresu...' : _address,
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
