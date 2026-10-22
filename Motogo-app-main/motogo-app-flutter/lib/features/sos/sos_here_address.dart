import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/i18n/i18n_provider.dart';
import '../../core/native/gps_service.dart';
import '../../core/theme.dart';
import '../../core/widgets/address_autocomplete_field.dart' show AddressSuggestion;
import '../../core/widgets/error_feedback.dart' show explainLocation;
import '../routes/routes_provider.dart' show mapyApiKey;
import 'sos_location.dart' show sosLocate;

/// Adresa místa [lat], [lng]: Mapy.com rgeocode, záložně Nominatim, a když
/// ani jedno neodpoví (bez signálu), aspoň souřadnice — obsluha podle nich
/// náhradu najde a zákazník je může přepsat.
Future<AddressSuggestion> sosAddressAt(double lat, double lng,
    {http.Client? client}) async {
  Future<http.Response> get(Uri u, Map<String, String> h) =>
      client != null ? client.get(u, headers: h) : http.get(u, headers: h);
  try {
    final r = await get(
        Uri.https('api.mapy.cz', '/v1/rgeocode', {
          'lat': '$lat',
          'lon': '$lng',
          'lang': 'cs',
          'apikey': mapyApiKey,
        }),
        const {'Accept': 'application/json'}).timeout(const Duration(seconds: 5));
    if (r.statusCode == 200) {
      final items = (jsonDecode(r.body)['items'] as List?) ?? const [];
      if (items.isNotEmpty && items.first is Map) {
        final it = items.first as Map;
        var city = '';
        for (final x in (it['regionalStructure'] as List?) ?? const []) {
          if (x is Map && x['type'] == 'regional.municipality') {
            city = '${x['name'] ?? ''}';
            break;
          }
        }
        final street = '${it['name'] ?? ''}'.trim();
        if (street.isNotEmpty || city.isNotEmpty) {
          return AddressSuggestion(
              street: street, city: city, zip: '${it['zip'] ?? ''}', lat: lat, lng: lng);
        }
      }
    }
  } catch (_) {}
  try {
    final r = await get(
        Uri.https('nominatim.openstreetmap.org', '/reverse', {
          'format': 'json',
          'lat': '$lat',
          'lon': '$lng',
          'zoom': '18',
          'addressdetails': '1',
        }),
        const {'User-Agent': 'MotoGo24/2.0'}).timeout(const Duration(seconds: 5));
    if (r.statusCode == 200) {
      final a = (jsonDecode(r.body)['address'] as Map?) ?? const {};
      final road = '${a['road'] ?? ''}';
      final house = '${a['house_number'] ?? ''}';
      final city = '${a['city'] ?? a['town'] ?? a['village'] ?? ''}';
      final street = road.isEmpty ? '' : (house.isEmpty ? road : '$road $house');
      if (street.isNotEmpty || city.isNotEmpty) {
        return AddressSuggestion(
            street: street, city: city, zip: '${a['postcode'] ?? ''}', lat: lat, lng: lng);
      }
    }
  } catch (_) {}
  return AddressSuggestion(
      street: 'GPS ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
      city: '',
      zip: '',
      lat: lat,
      lng: lng);
}

/// „Kde právě jsi“ nad adresou přistavení náhrady (majitel 2026-10-22:
/// nic nevyplňovat dvakrát — polohu appka při hlášení už poslala). Když je
/// poloha povolená, adresa se zjistí hned a ukáže se k jednomu klepnutí;
/// jinak klepnutí polohu teprve zjistí (případně se zeptá na oprávnění).
/// Pole adresy zůstává upravitelné — zákazník se může přesunout.
class SosHereAddress extends StatefulWidget {
  final ValueChanged<AddressSuggestion> onPick;

  /// Test: místo GPS a geokódování.
  final Future<AddressSuggestion?> Function()? locate;
  const SosHereAddress({super.key, required this.onPick, this.locate});

  @override
  State<SosHereAddress> createState() => _SosHereAddressState();
}

class _SosHereAddressState extends State<SosHereAddress> {
  AddressSuggestion? _found;
  bool _busy = false;
  bool _useWhenFound = false;
  bool _used = false;

  @override
  void initState() {
    super.initState();
    _prefetch();
  }

  Future<void> _prefetch() async {
    if (widget.locate == null && await GpsService.status(request: false) != GpsStatus.ok) return;
    await _locate(silent: true);
  }

  Future<void> _locate({bool silent = false}) async {
    if (!mounted) return;
    setState(() => _busy = true);
    AddressSuggestion? s;
    GpsStatus status = GpsStatus.ok;
    if (widget.locate != null) {
      s = await widget.locate!();
      if (s == null) status = GpsStatus.noFix;
    } else {
      final r = await sosLocate();
      final pos = r.pos;
      status = r.status;
      if (pos != null) s = await sosAddressAt(pos.latitude, pos.longitude);
    }
    if (!mounted) return;
    final use = !silent || _useWhenFound;
    setState(() {
      _busy = false;
      _found = s ?? _found;
      _useWhenFound = false;
    });
    if (s != null && use) _use(s);
    if (s == null && use) await explainLocation(context, status, snack: true);
  }

  void _use(AddressSuggestion s) {
    widget.onPick(s);
    setState(() => _used = true);
  }

  void _tap() {
    if (_busy) {
      _useWhenFound = true; // dojde-li zjišťování, adresa se rovnou použije
      return;
    }
    final f = _found;
    f != null ? _use(f) : _locate();
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final f = _found;
    final addr = f == null ? '' : [f.street, f.city].where((x) => x.isNotEmpty).join(', ');
    final sub = _busy
        ? tr.tr('gettingLocation')
        : _used
            ? tr.tr('sosHereUsed')
            : (addr.isNotEmpty ? addr : tr.tr('sosHereTap'));
    return Semantics(
      button: true,
      label: '${tr.tr('sosHereTitle')}. $sub',
      excludeSemantics: true,
      child: InkWell(
        onTap: _tap,
        borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: MotoGoColors.greenPale,
            borderRadius: BorderRadius.circular(MotoGoTheme.radiusSm),
            border: Border.all(color: MotoGoColors.green.withValues(alpha: 0.5)),
          ),
          child: Row(children: [
            SizedBox(
              width: 20,
              height: 20,
              child: _busy
                  ? const CircularProgressIndicator(strokeWidth: 2, color: MotoGoColors.greenDark)
                  : Icon(_used ? Icons.check_circle : Icons.my_location,
                      size: 20, color: MotoGoColors.greenDark),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr.tr('sosHereTitle'),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800, color: MotoGoColors.greenDarker)),
                const SizedBox(height: 2),
                Text(sub,
                    style: const TextStyle(fontSize: 12, height: 1.3, color: MotoGoColors.black)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
