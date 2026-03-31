import 'dart:convert';
import 'dart:math' show pi, sin, cos, sqrt, atan2;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../core/theme.dart';
import '../price_calculator.dart';

/// Address picker with geocoding — mirrors cart-address.js + address-api.js.
/// Uses Mapy.cz API for autocomplete and distance calculation.
class AddressPickerWidget extends StatefulWidget {
  final String label; // 'Vyzvednutí' or 'Vrácení'
  final String method; // 'store' or 'delivery'
  final ValueChanged<String> onMethodChanged;
  final ValueChanged<AddressResult> onAddressChanged;
  final ValueChanged<double> onDeliveryFeeChanged;

  const AddressPickerWidget({
    super.key,
    required this.label,
    required this.method,
    required this.onMethodChanged,
    required this.onAddressChanged,
    required this.onDeliveryFeeChanged,
  });

  @override
  State<AddressPickerWidget> createState() => _AddressPickerWidgetState();
}

class _AddressPickerWidgetState extends State<AddressPickerWidget> {
  final _streetCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _zipCtrl = TextEditingController();
  double? _lat, _lng;
  double? _distanceKm;
  double? _deliveryFee;
  bool _confirmed = false;

  // Mapy.cz API — mirrors address-api.js
  static const _apiKey = 'Ag9d2QJD0i8_fA07r6GDDaZ4qV9aZDGMhWn_HhQ_rFs';
  static const _apiBase = 'https://api.mapy.cz/v1';
  static const _branchLat = 49.4147;
  static const _branchLng = 15.2953;

  Future<void> _calcDistance() async {
    final address = '${_streetCtrl.text}, ${_cityCtrl.text} ${_zipCtrl.text}';
    if (_streetCtrl.text.trim().isEmpty) return;

    double km;

    if (_lat != null && _lng != null) {
      km = await _routeDistance(_lat!, _lng!);
    } else {
      // Try geocoding first
      final coords = await _geocode(address);
      if (coords != null) {
        _lat = coords.$1;
        _lng = coords.$2;
        km = await _routeDistance(coords.$1, coords.$2);
      } else {
        km = estimateKm(address).toDouble();
      }
    }

    final fee = PriceCalculator.calcDeliveryFee(km);
    setState(() {
      _distanceKm = km;
      _deliveryFee = fee;
    });
    widget.onDeliveryFeeChanged(fee);
    widget.onAddressChanged(AddressResult(
      street: _streetCtrl.text,
      city: _cityCtrl.text,
      zip: _zipCtrl.text,
      lat: _lat,
      lng: _lng,
    ));
  }

  Future<(double, double)?> _geocode(String address) async {
    try {
      final uri = Uri.parse('$_apiBase/geocode?query=${Uri.encodeComponent(address)}&apikey=$_apiKey');
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final items = data['items'] as List?;
        if (items != null && items.isNotEmpty) {
          final pos = items[0]['position'];
          return (pos['lat'] as double, pos['lon'] as double);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<double> _routeDistance(double lat, double lng) async {
    // Try OSRM (free, no API key)
    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/$_branchLng,$_branchLat;$lng,$lat?overview=false',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          return (routes[0]['distance'] as num).toDouble() / 1000;
        }
      }
    } catch (_) {}
    // Haversine fallback
    return _haversine(_branchLat, _branchLng, lat, lng) * 1.3;
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
            sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  @override
  void dispose() {
    _streetCtrl.dispose();
    _cityCtrl.dispose();
    _zipCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusLg),
        boxShadow: [BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.06), blurRadius: 12)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
          const SizedBox(height: 10),
          // Store option
          _RadioOption(
            label: 'Pobočka: Mezná 9, 393 01 Mezná',
            sublabel: widget.label == 'Vyzvednutí' ? 'Osobní vyzvednutí' : 'Vrácení na pobočce',
            price: 'Zdarma',
            selected: widget.method == 'store',
            onTap: () => widget.onMethodChanged('store'),
          ),
          const SizedBox(height: 8),
          // Delivery option
          _RadioOption(
            label: widget.label == 'Vyzvednutí' ? 'Přistavení na adresu' : 'Odvoz z adresy',
            sublabel: '1 000 Kč + 40 Kč/km od provozovny',
            price: 'od 1 000 Kč',
            selected: widget.method == 'delivery',
            onTap: () => widget.onMethodChanged('delivery'),
          ),
          // Address form (only if delivery)
          if (widget.method == 'delivery') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _cityCtrl,
                    decoration: const InputDecoration(labelText: 'Město'),
                    onChanged: (_) => _calcDistance(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _zipCtrl,
                    decoration: const InputDecoration(labelText: 'PSČ'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _streetCtrl,
              decoration: const InputDecoration(labelText: 'Ulice a č.p.'),
              onChanged: (_) => _calcDistance(),
            ),
            // Distance display
            if (_distanceKm != null && _deliveryFee != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '📍 ~${_distanceKm!.toStringAsFixed(0)} km · ${_deliveryFee!.toStringAsFixed(0)} Kč',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.greenDarker),
                ),
              ),
            // Confirm checkbox
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Checkbox(
                    value: _confirmed,
                    onChanged: (v) => setState(() => _confirmed = v ?? false),
                    activeColor: MotoGoColors.green,
                  ),
                  const Expanded(
                    child: Text('Potvrzuji adresu přistavení', style: TextStyle(fontSize: 12, color: MotoGoColors.g600)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RadioOption extends StatelessWidget {
  final String label;
  final String sublabel;
  final String price;
  final bool selected;
  final VoidCallback onTap;

  const _RadioOption({
    required this.label, required this.sublabel,
    required this.price, required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? MotoGoColors.greenPale : MotoGoColors.g100,
          borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
          border: Border.all(color: selected ? MotoGoColors.green : MotoGoColors.g200, width: selected ? 2 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 18, height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? MotoGoColors.green : MotoGoColors.g400, width: 2),
              ),
              child: selected
                  ? Center(child: Container(width: 10, height: 10, decoration: const BoxDecoration(shape: BoxShape.circle, color: MotoGoColors.green)))
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.black)),
                  Text(sublabel, style: const TextStyle(fontSize: 10, color: MotoGoColors.g400)),
                ],
              ),
            ),
            Text(price, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: selected ? MotoGoColors.greenDarker : MotoGoColors.g400)),
          ],
        ),
      ),
    );
  }
}

class AddressResult {
  final String street;
  final String city;
  final String zip;
  final double? lat;
  final double? lng;
  const AddressResult({required this.street, required this.city, required this.zip, this.lat, this.lng});
}
