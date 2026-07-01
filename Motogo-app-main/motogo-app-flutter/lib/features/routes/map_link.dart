import 'package:latlong2/latlong.dart';

import '../../core/supabase_client.dart';

/// Dekódování bodů trasy ze sdíleného odkazu — Mapy.com i Google Maps.
/// Sdílí algoritmus s velin/src/lib/mapyRoute.js a edge fn resolve-mapy-route.

const _alphabet =
    '0ABCD2EFGH4IJKLMN6OPQRST8UVWXYZ-1abcd3efgh5ijklmn7opqrst9uvwxyz.';

double _r6(double v) => (v * 1e6).round() / 1e6;

int _parseNumber(List<String> arr, int count) {
  var result = 0;
  var i = count;
  while (i > 0) {
    if (arr.isEmpty) throw const FormatException('Neplatná data trasy (rc)');
    final ch = arr.removeLast();
    final index = _alphabet.indexOf(ch);
    if (index == -1) continue;
    result = (result << 6) + index;
    i--;
  }
  return result;
}

/// Dekóduje Mapy.cz `rc` (delta-kódování) → pole bodů v pořadí trasy.
List<LatLng> decodeMapyRc(String? rc) {
  if (rc == null || rc.isEmpty) return const [];
  const five = (1 + 2) << 4;
  const three = 1 << 5;
  final results = <LatLng>[];
  final coords = [0, 0];
  var ci = 0;
  final arr = rc.trim().split('').reversed.toList();
  while (arr.isNotEmpty) {
    var num = _parseNumber(arr, 1);
    if ((num & five) == five) {
      num -= five;
      num = ((num & 15) << 24) + _parseNumber(arr, 4);
      coords[ci] = num;
    } else if ((num & three) == three) {
      num = ((num & 15) << 12) + _parseNumber(arr, 2);
      num -= 1 << 15;
      coords[ci] += num;
    } else {
      num = ((num & 31) << 6) + _parseNumber(arr, 1);
      num -= 1 << 10;
      coords[ci] += num;
    }
    if (ci != 0) {
      final lng = (coords[0] * 360) / (1 << 28) - 180;
      final lat = (coords[1] * 180) / (1 << 28) - 90;
      results.add(LatLng(_r6(lat), _r6(lng)));
    }
    ci = (ci + 1) % 2;
  }
  return results;
}

String? rcFromUrl(String url) {
  try {
    return Uri.parse(url).queryParameters['rc'];
  } catch (_) {
    return null;
  }
}

bool isMapyUrl(String url) =>
    RegExp(r'mapy\.(?:com|cz)', caseSensitive: false).hasMatch(url);
bool isMapyShare(String url) =>
    RegExp(r'mapy\.(?:com|cz)/s/', caseSensitive: false).hasMatch(url);
bool isGoogleUrl(String url) => RegExp(
        r'(?:google\.[a-z.]+/maps|maps\.app\.goo\.gl|goo\.gl/maps)',
        caseSensitive: false)
    .hasMatch(url);
bool isGoogleShare(String url) => RegExp(
        r'(?:maps\.app\.goo\.gl|goo\.gl/maps)/',
        caseSensitive: false)
    .hasMatch(url);

/// Body trasy z PLNÉ Google Maps URL (data !1d/!2d, ?api=1, /@lat,lng).
List<LatLng> decodeGoogleRouteCoords(String url) {
  final out = <LatLng>[];
  final re = RegExp(r'!1d(-?\d+(?:\.\d+)?)!2d(-?\d+(?:\.\d+)?)');
  for (final m in re.allMatches(url)) {
    final lng = double.tryParse(m.group(1)!);
    final lat = double.tryParse(m.group(2)!);
    if (lat != null && lng != null) out.add(LatLng(_r6(lat), _r6(lng)));
  }
  if (out.isNotEmpty) return out;
  try {
    final q = Uri.parse(url).queryParameters;
    void pushLL(String? val) {
      if (val == null) return;
      final p = val.split(',').map((x) => double.tryParse(x.trim())).toList();
      if (p.length >= 2 && p[0] != null && p[1] != null) {
        out.add(LatLng(_r6(p[0]!), _r6(p[1]!)));
      }
    }

    pushLL(q['origin']);
    final wp = q['waypoints'];
    if (wp != null) wp.split('|').forEach(pushLL);
    pushLL(q['destination']);
    if (out.isNotEmpty) return out;
    final at = RegExp(r'@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)').firstMatch(url);
    if (at != null) {
      final lat = double.tryParse(at.group(1)!);
      final lng = double.tryParse(at.group(2)!);
      if (lat != null && lng != null) out.add(LatLng(_r6(lat), _r6(lng)));
    }
    final pl = RegExp(r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)').firstMatch(url);
    if (out.isEmpty && pl != null) {
      final lat = double.tryParse(pl.group(1)!);
      final lng = double.tryParse(pl.group(2)!);
      if (lat != null && lng != null) out.add(LatLng(_r6(lat), _r6(lng)));
    }
  } catch (_) {}
  return out;
}

/// Z textu (URL i <iframe src=…>) vytáhne odkaz + poskytovatele.
({String url, String provider})? extractMapUrl(String text) {
  final t = text.trim();
  final mapySrc = RegExp(r'''src=["']([^"']*mapy\.(?:com|cz)[^"']*)["']''',
          caseSensitive: false)
      .firstMatch(t);
  if (mapySrc != null) return (url: mapySrc.group(1)!, provider: 'mapy');
  final mapyUrl = RegExp(r'''https?://[^\s"']*mapy\.(?:com|cz)[^\s"']*''',
          caseSensitive: false)
      .firstMatch(t);
  if (mapyUrl != null) return (url: mapyUrl.group(0)!, provider: 'mapy');
  final gUrl = RegExp(
          r'''https?://[^\s"']*(?:google\.[a-z.]+/maps|maps\.app\.goo\.gl|goo\.gl/maps)[^\s"']*''',
          caseSensitive: false)
      .firstMatch(t);
  if (gUrl != null) return (url: gUrl.group(0)!, provider: 'google');
  return null;
}

/// Výsledek dekódování odkazu: body trasy + normalizovaná URL.
class MapLinkResult {
  final List<LatLng> waypoints;
  final String url;
  const MapLinkResult(this.waypoints, this.url);
}

/// Dekóduje libovolný odkaz na body trasy. Plnou URL zvládne lokálně;
/// zkrácené odkazy (mapy.com/s/… , maps.app.goo.gl/…) rozbalí edge fn
/// `resolve-mapy-route`. Vyhodí Exception s čitelnou zprávou při neúspěchu.
Future<MapLinkResult> decodeMapLink(String raw) async {
  final detected = extractMapUrl(raw);
  final url = detected?.url ?? raw.trim();
  if (url.isEmpty) throw 'Vlož odkaz na Mapy.com nebo Google Maps.';
  final isGoogle = detected?.provider == 'google' || isGoogleUrl(url);

  // Lokální dekódování plných URL.
  if (isGoogle) {
    if (!isGoogleShare(url)) {
      final pts = decodeGoogleRouteCoords(url);
      if (pts.isNotEmpty) return MapLinkResult(pts, url);
    }
  } else {
    final rc = rcFromUrl(url);
    if (rc != null) {
      final pts = decodeMapyRc(rc);
      if (pts.isNotEmpty) return MapLinkResult(pts, url);
    }
  }

  // Zkrácený odkaz → edge fn.
  try {
    final res = await MotoGoSupabase.client.functions.invoke(
      'resolve-mapy-route',
      body: {'url': url},
    );
    final data = res.data;
    if (data is Map && data['success'] == true) {
      final wp = <LatLng>[];
      final list = data['waypoints'];
      if (list is List) {
        for (final p in list) {
          if (p is Map) {
            final lat = (p['lat'] as num?)?.toDouble();
            final lng = (p['lng'] as num?)?.toDouble();
            if (lat != null && lng != null) wp.add(LatLng(lat, lng));
          }
        }
      }
      if (wp.isEmpty && data['rc'] is String) {
        wp.addAll(decodeMapyRc(data['rc'] as String));
      }
      if (wp.isNotEmpty) {
        return MapLinkResult(wp, (data['url'] as String?) ?? url);
      }
      throw 'V odkazu se nenašly žádné body trasy.';
    }
    throw (data is Map && data['error'] is String)
        ? data['error'] as String
        : 'Rozbalení odkazu selhalo.';
  } catch (e) {
    throw e is String ? e : 'Odkaz se nepodařilo načíst: $e';
  }
}
