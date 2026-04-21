import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/native/gps_service.dart';
import 'booking_models.dart';
import 'booking_provider.dart';
import 'price_calculator.dart';
import '../../core/i18n/i18n_provider.dart';

/// Pure UI helper functions for inline booking form in router.dart.
/// NO ConsumerStatefulWidget, NO Riverpod — just widget builders.

const _noDec = TextDecoration.none;

/// Numbered section card.
Widget bookingCard(int n, String title, Widget content) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: Container(padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 12)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Row(children: [
          Container(width: 24, height: 24,
            decoration: const BoxDecoration(
              color: Color(0xFF74FB71),
              shape: BoxShape.circle),
            child: Center(child: Text('$n',
              style: const TextStyle(fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Colors.white, decoration: _noDec)))),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F1A14), decoration: _noDec)),
        ]),
        const SizedBox(height: 12),
        content,
      ])));
}

/// Radio option tile for pickup/return.
Widget bookingRadio(String label, String sub, String price,
    bool sel, VoidCallback onTap) {
  return GestureDetector(onTap: onTap,
    child: Container(padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: sel ? const Color(0xFFE8FFE8) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: sel ? const Color(0xFF74FB71)
              : const Color(0xFFD4E8E0),
          width: sel ? 2 : 1)),
      child: Row(children: [
        Container(width: 18, height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: sel ? const Color(0xFF74FB71)
                  : const Color(0xFF8AAB99), width: 2)),
          child: sel ? Center(child: Container(
            width: 10, height: 10,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF74FB71)))) : null),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Text(label, style: const TextStyle(fontSize: 12,
            fontWeight: FontWeight.w700, decoration: _noDec)),
          Text(sub, style: const TextStyle(fontSize: 10,
            color: Color(0xFF8AAB99), decoration: _noDec)),
        ])),
        Text(price, style: TextStyle(fontSize: 11,
          fontWeight: FontWeight.w700,
          color: sel ? const Color(0xFF1A8A18)
              : const Color(0xFF8AAB99),
          decoration: _noDec)),
      ])));
}

/// Consent checkbox.
Widget bookingCheckbox(String label, bool val, ValueChanged<bool> cb) {
  return GestureDetector(onTap: () => cb(!val),
    child: Row(children: [
      Container(width: 20, height: 20,
        decoration: BoxDecoration(
          color: val ? const Color(0xFF74FB71)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: val ? const Color(0xFF74FB71)
                : const Color(0xFFD4E8E0), width: 2)),
        child: val ? const Icon(Icons.check,
          size: 14, color: Colors.black) : null),
      const SizedBox(width: 8),
      Expanded(child: Text(label,
        style: const TextStyle(fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF4A6357), decoration: _noDec))),
    ]));
}

/// Price row.
Widget bookingPriceRow(String label, String value,
    {bool subtle = false, Color? color}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: Text(label, style: TextStyle(fontSize: 12,
          fontWeight: subtle ? FontWeight.w500 : FontWeight.w600,
          color: subtle ? const Color(0xFF8AAB99)
              : const Color(0xFF4A6357),
          decoration: _noDec))),
        Text(value, style: TextStyle(fontSize: 12,
          fontWeight: color != null ? FontWeight.w800
              : FontWeight.w600,
          color: color ?? (subtle ? const Color(0xFF8AAB99)
              : const Color(0xFF0F1A14)),
          decoration: _noDec)),
      ]));
}

/// Gear size picker row.
Widget bookingGearRow(String label, String? selected,
    ValueChanged<String?> onChanged) {
  return Padding(padding: const EdgeInsets.only(bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
      Text(label, style: const TextStyle(fontSize: 12,
        fontWeight: FontWeight.w700, decoration: _noDec)),
      const SizedBox(height: 4),
      Wrap(spacing: 6, runSpacing: 6,
        children: gearSizes.map((s) {
          final a = selected == s;
          return GestureDetector(
            onTap: () => onChanged(a ? null : s),
            child: Container(
              width: 46, height: 36,
              decoration: BoxDecoration(
                color: a ? const Color(0xFF1A8A18)
                    : const Color(0xFFE8FFE8),
                borderRadius: BorderRadius.circular(8)),
              child: Center(child: Text(s,
                style: TextStyle(fontSize: 12,
                  fontWeight: a ? FontWeight.w900
                      : FontWeight.w600,
                  color: a ? Colors.black
                      : const Color(0xFF0F1A14),
                  decoration: _noDec)))));
        }).toList()),
    ]));
}

/// Address display tile for delivery — shows address + distance.
Widget bookingAddrTile(String? city, String? address,
    VoidCallback onTap, {double? distKm, double? delivFee}) {
  final hasAddr = city?.isNotEmpty == true;
  return Column(children: [
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF1FAF7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFD4E8E0))),
        child: Row(children: [
          const Icon(Icons.location_on, size: 16,
            color: Color(0xFF8AAB99)),
          const SizedBox(width: 8),
          Expanded(child: Text(
            hasAddr ? '${address ?? ""}, $city'
                : 'Klikněte pro zadání adresy',
            style: TextStyle(fontSize: 12,
              color: hasAddr ? const Color(0xFF0F1A14)
                  : const Color(0xFF8AAB99),
              decoration: _noDec))),
          const Icon(Icons.edit, size: 14,
            color: Color(0xFF8AAB99)),
        ]))),
    if (delivFee != null && delivFee > 0)
      Padding(padding: const EdgeInsets.only(top: 6),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFE8FFE8),
            borderRadius: BorderRadius.circular(8)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
            const Icon(Icons.route, size: 14,
              color: Color(0xFF1A8A18)),
            const SizedBox(width: 6),
            Text(distKm != null
              ? '~${distKm.toStringAsFixed(0)} km · ${delivFee!.toStringAsFixed(0)} Kč'
              : '${delivFee!.toStringAsFixed(0)} Kč',
              style: const TextStyle(fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A8A18))),
          ]))),
  ]);
}

const _mapyKey = 'whg1ilj203oYhmsqkBHVtUqpk-tYr0E-HFTx4lGdue0';
const _mapyHeaders = <String, String>{
  'Accept': 'application/json',
  'X-Mapy-Api-Key': _mapyKey,
};

/// Full address dialog — autocomplete + GPS + distance.
void showAddrDialog(BuildContext ctx, String title,
    String city, String addr,
    void Function(String city, String addr) onSave,
    {void Function(double km, double fee)? onDistanceCalc}) {
  final cCtrl = TextEditingController(text: city);
  final aCtrl = TextEditingController(text: addr);
  String? distInfo;
  List<Map<String, dynamic>> suggestions = [];

  showDialog(context: ctx, builder: (c) => StatefulBuilder(
    builder: (c, ss) => AlertDialog(
      title: Text(title),
      content: SizedBox(width: double.maxFinite,
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          // City field with autocomplete
          TextField(controller: cCtrl,
            decoration: const InputDecoration(
              labelText: 'Město',
              prefixIcon: Icon(Icons.location_city, size: 18)),
            onChanged: (v) async {
              if (v.length < 2) {
                ss(() => suggestions = []);
                return;
              }
              try {
                final uri = Uri.parse(
                  'https://api.mapy.cz/v1/suggest'
                  '?query=${Uri.encodeComponent(v)}'
                  '&lang=cs&limit=5'
                  '&apikey=$_mapyKey');
                final res = await http.get(uri, headers: _mapyHeaders)
                    .timeout(const Duration(seconds: 3));
                if (res.statusCode == 200) {
                  final data = jsonDecode(res.body);
                  final items = (data['items'] as List?) ?? [];
                  ss(() => suggestions = items
                      .map((e) => e as Map<String, dynamic>)
                      .toList());
                }
              } catch (_) {}
            }),
          // Suggestions
          if (suggestions.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 150),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: suggestions.length,
                itemBuilder: (_, i) {
                  final s = suggestions[i];
                  final name = s['name'] as String? ?? '';
                  return ListTile(
                    dense: true,
                    title: Text(name, style: const TextStyle(
                      fontSize: 13)),
                    onTap: () async {
                      cCtrl.text = name;
                      ss(() => suggestions = []);
                      // Calc distance — use coords if available
                      double km;
                      final pos = s['position'] as Map<String, dynamic>?;
                      if (pos != null) {
                        final lat = (pos['lat'] as num?)?.toDouble();
                        final lng = (pos['lon'] as num?)?.toDouble();
                        if (lat != null && lng != null) {
                          km = await routeKmFromBranch(lat, lng);
                        } else {
                          km = estimateKm(name).toDouble();
                        }
                      } else {
                        km = estimateKm(name).toDouble();
                      }
                      final fee =
                          PriceCalculator.calcDeliveryFee(km);
                      ss(() => distInfo =
                        '~${km.toStringAsFixed(0)} km · '
                        '${fee.toStringAsFixed(0)} Kč');
                      onDistanceCalc?.call(km, fee);
                    });
                })),
          const SizedBox(height: 8),
          // Street field
          TextField(controller: aCtrl,
            decoration: const InputDecoration(
              labelText: 'Ulice a číslo',
              prefixIcon: Icon(Icons.place, size: 18))),
          const SizedBox(height: 10),
          // GPS button
          GestureDetector(
            onTap: () async {
              ss(() => distInfo = 'Zjišťuji polohu...');
              try {
                final pos = await GpsService.getCurrentPosition();
                if (pos == null) {
                  ss(() => distInfo = 'GPS nedostupné');
                  return;
                }
                // Reverse geocode
                final uri = Uri.parse(
                  'https://nominatim.openstreetmap.org/reverse'
                  '?format=json&lat=${pos.latitude}'
                  '&lon=${pos.longitude}&zoom=18&addressdetails=1');
                final res = await http.get(uri,
                  headers: {'User-Agent': 'MotoGo24/2.0'})
                  .timeout(const Duration(seconds: 5));
                if (res.statusCode == 200) {
                  final a = (jsonDecode(res.body)['address']
                      as Map<String, dynamic>?) ?? {};
                  final road = a['road'] as String? ?? '';
                  final house = a['house_number'] as String? ?? '';
                  final ct = (a['city'] ?? a['town'] ??
                      a['village'] ?? '') as String;
                  cCtrl.text = ct;
                  aCtrl.text = road.isNotEmpty
                      ? '$road${house.isNotEmpty ? " $house" : ""}'
                      : '';
                  ss(() => suggestions = []);
                }
                // Calc distance using real routing
                final km = await routeKmFromBranch(
                    pos.latitude, pos.longitude);
                final fee = PriceCalculator.calcDeliveryFee(km);
                ss(() => distInfo =
                  '~${km.toStringAsFixed(0)} km · '
                  '${fee.toStringAsFixed(0)} Kč');
                onDistanceCalc?.call(km, fee);
              } catch (_) {
                ss(() => distInfo = 'GPS chyba');
              }
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1FAF7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFD4E8E0))),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                Icon(Icons.my_location, size: 16,
                  color: Color(0xFF4A6357)),
                SizedBox(width: 6),
                Text('Použít moji polohu (GPS)',
                  style: TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4A6357))),
              ]))),
          const SizedBox(height: 8),
          // Distance info or calculate button
          GestureDetector(
            onTap: () async {
              final address =
                  '${aCtrl.text}, ${cCtrl.text}'.trim();
              if (address.length < 3) return;
              ss(() => distInfo = 'Počítám...');
              // Try geocode → real routing instead of estimate
              double km;
              try {
                final gUri = Uri.parse(
                  'https://api.mapy.cz/v1/geocode'
                  '?query=${Uri.encodeComponent(address)}'
                  '&lang=cs&limit=1&locality=cz&apikey=$_mapyKey');
                final gRes = await http.get(gUri, headers: _mapyHeaders)
                    .timeout(const Duration(seconds: 5));
                if (gRes.statusCode == 200) {
                  final items = (jsonDecode(gRes.body)['items'] as List?) ?? [];
                  if (items.isNotEmpty) {
                    final pos = items[0]['position'];
                    final lat = (pos?['lat'] as num?)?.toDouble();
                    final lng = (pos?['lon'] as num?)?.toDouble();
                    if (lat != null && lng != null) {
                      km = await routeKmFromBranch(lat, lng);
                    } else {
                      km = estimateKm(address).toDouble();
                    }
                  } else {
                    km = estimateKm(address).toDouble();
                  }
                } else {
                  km = estimateKm(address).toDouble();
                }
              } catch (_) {
                km = estimateKm(address).toDouble();
              }
              final fee = PriceCalculator.calcDeliveryFee(km);
              ss(() => distInfo =
                '~${km.toStringAsFixed(0)} km · '
                '${fee.toStringAsFixed(0)} Kč');
              onDistanceCalc?.call(km, fee);
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFE8FFE8),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF74FB71))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                const Icon(Icons.route, size: 16,
                  color: Color(0xFF1A8A18)),
                const SizedBox(width: 6),
                Flexible(child: Text(distInfo ?? 'Spočítat vzdálenost a cenu',
                  style: const TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A8A18)),
                  maxLines: 2, overflow: TextOverflow.ellipsis)),
              ]))),
        ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c),
          child: const Text('Zrušit')),
        ElevatedButton(onPressed: () {
          onSave(cCtrl.text, aCtrl.text);
          Navigator.pop(c);
        }, child: const Text('Uložit')),
      ],
    )));
}

/// Address bottom sheet — autocomplete + GPS + map + distance.
void showAddrBottomSheet(BuildContext ctx,
    String title, String? city, String? addr,
    void Function(String city, String addr) onSave,
    {void Function(double km, double fee)? onDistCalc,
    Future<void> Function(BuildContext)? onMapTap}) {
  final cCtrl = TextEditingController(
      text: [addr, city].where((s) => s != null && s.isNotEmpty).join(', '));
  showModalBottomSheet(
    context: ctx,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (c) => _AddrSheetBody(
      ctrl: cCtrl, title: title,
      initialCity: city ?? '',
      initialAddr: addr ?? '',
      onSave: (city, addr) { onSave(city, addr); Navigator.pop(c); },
      onDistCalc: onDistCalc,
      onMapTap: onMapTap),
  );
}

class _AddrSheetBody extends StatefulWidget {
  final TextEditingController ctrl;
  final String title;
  final String initialCity, initialAddr;
  final void Function(String city, String addr) onSave;
  final void Function(double km, double fee)? onDistCalc;
  final Future<void> Function(BuildContext)? onMapTap;
  const _AddrSheetBody({required this.ctrl, required this.title,
    this.initialCity = '', this.initialAddr = '',
    required this.onSave, this.onDistCalc, this.onMapTap});
  @override
  State<_AddrSheetBody> createState() => _AddrSheetBodyState();
}

class _AddrSheetBodyState extends State<_AddrSheetBody> {
  List<Map<String, dynamic>> _sug = [];
  String? _distInfo;
  bool _isError = false;
  String _city = '', _addr = '';
  double? _lat, _lng;
  Timer? _debounce;
  // Visible debug log lines (shown in UI for diagnostics)
  final List<String> _dbg = [];

  @override
  void initState() {
    super.initState();
    _city = widget.initialCity;
    _addr = widget.initialAddr;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _log(String msg) {
    debugPrint(msg);
    if (mounted) setState(() {
      _dbg.add(msg);
      if (_dbg.length > 15) _dbg.removeAt(0);
    });
  }

  // ── Mapy.cz Suggest — matches original frontend exactly ──
  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.length < 2) { setState(() => _sug = []); return; }
    _debounce = Timer(const Duration(milliseconds: 200), () => _search(q));
  }

  Future<void> _search(String q) async {
    _log('[SUGGEST] search "$q"');
    List<Map<String, dynamic>> items = [];

    // 1) Try Mapy.cz Suggest
    try {
      final url = 'https://api.mapy.cz/v1/suggest'
        '?query=${Uri.encodeComponent(q)}'
        '&lang=cs&limit=8&locality=cz'
        '&apikey=$_mapyKey';
      final uri = Uri.parse(url);
      final res = await http.get(uri, headers: _mapyHeaders)
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        items = ((data['items'] as List?) ?? []).cast<Map<String, dynamic>>();
        _log('[SUGGEST] Mapy.cz ✓ ${items.length} výsledků');
      } else {
        _log('[SUGGEST] Mapy.cz ${res.statusCode}');
      }
    } catch (e) {
      _log('[SUGGEST] Mapy.cz err: $e');
    }

    // 2) Fallback: Nominatim (free, no API key)
    if (items.isEmpty) {
      try {
        final nUrl = 'https://nominatim.openstreetmap.org/search'
          '?q=${Uri.encodeComponent(q)}'
          '&format=json&countrycodes=cz&limit=8'
          '&addressdetails=1&accept-language=cs';
        final nRes = await http.get(Uri.parse(nUrl), headers: {
          'User-Agent': 'MotoGo24-App/1.0',
        }).timeout(const Duration(seconds: 6));
        if (nRes.statusCode == 200 && mounted) {
          final nData = jsonDecode(nRes.body) as List;
          _log('[SUGGEST] Nominatim ✓ ${nData.length} výsledků');
          // Convert Nominatim format → Mapy.cz-like format
          items = nData.map<Map<String, dynamic>>((n) {
            final addr = n['address'] as Map<String, dynamic>? ?? {};
            final road = addr['road'] ?? addr['hamlet'] ?? addr['village'] ?? '';
            final house = addr['house_number'] ?? '';
            final city = addr['city'] ?? addr['town'] ?? addr['village'] ?? addr['municipality'] ?? '';
            final zip = addr['postcode'] ?? '';
            final street = road.isNotEmpty
                ? '$road${house.isNotEmpty ? " $house" : ""}' : '';
            final label = [
              if (street.isNotEmpty) street,
              if (city.isNotEmpty) city,
              if (zip.isNotEmpty) zip,
            ].join(', ');
            return <String, dynamic>{
              'name': n['display_name'] ?? label,
              'label': label.isNotEmpty ? label : (n['display_name'] ?? ''),
              'position': {'lat': double.tryParse('${n['lat']}'),
                           'lon': double.tryParse('${n['lon']}')},
              'zip': zip,
              'regionalStructure': [
                if (city.isNotEmpty)
                  {'type': 'regional.municipality', 'name': city},
              ],
              '_street': street,
              '_city': city,
            };
          }).toList();
          for (int i = 0; i < items.length && i < 3; i++) {
            _log('  [$i] "${items[i]['label']}"');
          }
        } else {
          _log('[SUGGEST] Nominatim ${nRes.statusCode}');
        }
      } catch (e) {
        _log('[SUGGEST] Nominatim err: $e');
      }
    }

    if (mounted) setState(() => _sug = items);
  }

  // ── Pick a suggestion ──
  Future<void> _pick(Map<String, dynamic> s) async {
    _log('[PICK] "${s['name']}" pos=${s['position']}');

    final name = s['name'] as String? ?? '';
    final label = s['label'] as String? ?? name;
    widget.ctrl.text = label;
    setState(() { _sug = []; _distInfo = 'Počítám km...'; });

    // Extract city from regionalStructure
    final rs = (s['regionalStructure'] as List?) ?? [];
    String municipality = '';
    for (final r in rs) {
      if (r['type'] == 'regional.municipality') {
        municipality = r['name'] as String? ?? '';
        break;
      }
    }

    // Use pre-parsed fields from Nominatim if available
    final preStreet = s['_street'] as String? ?? '';
    final preCity = s['_city'] as String? ?? '';

    // Parse address parts from label
    final parts = label.split(',').map((e) => e.trim()).toList();
    _city = municipality.isNotEmpty ? municipality
        : preCity.isNotEmpty ? preCity
        : (parts.length > 1 ? parts.last : name);
    _addr = preStreet.isNotEmpty ? preStreet
        : (parts.isNotEmpty ? parts.first : name);
    if (_addr == _city) _addr = name;
    _log('[PICK] city="$_city" addr="$_addr"');

    // Coords + distance
    final pos = s['position'] as Map<String, dynamic>?;
    double km;
    if (pos != null) {
      _lat = (pos['lat'] as num?)?.toDouble();
      _lng = (pos['lon'] as num?)?.toDouble();
      _log('[PICK] coords: $_lat, $_lng');
      if (_lat != null && _lng != null) {
        km = await routeKmFromBranch(_lat!, _lng!);
        _log('[PICK] ✓ route=${km.toStringAsFixed(1)}km');
      } else {
        km = estimateKm(_city).toDouble();
        _log('[PICK] ✗ no coords → est ${km.toStringAsFixed(0)}km');
      }
    } else {
      km = estimateKm(_city).toDouble();
      _log('[PICK] ✗ pos=null → est ${km.toStringAsFixed(0)}km');
    }
    _showDist(km);
  }

  // ── GPS ──
  Future<void> _useGps() async {
    _log('[GPS] start...');
    setState(() => _distInfo = 'Zjišťuji polohu...');
    try {
      final hasPerm = await GpsService.ensurePermission();
      _log('[GPS] permission=$hasPerm');
      final pos = await GpsService.getCurrentPosition();
      if (pos == null) {
        _log('[GPS] ✗ position=null');
        if (mounted) setState(() {
          _distInfo = 'GPS nedostupné — zadejte adresu ručně nebo z mapy';
          _isError = true;
        });
        return;
      }
      _log('[GPS] ✓ lat=${pos.latitude} lng=${pos.longitude} acc=${pos.accuracy}m');
      _lat = pos.latitude;
      _lng = pos.longitude;

      // Reverse geocode — Mapy.cz primary (precise for CZ), Nominatim fallback
      bool filled = false;
      try {
        final mUri = Uri.parse(
          'https://api.mapy.cz/v1/rgeocode'
          '?lat=${pos.latitude}&lon=${pos.longitude}'
          '&lang=cs&apikey=$_mapyKey');
        final mRes = await http.get(mUri, headers: _mapyHeaders)
            .timeout(const Duration(seconds: 5));
        _log('[GPS] rgeocode HTTP ${mRes.statusCode}');
        if (mRes.statusCode == 200 && mounted) {
          final data = jsonDecode(mRes.body);
          final items = (data['items'] as List?) ?? [];
          if (items.isNotEmpty) {
            final item = items[0];
            final name = item['name'] as String? ?? '';
            final numMatch = RegExp(r'^(.+?)\s+(\d+\/?[\da-zA-Z]*)$').firstMatch(name);
            _addr = numMatch != null ? '${numMatch.group(1)} ${numMatch.group(2)}' : name;
            final rs = (item['regionalStructure'] as List?) ?? [];
            for (final r in rs) {
              if (r['type'] == 'regional.municipality') {
                _city = r['name'] as String? ?? '';
                break;
              }
            }
            widget.ctrl.text = _addr.isNotEmpty ? '$_addr, $_city' : _city;
            _log('[GPS] ✓ rgeocode: "$_addr, $_city"');
            filled = true;
          }
        }
      } catch (e) {
        _log('[GPS] ✗ rgeocode err: $e');
      }

      // Nominatim fallback
      if (!filled) {
        _log('[GPS] Nominatim fallback...');
        try {
          final uri = Uri.parse(
            'https://nominatim.openstreetmap.org/reverse'
            '?format=json&lat=${pos.latitude}'
            '&lon=${pos.longitude}&zoom=18&addressdetails=1');
          final res = await http.get(uri,
              headers: {'User-Agent': 'MotoGo24/2.0'})
              .timeout(const Duration(seconds: 5));
          _log('[GPS] Nominatim HTTP ${res.statusCode}');
          if (res.statusCode == 200 && mounted) {
            final a = (jsonDecode(res.body)['address']
                as Map<String, dynamic>?) ?? {};
            final road = a['road'] as String? ?? '';
            final house = a['house_number'] as String? ?? '';
            _city = (a['city'] ?? a['town'] ?? a['village'] ?? '') as String;
            _addr = road.isNotEmpty
                ? '$road${house.isNotEmpty ? " $house" : ""}' : '';
            widget.ctrl.text = _addr.isNotEmpty ? '$_addr, $_city' : _city;
            _log('[GPS] ✓ Nominatim: "$_addr, $_city"');
          }
        } catch (e) {
          _log('[GPS] ✗ Nominatim err: $e');
        }
      }

      _log('[GPS] routing...');
      final km = await routeKmFromBranch(pos.latitude, pos.longitude);
      _log('[GPS] ✓ ${km.toStringAsFixed(1)}km');
      _showDist(km);
    } catch (e) {
      _log('[GPS] ✗ FATAL: $e');
      if (mounted) setState(() {
        _distInfo = 'GPS chyba — zadejte adresu ručně';
        _isError = true;
      });
    }
  }

  // ── Map picker (handled internally) ──
  Future<void> _openMap() async {
    // Import-free: call the onMapTap callback but intercept results
    // by reading the draft after it returns. Better: use launchMapPicker.
    if (widget.onMapTap != null) {
      await widget.onMapTap!(context);
      // onMapTap updates draft directly — read back and close
      if (mounted) widget.onSave(_city, _addr);
      return;
    }
  }

  // ── Show distance + update provider ──
  void _showDist(double km) {
    final fee = PriceCalculator.calcDeliveryFee(km);
    if (mounted) {
      setState(() { _sug = [];
        _isError = false;
        _distInfo = '~${km.toStringAsFixed(0)} km · '
            '${fee.toStringAsFixed(0)} Kč'; });
      widget.onDistCalc?.call(km, fee);
    }
  }

  // ── Confirm: parse address + calc distance if needed ──
  Future<void> _confirm() async {
    debugPrint('─── [CONFIRM] _confirm() ───');
    debugPrint('[CONFIRM] state: city="$_city" addr="$_addr" lat=$_lat lng=$_lng distInfo=$_distInfo');
    debugPrint('[CONFIRM] textField: "${widget.ctrl.text}"');

    // Parse from text field if no suggestion was picked
    if (_city.isEmpty) {
      final parts = widget.ctrl.text.split(',')
          .map((e) => e.trim()).toList();
      _city = parts.length > 1 ? parts.last : widget.ctrl.text;
      _addr = parts.length > 1 ? parts.first : '';
      debugPrint('[CONFIRM] parsed from text: city="$_city" addr="$_addr"');
    }

    // Calculate distance if not yet done
    if (_distInfo == null && _city.isNotEmpty) {
      debugPrint('[CONFIRM] no distance yet → calculating...');
      double km;
      if (_lat != null && _lng != null) {
        debugPrint('[CONFIRM] has coords → routeKmFromBranch($_lat, $_lng)');
        km = await routeKmFromBranch(_lat!, _lng!);
      } else {
        debugPrint('[CONFIRM] no coords → geocoding "$_addr, $_city"...');
        try {
          final gUrl = 'https://api.mapy.cz/v1/geocode'
            '?query=${Uri.encodeComponent('$_addr, $_city')}'
            '&lang=cs&limit=1&locality=cz&apikey=$_mapyKey';
          debugPrint('[CONFIRM] geocode URL: $gUrl');
          final gUri = Uri.parse(gUrl);
          final gRes = await http.get(gUri, headers: _mapyHeaders)
              .timeout(const Duration(seconds: 5));
          debugPrint('[CONFIRM] geocode status: ${gRes.statusCode}');
          debugPrint('[CONFIRM] geocode body (first 300): '
              '${gRes.body.length > 300 ? gRes.body.substring(0, 300) : gRes.body}');
          if (gRes.statusCode == 200) {
            final items = (jsonDecode(gRes.body)['items'] as List?) ?? [];
            debugPrint('[CONFIRM] geocode items: ${items.length}');
            if (items.isNotEmpty) {
              final pos = items[0]['position'];
              debugPrint('[CONFIRM] geocode position: $pos');
              if (pos != null) {
                _lat = (pos['lat'] as num?)?.toDouble();
                _lng = (pos['lon'] as num?)?.toDouble();
              }
            }
          }
        } catch (e) {
          debugPrint('[CONFIRM] ✗ geocode error: $e');
        }
        if (_lat != null && _lng != null) {
          debugPrint('[CONFIRM] geocoded coords: lat=$_lat lng=$_lng → routing...');
          km = await routeKmFromBranch(_lat!, _lng!);
        } else {
          km = estimateKm('$_addr $_city').toDouble();
          debugPrint('[CONFIRM] ✗ no coords → estimateKm = ${km.toStringAsFixed(0)}km');
        }
      }
      final fee = PriceCalculator.calcDeliveryFee(km);
      debugPrint('[CONFIRM] result: ${km.toStringAsFixed(1)}km, ${fee.toStringAsFixed(0)} Kč');
      widget.onDistCalc?.call(km, fee);
    } else {
      debugPrint('[CONFIRM] distance already calculated or city empty, skipping');
    }
    debugPrint('[CONFIRM] → onSave(city="$_city", addr="$_addr")');
    widget.onSave(_city, _addr);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20,
        MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, decoration: BoxDecoration(
          color: const Color(0xFFD4E8E0),
          borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 14),
        Text(widget.title, style: const TextStyle(fontSize: 15,
          fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        // Address input
        TextField(controller: widget.ctrl, onChanged: _onChanged,
          autofocus: true,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Zadejte adresu...',
            prefixIcon: const Icon(Icons.search, size: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10)))),
        // Suggestions
        if (_sug.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFD4E8E0)),
              borderRadius: BorderRadius.circular(8)),
            child: ListView.builder(
              shrinkWrap: true, padding: EdgeInsets.zero,
              itemCount: _sug.length, itemBuilder: (_, i) {
                final label = _sug[i]['label'] as String? ??
                    _sug[i]['name'] as String? ?? '';
                return ListTile(dense: true,
                  leading: const Icon(Icons.place, size: 16,
                    color: Color(0xFF8AAB99)),
                  title: Text(label, style: const TextStyle(fontSize: 12)),
                  onTap: () => _pick(_sug[i]));
              })),
        const SizedBox(height: 10),
        // GPS + Map buttons
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: _useGps,
            icon: const Icon(Icons.my_location, size: 16),
            label: const Text('GPS'))),
          if (widget.onMapTap != null) ...[
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(
              onPressed: _openMap,
              icon: const Icon(Icons.map_outlined, size: 16),
              label: const Text('Mapa'))),
          ],
        ]),
        // Distance / status
        if (_distInfo != null)
          Padding(padding: const EdgeInsets.only(top: 8),
            child: Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _isError ? const Color(0xFFFEF3C7)
                    : const Color(0xFFE8FFE8),
                borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center,
                children: [
                Icon(_isError ? Icons.warning_amber_rounded : Icons.route,
                  size: 14,
                  color: _isError ? const Color(0xFFD97706)
                      : const Color(0xFF1A8A18)),
                const SizedBox(width: 6),
                Flexible(child: Text(_distInfo!, style: TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _isError ? const Color(0xFFD97706)
                      : const Color(0xFF1A8A18)),
                  maxLines: 2, overflow: TextOverflow.ellipsis)),
              ]))),
        // ── DEBUG STRIP (visible in UI) ──
        if (_dbg.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2E22),
                borderRadius: BorderRadius.circular(6)),
              constraints: const BoxConstraints(maxHeight: 120),
              child: SingleChildScrollView(
                reverse: true,
                child: Text(
                  _dbg.join('\n'),
                  style: const TextStyle(
                    fontSize: 9, color: Color(0xFF74FB71),
                    fontFamily: 'monospace', height: 1.3),
                )))),
        const SizedBox(height: 14),
        // Confirm
        SizedBox(width: double.infinity, height: 48,
          child: ElevatedButton(
            onPressed: _confirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF74FB71),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(50))),
            child: const Text('POTVRDIT ADRESU',
              style: TextStyle(fontWeight: FontWeight.w800)))),
      ]));
  }
}

/// Promo code bottom sheet.
void showPromoBottomSheet(BuildContext ctx,
    List<AppliedDiscount> current,
    void Function(AppliedDiscount) onApplied,
    void Function(String) onRemoved) {
  showModalBottomSheet(
    context: ctx,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (c) => _PromoSheetBody(
      current: current,
      onApplied: (d) { onApplied(d); Navigator.pop(c); },
      onRemoved: onRemoved),
  );
}

class _PromoSheetBody extends StatefulWidget {
  final List<AppliedDiscount> current;
  final ValueChanged<AppliedDiscount> onApplied;
  final ValueChanged<String> onRemoved;
  const _PromoSheetBody({required this.current,
    required this.onApplied, required this.onRemoved});
  @override
  State<_PromoSheetBody> createState() => _PromoSheetBodyState();
}

class _PromoSheetBodyState extends State<_PromoSheetBody> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _msg; bool? _ok;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _apply() async {
    final code = _ctrl.text.trim();
    if (code.isEmpty) return;
    setState(() { _loading = true; _msg = null; });
    final result = await validateAndApplyCode(code);
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.success && result.discount != null) {
      _ctrl.clear();
      setState(() { _msg = result.message(t(context).tr); _ok = true; });
      widget.onApplied(result.discount!);
    } else {
      setState(() { _msg = result.message(t(context).tr); _ok = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20,
        MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, decoration: BoxDecoration(
          color: const Color(0xFFD4E8E0),
          borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 14),
        const Text('Slevový kód', style: TextStyle(fontSize: 15,
          fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: TextField(controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            onSubmitted: (_) => _apply(),
            decoration: InputDecoration(
              hintText: 'Zadejte kód...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10))))),
          const SizedBox(width: 8),
          ElevatedButton(onPressed: _loading ? null : _apply,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A2E22),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10))),
            child: _loading
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('UPLATNIT', style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800))),
        ]),
        if (_msg != null)
          Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(_ok == true ? '✓ $_msg' : _msg!,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: _ok == true ? const Color(0xFF1A8A18) : const Color(0xFFEF4444)))),
      ]));
  }
}
