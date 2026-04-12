import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../theme.dart';

/// Single-line address autocomplete using Mapy.cz Suggest API.
/// Phase 1: user types → city suggestions.
/// Phase 2: after city selected → user types street → address suggestions.
class AddressAutocompleteField extends StatefulWidget {
  final ValueChanged<AddressSuggestion> onSelected;
  final VoidCallback? onCleared;
  final String hint;

  const AddressAutocompleteField({
    super.key,
    required this.onSelected,
    this.onCleared,
    this.hint = 'Zadejte město…',
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
  String? _city;
  String? _zip;
  bool _open = false;
  bool _loading = false;

  static const _key = 'Ag9d2QJD0i8_fA07r6GDDaZ4qV9aZDGMhWn_HhQ_rFs';
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
    // TextFieldTapRegion prevents focus loss when tapping suggestions,
    // so this only fires when user taps truly outside → safe to hide.
    if (!_focus.hasFocus && mounted) {
      setState(() => _open = false);
    }
  }

  /// Set address externally (GPS / map picker).
  void setAddress(String street, String city, String zip) {
    _city = city;
    _zip = zip;
    _ctrl.text = street.isNotEmpty ? '$street, $city' : city;
    setState(() => _open = false);
  }

  void clear() {
    _ctrl.clear();
    _city = null;
    _zip = null;
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
      _city = null;
      _zip = null;
      setState(() {
        _items = [];
        _open = false;
      });
      widget.onCleared?.call();
      return;
    }
    if (_city != null && !v.startsWith(_city!)) {
      _city = null;
      _zip = null;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _fetch(v));
  }

  Future<void> _fetch(String q) async {
    if (q.trim().length < 2) return;
    if (mounted) setState(() => _loading = true);

    try {
      final url = _city == null ? _cityUrl(q) : _streetUrl(q);
      if (url == null) {
        if (mounted) setState(() {
          _items = [];
          _open = false;
          _loading = false;
        });
        return;
      }
      final res = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 5));

      if (!mounted) return;

      if (res.statusCode != 200) {
        debugPrint('[AddressAutocomplete] API ${res.statusCode}: '
            '${res.body.length > 200 ? res.body.substring(0, 200) : res.body}');
        setState(() => _loading = false);
        return;
      }

      final body = jsonDecode(res.body);
      final items = (body['items'] as List?) ?? [];
      final sugs = <_Sug>[];
      for (final it in items) {
        try {
          sugs.add(_parseSuggestion(it));
        } catch (e) {
          debugPrint('[AddressAutocomplete] Parse error: $e');
        }
      }
      if (mounted) {
        setState(() {
          _items = sugs;
          _open = sugs.isNotEmpty;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[AddressAutocomplete] Fetch error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _cityUrl(String q) =>
      '$_base/suggest?query=${Uri.encodeComponent(q)}'
      '&lang=cs&limit=6&type=regional.municipality'
      '&locality=cz&apikey=$_key';

  String? _streetUrl(String q) {
    final street =
        q.substring(_city!.length).replaceFirst(RegExp(r'^,?\s*'), '');
    if (street.length < 2) return null;
    return '$_base/suggest'
        '?query=${Uri.encodeComponent('$street, $_city')}'
        '&lang=cs&limit=6&type=regional.address'
        '&locality=cz&apikey=$_key';
  }

  _Sug _parseSuggestion(dynamic it) {
    final name = (it['name'] as String?) ?? '';
    final pos = it['position'] as Map<String, dynamic>?;
    final zip = (it['zip'] as String?) ?? '';
    final rs = (it['regionalStructure'] as List?) ?? [];
    final lat = (pos?['lat'] as num?)?.toDouble();
    final lng = (pos?['lon'] as num?)?.toDouble();

    if (_city == null) {
      final district = _region(rs, 'regional.district') ??
          _region(rs, 'regional.region') ??
          '';
      final label = '$name${zip.isNotEmpty ? '  $zip' : ''}'
          '${district.isNotEmpty ? ' · $district' : ''}';
      return _Sug(name, label, null, name, zip, lat, lng, true);
    } else {
      final label = (it['label'] as String?) ?? name;
      final city = _region(rs, 'regional.municipality') ?? _city!;
      return _Sug(
          name, label, name, city,
          zip.isNotEmpty ? zip : (_zip ?? ''),
          lat, lng, false);
    }
  }

  String? _region(List rs, String type) {
    for (final r in rs) {
      if (r['type'] == type) return r['name'] as String?;
    }
    return null;
  }

  void _tap(_Sug s) {
    if (s.isCity) {
      _city = s.city;
      _zip = s.zip;
      _ctrl.text = '${s.city}, ';
      _ctrl.selection =
          TextSelection.collapsed(offset: _ctrl.text.length);
      setState(() {
        _items = [];
        _open = false;
      });
      _focus.requestFocus();
    } else {
      _ctrl.text = '${s.street ?? s.name}, ${s.city}';
      _city = s.city;
      _zip = s.zip;
      setState(() {
        _items = [];
        _open = false;
      });
      widget.onSelected(AddressSuggestion(
        street: s.street ?? s.name,
        city: s.city,
        zip: s.zip,
        lat: s.lat,
        lng: s.lng,
      ));
    }
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
            hintText: _city != null ? 'Ulice a č.p.…' : widget.hint,
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
        // TextFieldTapRegion prevents focus loss when tapping
        // suggestion items — so onTap always fires correctly.
        TextFieldTapRegion(
          child: Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 220),
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
                    child: Row(children: [
                      Icon(
                          s.isCity
                              ? Icons.location_city
                              : Icons.place,
                          size: 16,
                          color: MotoGoColors.greenDarker),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(s.label,
                            style: const TextStyle(
                                fontSize: 12,
                                color: MotoGoColors.black),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ]),
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
  final String name, label;
  final String? street;
  final String city, zip;
  final double? lat, lng;
  final bool isCity;
  const _Sug(this.name, this.label, this.street, this.city, this.zip,
      this.lat, this.lng, this.isCity);
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
