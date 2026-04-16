import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/native/gps_service.dart';
import 'price_calculator.dart';

/// Address-related UI helpers for the booking form.
/// Includes address tile, address dialog, and address bottom sheet.

const _noDec = TextDecoration.none;

const _mapyKey = 'Ag9d2QJD0i8_fA07r6GDDaZ4qV9aZDGMhWn_HhQ_rFs';
const _mapyHeaders = <String, String>{
  'Accept': 'application/json',
  'X-Mapy-Api-Key': _mapyKey,
};

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
    if (distKm != null && delivFee != null)
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
            Text('~${distKm.toStringAsFixed(0)} km · '
              '${delivFee.toStringAsFixed(0)} Kč',
              style: const TextStyle(fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A8A18))),
          ]))),
  ]);
}

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
                  final loc = s['location'] as Map? ?? {};
                  return ListTile(
                    dense: true,
                    title: Text(name, style: const TextStyle(
                      fontSize: 13)),
                    onTap: () {
                      cCtrl.text = name;
                      ss(() => suggestions = []);
                      // Auto-calc distance
                      final km = estimateKm(name).toDouble();
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
                // Reverse geocode — Mapy.cz primary, Nominatim fallback
                bool filled = false;
                try {
                  final mUri = Uri.parse(
                    'https://api.mapy.cz/v1/rgeocode'
                    '?lat=${pos.latitude}&lon=${pos.longitude}'
                    '&lang=cs&apikey=$_mapyKey');
                  final mRes = await http.get(mUri, headers: _mapyHeaders)
                      .timeout(const Duration(seconds: 5));
                  if (mRes.statusCode == 200) {
                    final data = jsonDecode(mRes.body);
                    final items = (data['items'] as List?) ?? [];
                    if (items.isNotEmpty) {
                      final item = items[0];
                      final name = item['name'] as String? ?? '';
                      final numMatch = RegExp(r'^(.+?)\s+(\d+\/?[\da-zA-Z]*)$').firstMatch(name);
                      final street = numMatch != null
                          ? '${numMatch.group(1)} ${numMatch.group(2)}' : name;
                      final rs = (item['regionalStructure'] as List?) ?? [];
                      String ct = '';
                      for (final r in rs) {
                        if (r['type'] == 'regional.municipality') {
                          ct = r['name'] as String? ?? '';
                          break;
                        }
                      }
                      cCtrl.text = ct;
                      aCtrl.text = street;
                      ss(() => suggestions = []);
                      filled = true;
                    }
                  }
                } catch (_) {}
                if (!filled) {
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

/// Address bottom sheet — autocomplete + GPS + distance.
/// Same UX pattern as size picker (slides from bottom).
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
      onSave: (city, addr) { onSave(city, addr); Navigator.pop(c); },
      onDistCalc: onDistCalc,
      onMapTap: onMapTap),
  );
}

class _AddrSheetBody extends StatefulWidget {
  final TextEditingController ctrl;
  final String title;
  final void Function(String city, String addr) onSave;
  final void Function(double km, double fee)? onDistCalc;
  final Future<void> Function(BuildContext)? onMapTap;
  const _AddrSheetBody({required this.ctrl, required this.title,
    required this.onSave, this.onDistCalc, this.onMapTap});
  @override
  State<_AddrSheetBody> createState() => _AddrSheetBodyState();
}

class _AddrSheetBodyState extends State<_AddrSheetBody> {
  List<Map<String, dynamic>> _sug = [];
  String? _distInfo;
  String _city = '', _addr = '';

  Future<void> _search(String q) async {
    if (q.length < 2) { setState(() => _sug = []); return; }
    try {
      final uri = Uri.parse(
        'https://api.mapy.cz/v1/suggest'
        '?query=${Uri.encodeComponent(q)}'
        '&lang=cs&limit=8&locality=cz'
        '&apikey=$_mapyKey');
      final res = await http.get(uri, headers: _mapyHeaders)
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200 && mounted) {
        final items = (jsonDecode(res.body)['items'] as List?) ?? [];
        setState(() => _sug = items.cast<Map<String, dynamic>>());
      }
    } catch (e) {
      debugPrint('[AddrSheet] search error: $e');
    }
  }

  Future<void> _pick(Map<String, dynamic> s) async {
    final label = s['label'] as String? ?? s['name'] as String? ?? '';
    widget.ctrl.text = label;
    setState(() { _sug = []; _distInfo = 'Počítám km...'; });
    final parts = label.split(',').map((e) => e.trim()).toList();
    _city = parts.length > 1 ? parts.last : label;
    _addr = parts.length > 1 ? parts.first : '';
    // Try real routing via coords from suggestion
    double km;
    final pos = s['position'] as Map<String, dynamic>?;
    if (pos != null) {
      final lat = (pos['lat'] as num?)?.toDouble();
      final lng = (pos['lon'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        km = await _routeKm(lat, lng);
      } else {
        km = estimateKm(label).toDouble();
      }
    } else {
      km = estimateKm(label).toDouble();
    }
    final fee = PriceCalculator.calcDeliveryFee(km);
    if (mounted) {
      setState(() => _distInfo =
          '~${km.toStringAsFixed(0)} km · ${fee.toStringAsFixed(0)} Kč');
      widget.onDistCalc?.call(km, fee);
    }
  }

  Future<double> _routeKm(double lat, double lng) async {
    try {
      return await routeKmFromBranch(lat, lng);
    } catch (_) {}
    return estimateKm(_city).toDouble();
  }

  Future<void> _useGps() async {
    setState(() => _distInfo = 'Zjišťuji polohu...');
    try {
      await GpsService.ensurePermission();
      final pos = await GpsService.getCurrentPosition();
      if (pos == null) {
        if (mounted) setState(() => _distInfo =
            'GPS nedostupné — zadejte adresu ručně nebo z mapy');
        return;
      }
      // Reverse geocode — Mapy.cz primary, Nominatim fallback
      bool filled = false;
      try {
        final mUri = Uri.parse(
          'https://api.mapy.cz/v1/rgeocode'
          '?lat=${pos.latitude}&lon=${pos.longitude}'
          '&lang=cs&apikey=$_mapyKey');
        final mRes = await http.get(mUri, headers: _mapyHeaders)
            .timeout(const Duration(seconds: 5));
        if (mRes.statusCode == 200 && mounted) {
          final data = jsonDecode(mRes.body);
          final items = (data['items'] as List?) ?? [];
          if (items.isNotEmpty) {
            final item = items[0];
            final name = item['name'] as String? ?? '';
            final numMatch = RegExp(r'^(.+?)\s+(\d+\/?[\da-zA-Z]*)$').firstMatch(name);
            _addr = numMatch != null
                ? '${numMatch.group(1)} ${numMatch.group(2)}' : name;
            final rs = (item['regionalStructure'] as List?) ?? [];
            for (final r in rs) {
              if (r['type'] == 'regional.municipality') {
                _city = r['name'] as String? ?? '';
                break;
              }
            }
            widget.ctrl.text = _addr.isNotEmpty ? '$_addr, $_city' : _city;
            filled = true;
          }
        }
      } catch (_) {}
      if (!filled) {
        final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse'
          '?format=json&lat=${pos.latitude}'
          '&lon=${pos.longitude}&zoom=18&addressdetails=1');
        final res = await http.get(uri,
            headers: {'User-Agent': 'MotoGo24/2.0'})
            .timeout(const Duration(seconds: 5));
        if (res.statusCode == 200 && mounted) {
          final a = (jsonDecode(res.body)['address']
              as Map<String, dynamic>?) ?? {};
          final road = a['road'] as String? ?? '';
          final house = a['house_number'] as String? ?? '';
          _city = (a['city'] ?? a['town'] ?? a['village'] ?? '') as String;
          _addr = road.isNotEmpty
              ? '$road${house.isNotEmpty ? " $house" : ""}' : '';
          widget.ctrl.text = _addr.isNotEmpty ? '$_addr, $_city' : _city;
        }
      }
      // Real routing from GPS coords
      final km = await _routeKm(pos.latitude, pos.longitude);
      final fee = PriceCalculator.calcDeliveryFee(km);
      if (mounted) {
        setState(() { _sug = [];
          _distInfo = '~${km.toStringAsFixed(0)} km · '
              '${fee.toStringAsFixed(0)} Kč'; });
        widget.onDistCalc?.call(km, fee);
      }
    } catch (e) {
      debugPrint('[AddrSheet] GPS error: $e');
      if (mounted) setState(() => _distInfo =
          'GPS chyba — zadejte adresu ručně');
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
        Text(widget.title, style: const TextStyle(fontSize: 15,
          fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        // Address input
        TextField(controller: widget.ctrl, onChanged: _search,
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
            constraints: const BoxConstraints(maxHeight: 180),
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
              onPressed: () => widget.onMapTap!(context),
              icon: const Icon(Icons.map_outlined, size: 16),
              label: const Text('Mapa'))),
          ],
        ]),
        // Distance
        if (_distInfo != null)
          Padding(padding: const EdgeInsets.only(top: 8),
            child: Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _distInfo!.contains('nedostupné') || _distInfo!.contains('chyba')
                    ? const Color(0xFFFEF3C7) : const Color(0xFFE8FFE8),
                borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center,
                children: [
                Icon(
                  _distInfo!.contains('nedostupné') || _distInfo!.contains('chyba')
                      ? Icons.warning_amber_rounded : Icons.route,
                  size: 14,
                  color: _distInfo!.contains('nedostupné') || _distInfo!.contains('chyba')
                      ? const Color(0xFFD97706) : const Color(0xFF1A8A18)),
                const SizedBox(width: 6),
                Flexible(child: Text(_distInfo!, style: TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _distInfo!.contains('nedostupné') || _distInfo!.contains('chyba')
                      ? const Color(0xFFD97706) : const Color(0xFF1A8A18)),
                  maxLines: 2, overflow: TextOverflow.ellipsis)),
              ]))),
        const SizedBox(height: 14),
        // Confirm
        SizedBox(width: double.infinity, height: 48,
          child: ElevatedButton(
            onPressed: () {
              if (_city.isEmpty) {
                final parts = widget.ctrl.text.split(',')
                    .map((e) => e.trim()).toList();
                _city = parts.length > 1 ? parts.last : widget.ctrl.text;
                _addr = parts.length > 1 ? parts.first : '';
              }
              widget.onSave(_city, _addr);
            },
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
