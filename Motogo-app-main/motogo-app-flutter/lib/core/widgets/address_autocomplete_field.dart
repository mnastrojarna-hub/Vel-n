import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../theme.dart';

/// Single-line address autocomplete using Mapy.cz Suggest API.
/// Shows ranked suggestions (address > street > municipality > POI) with
/// primary title + subtitle. No type restriction — user's text decides.
class AddressAutocompleteField extends StatefulWidget {
  final ValueChanged<AddressSuggestion> onSelected;
  final VoidCallback? onCleared;
  final String hint;

  const AddressAutocompleteField({
    super.key,
    required this.onSelected,
    this.onCleared,
    this.hint = 'Zadejte adresu, obec nebo ulici…',
  });

  @override
  State<AddressAutocompleteField> createState() =>
      AddressAutocompleteFieldState();
}

class AddressAutocompleteFieldState extends State<AddressAutocompleteField> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  List<_Sug> _items = [];
  bool _open = false;
  bool _loading = false;

  static const _key = 'whg1ilj203oYhmsqkBHVtUqpk-tYr0E-HFTx4lGdue0';
  static const _base = 'https://api.mapy.cz/v1';
  static const _headers = {
    'Accept': 'application/json',
    'X-Mapy-Api-Key': _key,
  };

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focus.hasFocus && mounted) {
      setState(() => _open = false);
    }
  }

  /// Set address externally (GPS / map picker).
  void setAddress(String street, String city, String zip) {
    _ctrl.text = [street, [zip, city].where((s) => s.isNotEmpty).join(' ')]
        .where((s) => s.isNotEmpty)
        .join(', ');
    setState(() {
      _items = [];
      _open = false;
    });
  }

  void clear() {
    _ctrl.clear();
    setState(() {
      _items = [];
      _open = false;
    });
  }

  String get text => _ctrl.text;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    super.dispose();
  }

  void _onChange(String v) {
    if (v.isEmpty) {
      setState(() {
        _items = [];
        _open = false;
      });
      widget.onCleared?.call();
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _fetch(v));
  }

  Future<void> _fetch(String q) async {
    if (q.trim().length < 2) return;
    if (mounted) setState(() => _loading = true);

    var sugs = <_Sug>[];

    // 1) Mapy.cz Suggest — single pass, no type restriction
    try {
      final url = '$_base/suggest'
          '?query=${Uri.encodeComponent(q)}'
          '&lang=cs&limit=8&locality=cz&apikey=$_key';
      final res = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final items = (jsonDecode(res.body)['items'] as List?) ?? [];
        for (final it in items) {
          try {
            final sug = _parseSuggestion(it);
            if (sug != null) sugs.add(sug);
          } catch (_) {}
        }
        debugPrint('[Autocomplete] Mapy.cz ✓ ${sugs.length} results for "$q"');
      } else {
        debugPrint('[Autocomplete] Mapy.cz ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('[Autocomplete] Mapy.cz error: $e');
    }

    // 2) Fallback: Nominatim (free, no API key)
    if (sugs.isEmpty && mounted) {
      try {
        final nUrl = 'https://nominatim.openstreetmap.org/search'
            '?q=${Uri.encodeComponent(q)}'
            '&format=json&countrycodes=cz&limit=6'
            '&addressdetails=1&accept-language=cs';
        final nRes = await http.get(Uri.parse(nUrl), headers: {
          'User-Agent': 'MotoGo24-App/1.0',
        }).timeout(const Duration(seconds: 6));
        if (nRes.statusCode == 200 && mounted) {
          final nData = jsonDecode(nRes.body) as List;
          for (final n in nData) {
            final addr = n['address'] as Map<String, dynamic>? ?? {};
            final road = addr['road'] ?? addr['hamlet'] ?? addr['village'] ?? '';
            final house = addr['house_number'] ?? '';
            final city = addr['city'] ?? addr['town'] ??
                addr['village'] ?? addr['municipality'] ?? '';
            final zip = addr['postcode'] ?? '';
            final lat = double.tryParse('${n['lat']}');
            final lng = double.tryParse('${n['lon']}');
            final street = road.isNotEmpty
                ? '$road${house.isNotEmpty ? " $house" : ""}'
                : '';
            final primary =
                street.isNotEmpty ? street : (city.isNotEmpty ? city : '${n['display_name']}');
            final secondary =
                [if (zip.isNotEmpty) zip, if (street.isNotEmpty) city]
                    .where((s) => s != null && s.toString().isNotEmpty)
                    .join(' ');
            sugs.add(_Sug(
              primary: primary,
              secondary: secondary,
              street: street,
              city: city,
              zip: zip,
              lat: lat,
              lng: lng,
              icon: street.isNotEmpty ? Icons.place : Icons.location_city,
            ));
          }
          debugPrint('[Autocomplete] Nominatim ✓ ${sugs.length} results');
        }
      } catch (e) {
        debugPrint('[Autocomplete] Nominatim error: $e');
      }
    }

    if (mounted) {
      setState(() {
        _items = sugs;
        _open = sugs.isNotEmpty;
        _loading = false;
      });
    }
  }

  /// Parse single Mapy.cz Suggest item into a UI-friendly row.
  /// Returns null for items that have no usable name.
  _Sug? _parseSuggestion(dynamic it) {
    final name = (it['name'] as String?)?.trim() ?? '';
    final label = (it['label'] as String?)?.trim() ?? '';
    final location = (it['location'] as String?)?.trim() ?? '';
    final zip = (it['zip'] as String?)?.trim() ?? '';
    final type = (it['type'] as String?) ?? '';
    final pos = it['position'] as Map<String, dynamic>?;
    final rs = (it['regionalStructure'] as List?) ?? [];
    final lat = (pos?['lat'] as num?)?.toDouble();
    final lng = (pos?['lon'] as num?)?.toDouble();

    // Skip degenerate items (no name AND no label)
    if (name.isEmpty && label.isEmpty) return null;

    final primary = name.isNotEmpty ? name : label;
    // Subtitle: prefer explicit "location" from API, else combined zip+region
    final region = _region(rs, 'regional.region') ??
        _region(rs, 'regional.country') ?? '';
    final secondary = location.isNotEmpty
        ? (zip.isNotEmpty ? '$zip · $location' : location)
        : [if (zip.isNotEmpty) zip, if (region.isNotEmpty) region].join(' · ');

    // Structured parts for the selection callback
    String street = '';
    String city = '';
    switch (type) {
      case 'regional.address':
        street = name;
        city = _region(rs, 'regional.municipality') ??
            _region(rs, 'regional.municipality_part') ?? '';
        break;
      case 'regional.street':
        street = name;
        city = _region(rs, 'regional.municipality') ?? '';
        break;
      case 'regional.municipality':
      case 'regional.municipality_part':
        street = '';
        city = name;
        break;
      case 'poi':
        // Pokud POI, vezmeme lokalitu jako city
        street = name;
        city = _region(rs, 'regional.municipality') ?? '';
        break;
      default:
        // Unknown — pokus o nejlepší odhad
        final maybeCity = _region(rs, 'regional.municipality');
        if (maybeCity != null && maybeCity != name) {
          street = name;
          city = maybeCity;
        } else {
          city = name;
        }
    }

    return _Sug(
      primary: primary,
      secondary: secondary,
      street: street,
      city: city,
      zip: zip,
      lat: lat,
      lng: lng,
      icon: _iconForType(type),
    );
  }

  static IconData _iconForType(String type) {
    switch (type) {
      case 'regional.address':
        return Icons.home_outlined;
      case 'regional.street':
        return Icons.signpost_outlined;
      case 'regional.municipality':
      case 'regional.municipality_part':
        return Icons.location_city;
      case 'poi':
        return Icons.place_outlined;
      default:
        return Icons.place;
    }
  }

  String? _region(List rs, String type) {
    for (final r in rs) {
      if (r['type'] == type) return r['name'] as String?;
    }
    return null;
  }

  void _tap(_Sug s) {
    final display = [
      if (s.street.isNotEmpty) s.street,
      [if (s.zip.isNotEmpty) s.zip, if (s.city.isNotEmpty) s.city].join(' '),
    ].where((x) => x.isNotEmpty).join(', ');

    _ctrl.text = display.isNotEmpty ? display : s.primary;
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    setState(() {
      _items = [];
      _open = false;
    });
    _focus.unfocus();
    widget.onSelected(AddressSuggestion(
      street: s.street,
      city: s.city,
      zip: s.zip,
      lat: s.lat,
      lng: s.lng,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: MotoGoColors.g200, width: 1.5),
        ),
        child: TextField(
          controller: _ctrl,
          focusNode: _focus,
          onChanged: _onChange,
          style: const TextStyle(fontSize: 13, color: MotoGoColors.black),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle:
                const TextStyle(fontSize: 12, color: MotoGoColors.g400),
            prefixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: MotoGoColors.g400)))
                : const Icon(Icons.search,
                    size: 18, color: MotoGoColors.g400),
            suffixIcon: _ctrl.text.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      clear();
                      widget.onCleared?.call();
                    },
                    child: const Icon(Icons.close,
                        size: 18, color: MotoGoColors.g400))
                : null,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
      ),
      if (_open && _items.isNotEmpty)
        TextFieldTapRegion(
          child: Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 280),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: MotoGoColors.g200),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x1A0F1A14),
                    blurRadius: 20,
                    offset: Offset(0, 4))
              ],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _items.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: MotoGoColors.g100),
              itemBuilder: (_, i) {
                final s = _items[i];
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _tap(s),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(s.icon,
                              size: 16,
                              color: MotoGoColors.greenDarker),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.primary,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: MotoGoColors.black),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              if (s.secondary.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(s.secondary,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: MotoGoColors.g400),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
    ]);
  }
}

class _Sug {
  final String primary;
  final String secondary;
  final String street;
  final String city;
  final String zip;
  final double? lat, lng;
  final IconData icon;
  const _Sug({
    required this.primary,
    required this.secondary,
    required this.street,
    required this.city,
    required this.zip,
    required this.lat,
    required this.lng,
    required this.icon,
  });
}

class AddressSuggestion {
  final String street, city, zip;
  final double? lat, lng;
  const AddressSuggestion({
    required this.street,
    required this.city,
    required this.zip,
    this.lat,
    this.lng,
  });
}
