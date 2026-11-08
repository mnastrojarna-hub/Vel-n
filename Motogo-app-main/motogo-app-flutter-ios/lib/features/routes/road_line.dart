import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'routes_provider.dart' show RouteProfile, fetchMapyRoute;

/// Čára trasy VŽDY po silnici — pokyn majitele 2026-11-08: „všechny trasy se
/// všude zobrazovaly přepočítané po silnici a ne jen přímky mezi body“.
///
/// Klíč = zastávky v pořadí + profil (doporučené / nejrychlejší / nejkratší).
/// Výsledek drží paměťová cache ve `fetchMapyRouteInfo`, takže opakované
/// zobrazení téže trasy API nevolá. Když routing selže (bez signálu, výpadek
/// API), vrací se PRÁZDNÁ čára — nikdy rovné spojnice zastávek; provider je
/// autoDispose, takže se při dalším zobrazení zkusí znovu.
@immutable
class RoadLineKey {
  final List<LatLng> stops;
  final RouteProfile profile;
  RoadLineKey(List<LatLng> stops, {this.profile = RouteProfile.recommended})
      : stops = List.unmodifiable(stops);

  String get _id {
    final b = StringBuffer(profile.name);
    for (final p in stops) {
      b.write('|${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}');
    }
    return b.toString();
  }

  @override
  bool operator ==(Object other) => other is RoadLineKey && other._id == _id;

  @override
  int get hashCode => _id.hashCode;
}

final roadLineProvider =
    FutureProvider.autoDispose.family<List<LatLng>, RoadLineKey>((ref, key) async {
  if (key.stops.length < 2) return const <LatLng>[];
  final geo = await fetchMapyRoute(key.stops, profile: key.profile);
  if (geo != null && geo.length >= 2) return geo;
  retryRoadLineLater(ref, key._id);
  return const <LatLng>[];
});

/// Neúspěšný routing se nesmí zapamatovat na celý běh appky (providery tras
/// žijí, dokud appka běží): provider se za chvíli spočítá znovu — nejvýš
/// [_kRetries]× pro tutéž trasu, ať appka bez signálu nesype dotaz za dotazem.
void retryRoadLineLater(Ref ref, String id) {
  final n = _retries[id] ?? 0;
  if (n >= _kRetries) return;
  _retries[id] = n + 1;
  final t = Timer(Duration(seconds: 20 * (n + 1)), ref.invalidateSelf);
  ref.onDispose(t.cancel);
}

const int _kRetries = 3;
final Map<String, int> _retries = {};
