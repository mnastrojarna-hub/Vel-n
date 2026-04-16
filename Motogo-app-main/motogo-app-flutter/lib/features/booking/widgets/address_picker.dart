import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../core/theme.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/native/gps_service.dart';
import '../../../core/widgets/address_autocomplete_field.dart';
import '../price_calculator.dart';
import 'map_picker.dart';

/// Address picker with geocoding — mirrors cart-address.js + address-api.js.
/// Uses single-line autocomplete (city → street) via Mapy.cz Suggest.
class AddressPickerWidget extends StatefulWidget {
  final String label;
  final String method;
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
  final _addrKey = GlobalKey<AddressAutocompleteFieldState>();
  String _street = '';
  String _city = '';
  String _zip = '';
  double? _lat, _lng;
  double? _distanceKm;
  double? _deliveryFee;
  bool _confirmed = false;

  static const _apiKey = 'Ag9d2QJD0i8_fA07r6GDDaZ4qV9aZDGMhWn_HhQ_rFs';
  static const _apiBase = 'https://api.mapy.cz/v1';

  void _onAddressSelected(AddressSuggestion s) {
    _street = s.street;
    _city = s.city;
    _zip = s.zip;
    _lat = s.lat;
    _lng = s.lng;
    _calcDistance();
  }

  void _onCleared() {
    _street = '';
    _city = '';
    _zip = '';
    _lat = null;
    _lng = null;
    setState(() {
      _distanceKm = null;
      _deliveryFee = null;
    });
  }

  Future<void> _calcDistance() async {
    if (_street.isEmpty && _city.isEmpty) return;
    final address = '$_street, $_city $_zip'.trim();

    double km;
    if (_lat != null && _lng != null) {
      km = await routeKmFromBranch(_lat!, _lng!);
    } else {
      final coords = await _geocode(address);
      if (coords != null) {
        _lat = coords.$1;
        _lng = coords.$2;
        km = await routeKmFromBranch(coords.$1, coords.$2);
      } else {
        km = estimateKm(address).toDouble();
      }
    }

    final fee = PriceCalculator.calcDeliveryFee(km);
    if (mounted) {
      setState(() {
        _distanceKm = km;
        _deliveryFee = fee;
      });
      widget.onDeliveryFeeChanged(fee);
      widget.onAddressChanged(AddressResult(
          street: _street,
          city: _city,
          zip: _zip,
          lat: _lat,
          lng: _lng));
    }
  }

  Future<(double, double)?> _geocode(String address) async {
    try {
      final uri = Uri.parse(
          '$_apiBase/geocode?query=${Uri.encodeComponent(address)}&apikey=$_apiKey');
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

  Future<void> _useGps() async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Zjišťuji polohu...'),
          duration: Duration(seconds: 2)));
    }
    final pos = await GpsService.getCurrentPosition();
    if (pos == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('GPS není dostupné — vyberte adresu ručně nebo z mapy'),
            duration: Duration(seconds: 3)));
      }
      return;
    }
    _lat = pos.latitude;
    _lng = pos.longitude;
    // Reverse geocode — Mapy.cz primary (precise for CZ), Nominatim fallback
    bool filled = false;
    try {
      final mUri = Uri.parse(
          '$_apiBase/rgeocode?lat=${pos.latitude}&lon=${pos.longitude}'
          '&lang=cs&apikey=$_apiKey');
      final mRes = await http.get(mUri, headers: {
        'Accept': 'application/json',
        'X-Mapy-Api-Key': _apiKey,
      }).timeout(const Duration(seconds: 5));
      if (mRes.statusCode == 200) {
        final data = jsonDecode(mRes.body);
        final items = (data['items'] as List?) ?? [];
        if (items.isNotEmpty) {
          final item = items[0];
          final name = item['name'] as String? ?? '';
          final numMatch = RegExp(r'^(.+?)\s+(\d+\/?[\da-zA-Z]*)$').firstMatch(name);
          _street = numMatch != null
              ? '${numMatch.group(1)} ${numMatch.group(2)}' : name;
          final rs = (item['regionalStructure'] as List?) ?? [];
          for (final r in rs) {
            if (r['type'] == 'regional.municipality') {
              _city = r['name'] as String? ?? '';
              break;
            }
          }
          _zip = item['zip'] as String? ?? '';
          _addrKey.currentState?.setAddress(_street, _city, _zip);
          filled = true;
          if (mounted) setState(() {});
        }
      }
    } catch (_) {}
    if (!filled) {
      try {
        final uri = Uri.parse(
            'https://nominatim.openstreetmap.org/reverse?format=json'
            '&lat=${pos.latitude}&lon=${pos.longitude}&zoom=18&addressdetails=1');
        final res = await http
            .get(uri, headers: {'User-Agent': 'MotoGo24/1.0'})
            .timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final addr =
              (jsonDecode(res.body)['address'] as Map<String, dynamic>?) ?? {};
          _fillFromAddr(addr);
          if (mounted) setState(() {});
        }
      } catch (_) {}
    }
    _calcDistance();
  }

  Future<void> _openMap(BuildContext context) async {
    final result = await MapPickerScreen.show(context, lat: _lat, lng: _lng);
    if (result == null) return;
    _lat = result.lat;
    _lng = result.lng;
    // Map picker already uses Mapy.cz rgeocode — use its parsed result
    _street = result.street;
    _city = result.city;
    _zip = result.zip;
    _addrKey.currentState?.setAddress(result.street, result.city, result.zip);
    if (mounted) setState(() {});
    _calcDistance();
  }

  void _fillFromAddr(Map<String, dynamic> addr) {
    final road = addr['road'] as String? ?? '';
    final house = addr['house_number'] as String? ?? '';
    _street = road.isNotEmpty
        ? '$road${house.isNotEmpty ? " $house" : ""}'
        : '';
    _city =
        (addr['city'] ?? addr['town'] ?? addr['village'] ?? '') as String;
    _zip = (addr['postcode'] ?? '') as String;
    _addrKey.currentState?.setAddress(_street, _city, _zip);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RadioOption(
          label: 'Na pobočce',
          sublabel: 'Mezná 9, Mezná',
          price: 'Zdarma',
          selected: widget.method == 'store',
          onTap: () => widget.onMethodChanged('store'),
        ),
        const SizedBox(height: 6),
        _RadioOption(
          label: widget.label == 'Vyzvednutí'
              ? 'Přistavení na vaši adresu'
              : 'Odvoz z vaší adresy',
          sublabel: '1 000 Kč + 40 Kč/km',
          price: 'od 1 000 Kč',
          selected: widget.method == 'delivery',
          onTap: () => widget.onMethodChanged('delivery'),
        ),
        if (widget.method == 'delivery') ...[
          const SizedBox(height: 10),
          // Single-line autocomplete (city → street)
          AddressAutocompleteField(
            key: _addrKey,
            onSelected: _onAddressSelected,
            onCleared: _onCleared,
            hint: 'Zadejte město…',
          ),
          const SizedBox(height: 8),
          // GPS + Map buttons
          Row(children: [
            Expanded(
                child: _ActionBtn(
                    icon: Icons.my_location,
                    label: 'Poloha',
                    onTap: _useGps)),
            const SizedBox(width: 8),
            Expanded(
                child: _ActionBtn(
                    icon: Icons.map_outlined,
                    label: 'Mapa',
                    onTap: () => _openMap(context))),
          ]),
          if (_distanceKm != null && _deliveryFee != null)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: MotoGoColors.greenPale,
                        borderRadius: BorderRadius.circular(8)),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.route,
                              size: 14, color: MotoGoColors.greenDarker),
                          const SizedBox(width: 6),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  '~${_distanceKm!.toStringAsFixed(0)} km · '
                                  '${_deliveryFee!.toStringAsFixed(0)} Kč',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: MotoGoColors.greenDarker)),
                              Text(t(context).tr('deliveryFeeExplain'),
                                  style: const TextStyle(fontSize: 9, color: MotoGoColors.g400)),
                            ],
                          ),
                        ]))),
          Padding(
              padding: const EdgeInsets.only(top: 6),
              child: GestureDetector(
                  onTap: () => setState(() => _confirmed = !_confirmed),
                  child: Row(children: [
                    Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                            color: _confirmed
                                ? MotoGoColors.green
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: _confirmed
                                    ? MotoGoColors.green
                                    : MotoGoColors.g200,
                                width: 2)),
                        child: _confirmed
                            ? const Icon(Icons.check,
                                size: 12, color: Colors.black)
                            : null),
                    const SizedBox(width: 8),
                    const Text('Potvrzuji adresu',
                        style: TextStyle(
                            fontSize: 11, color: MotoGoColors.g600)),
                  ]))),
        ],
      ],
    );
  }
}

class _RadioOption extends StatelessWidget {
  final String label, sublabel, price;
  final bool selected;
  final VoidCallback onTap;
  const _RadioOption(
      {required this.label,
      required this.sublabel,
      required this.price,
      required this.selected,
      required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: selected ? MotoGoColors.greenPale : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: selected ? MotoGoColors.green : MotoGoColors.g200,
                  width: selected ? 2 : 1)),
          child: Row(children: [
            Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color:
                            selected ? MotoGoColors.green : MotoGoColors.g400,
                        width: 2)),
                child: selected
                    ? Center(
                        child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: MotoGoColors.green)))
                    : null),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: MotoGoColors.black)),
                  Text(sublabel,
                      style: const TextStyle(
                          fontSize: 10, color: MotoGoColors.g400)),
                ])),
            Text(price,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? MotoGoColors.greenDarker
                        : MotoGoColors.g400)),
          ])));
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
              color: MotoGoColors.greenPale,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: MotoGoColors.green, width: 1.5)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 16, color: MotoGoColors.greenDarker),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: MotoGoColors.greenDarker)),
          ])));
}

class AddressResult {
  final String street, city, zip;
  final double? lat, lng;
  const AddressResult(
      {required this.street,
      required this.city,
      required this.zip,
      this.lat,
      this.lng});
}
