import 'package:latlong2/latlong.dart';

/// Pomocné parsování čísla z dynamic (DB vrací num/string).
double? _toD(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int? _toI(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

/// Normalizace textu pro vyhledávání — malá písmena bez diakritiky.
/// (Dart nemá unicodedata; mapa pokrývá evropské jazyky appky vč. cs/pl/ro/sk.)
String searchNorm(String s) {
  const map = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'ą': 'a', 'ā': 'a',
    'č': 'c', 'ç': 'c', 'ć': 'c', 'ď': 'd', 'đ': 'd',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'ě': 'e', 'ę': 'e', 'ē': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i',
    'ľ': 'l', 'ĺ': 'l', 'ł': 'l', 'ň': 'n', 'ñ': 'n', 'ń': 'n',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o', 'ő': 'o', 'ō': 'o',
    'ř': 'r', 'ŕ': 'r', 'š': 's', 'ś': 's', 'ş': 's', 'ș': 's', 'ß': 'ss',
    'ť': 't', 'ţ': 't', 'ț': 't',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ů': 'u', 'ű': 'u', 'ū': 'u',
    'ý': 'y', 'ÿ': 'y', 'ž': 'z', 'ź': 'z', 'ż': 'z', 'æ': 'ae', 'œ': 'oe',
  };
  final sb = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final ch = String.fromCharCode(r);
    sb.write(map[ch] ?? ch);
  }
  return sb.toString();
}

/// Hloubková shoda dotazu: KAŽDÉ slovo dotazu se musí vyskytovat
/// v (už normalizovaném) textu `normBlob`. Bez diakritiky, bez velikosti písmen.
bool searchMatches(String normBlob, String query) {
  for (final tk in searchNorm(query).split(' ')) {
    final tok = tk.trim();
    if (tok.isEmpty) continue;
    if (!normBlob.contains(tok)) return false;
  }
  return true;
}

/// Přidá do bufferu name+description ze všech jazyků `translations`.
void _appendTranslations(StringBuffer sb, Map? translations) {
  translations?.forEach((_, v) {
    if (v is Map) {
      final n = v['name'];
      final d = v['description'];
      if (n is String && n.isNotEmpty) sb..write(' ')..write(n);
      if (d is String && d.isNotEmpty) sb..write(' ')..write(d);
    }
  });
}

// Cache vyhledávacích textů (objekty z providerů jsou stabilní).
final Expando<String> _poiBlobCache = Expando<String>();
final Expando<String> _routeBlobCache = Expando<String>();
final Expando<String> _routeNameBlobCache = Expando<String>();

/// Lokalizace pole z jsonb `translations = {lang:{field:value}}`.
String _loc(Map? translations, String lang, String field, String fallback) {
  if (translations == null) return fallback;
  final l = translations[lang];
  if (l is Map) {
    final v = l[field];
    if (v is String && v.trim().isNotEmpty) return v;
  }
  return fallback;
}

/// Bod zájmu na trase.
class RoutePoi {
  final String id;
  final String name;
  final String? description;
  final double? lat;
  final double? lng;
  final String? imageUrl;
  final List<String> images;
  final Map? translations;
  final double? avgRating; // průměrné hodnocení (z RPC)
  final int ratingCount; // počet hodnocení
  final bool isUserPoi; // bod zájmu od uživatele (komunitní)
  final bool isCatalogPoi; // samostatný bod z katalogu points_of_interest
  final String? category; // explicitní kategorie z backendu (food/castle/…), jinak null

  const RoutePoi({
    required this.id,
    required this.name,
    this.description,
    this.lat,
    this.lng,
    this.imageUrl,
    this.images = const [],
    this.translations,
    this.avgRating,
    this.ratingCount = 0,
    this.isUserPoi = false,
    this.isCatalogPoi = false,
    this.category,
  });

  LatLng? get latLng => (lat != null && lng != null) ? LatLng(lat!, lng!) : null;
  String? get cover => imageUrl ?? (images.isNotEmpty ? images.first : null);

  String nameFor(String lang) => _loc(translations, lang, 'name', name);
  String? descFor(String lang) =>
      description == null ? null : _loc(translations, lang, 'description', description!);

  /// Normalizovaný text pro hloubkové vyhledávání: název, popis, kategorie
  /// a všechny jazykové mutace (cachováno).
  String get searchBlob => _poiBlobCache[this] ??= _buildSearchBlob();
  String _buildSearchBlob() {
    final sb = StringBuffer(name);
    if (description != null) sb..write(' ')..write(description);
    if (category != null) sb..write(' ')..write(category);
    _appendTranslations(sb, translations);
    return searchNorm(sb.toString());
  }

  factory RoutePoi.fromJson(Map<String, dynamic> j) {
    return RoutePoi(
      id: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      description: j['description']?.toString(),
      lat: _toD(j['lat']),
      lng: _toD(j['lng']),
      imageUrl: j['image_url']?.toString(),
      images: (j['images'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      translations: j['translations'] is Map ? j['translations'] as Map : null,
      avgRating: _toD(j['avg_rating']),
      ratingCount: _toI(j['rating_count']) ?? 0,
      isUserPoi: j['is_user_poi'] == true,
      isCatalogPoi: j['is_catalog'] == true,
      category: (j['category']?.toString().trim().isNotEmpty ?? false)
          ? j['category'].toString().trim()
          : null,
    );
  }

  /// Bod zájmu navržený uživatelem (z RPC `get_user_pois`).
  factory RoutePoi.fromUserJson(Map<String, dynamic> j) {
    return RoutePoi(
      id: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      description: j['description']?.toString(),
      lat: _toD(j['lat']),
      lng: _toD(j['lng']),
      imageUrl: j['image_url']?.toString(),
      avgRating: _toD(j['avg_rating']),
      ratingCount: _toI(j['rating_count']) ?? 0,
      isUserPoi: true,
    );
  }
}

/// Doporučená trasa od pobočky.
class RouteItem {
  final String id;
  final String? branchId;
  final String name;
  final String? description;
  final String routeType; // 'loop' | 'poi'
  final double? distanceKm;
  final int? durationMin;
  final String? difficulty; // easy | medium | hard
  final List<LatLng> waypoints;
  final List<String> waypointLabels; // popisky průjezdních bodů (města/místa na cestě)
  final List<LatLng> geometry; // dekódovaná polyline (lat,lng)
  final String? mapyUrl;
  final String? coverImage;
  final List<String> images;
  final List<RoutePoi> pois;
  final Map? translations;
  final double? reviewAvg; // průměrné hodnocení trasy (recenze)
  final int reviewCount; // počet recenzí
  final List<String> countries; // ISO kódy zemí, kterými trasa vede (CZ, DE, …)

  const RouteItem({
    required this.id,
    this.branchId,
    required this.name,
    this.description,
    this.routeType = 'loop',
    this.distanceKm,
    this.durationMin,
    this.difficulty,
    this.waypoints = const [],
    this.waypointLabels = const [],
    this.geometry = const [],
    this.mapyUrl,
    this.coverImage,
    this.images = const [],
    this.pois = const [],
    this.translations,
    this.reviewAvg,
    this.reviewCount = 0,
    this.countries = const [],
  });

  bool get isLoop => routeType == 'loop';
  /// Vede trasa i mimo ČR?
  bool get isAbroad => countries.any((c) => c != 'CZ');
  String? get cover => coverImage ?? (images.isNotEmpty ? images.first : null);

  String nameFor(String lang) => _loc(translations, lang, 'name', name);
  String? descFor(String lang) =>
      description == null ? null : _loc(translations, lang, 'description', description!);

  /// Normalizovaný NÁZEV trasy ve všech jazycích (užší shoda — např. pro
  /// dohledání bodů podle názvu jejich trasy v katalogu POI).
  String get nameBlob => _routeNameBlobCache[this] ??= _buildNameBlob();
  String _buildNameBlob() {
    final sb = StringBuffer(name);
    translations?.forEach((_, v) {
      if (v is Map && v['name'] is String) sb..write(' ')..write(v['name']);
    });
    return searchNorm(sb.toString());
  }

  /// Normalizovaný text pro hloubkové vyhledávání trasy: název, popis,
  /// všechny jazykové mutace, popisky průjezdních bodů (města na cestě)
  /// a názvy/popisy všech bodů zájmu na trase (cachováno).
  String get searchBlob => _routeBlobCache[this] ??= _buildSearchBlob();
  String _buildSearchBlob() {
    final sb = StringBuffer(name);
    if (description != null) sb..write(' ')..write(description);
    for (final l in waypointLabels) {
      sb..write(' ')..write(l);
    }
    _appendTranslations(sb, translations);
    var blob = searchNorm(sb.toString());
    for (final p in pois) {
      blob = '$blob ${p.searchBlob}';
    }
    return blob;
  }

  factory RouteItem.fromJson(Map<String, dynamic> j) {
    // geometry = {coordinates:[[lng,lat],…]}  (GeoJSON pořadí)
    final geo = <LatLng>[];
    final g = j['geometry'];
    if (g is Map && g['coordinates'] is List) {
      for (final c in (g['coordinates'] as List)) {
        if (c is List && c.length >= 2) {
          final lng = _toD(c[0]);
          final lat = _toD(c[1]);
          if (lat != null && lng != null) geo.add(LatLng(lat, lng));
        }
      }
    }

    // waypoints = [{lat,lng,label,order}]
    final wps = <LatLng>[];
    final wpLabels = <String>[];
    final w = j['waypoints'];
    if (w is List) {
      for (final p in w) {
        if (p is Map) {
          final lat = _toD(p['lat']);
          final lng = _toD(p['lng']);
          if (lat != null && lng != null) {
            wps.add(LatLng(lat, lng));
            final label = p['label'];
            if (label is String && label.trim().isNotEmpty) wpLabels.add(label.trim());
          }
        }
      }
    }

    final poiList = <RoutePoi>[];
    final ps = j['pois'];
    if (ps is List) {
      for (final p in ps) {
        if (p is Map) poiList.add(RoutePoi.fromJson(Map<String, dynamic>.from(p)));
      }
    }

    return RouteItem(
      id: j['id']?.toString() ?? '',
      branchId: j['branch_id']?.toString(),
      name: j['name']?.toString() ?? '',
      description: j['description']?.toString(),
      routeType: j['route_type']?.toString() ?? 'loop',
      distanceKm: _toD(j['distance_km']),
      durationMin: _toI(j['duration_min']),
      difficulty: j['difficulty']?.toString(),
      waypoints: wps,
      waypointLabels: wpLabels,
      geometry: geo,
      mapyUrl: j['mapy_url']?.toString(),
      coverImage: j['cover_image']?.toString(),
      images: (j['images'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      pois: poiList,
      translations: j['translations'] is Map ? j['translations'] as Map : null,
      reviewAvg: _toD(j['review_avg']),
      reviewCount: _toI(j['review_count']) ?? 0,
      countries: (j['countries'] as List?)
              ?.map((e) => e.toString().toUpperCase())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const [],
    );
  }
}

/// Pobočka — startovní bod tras (jméno + GPS).
class RouteBranch {
  final String id;
  final String name;
  final String? city;
  final double? lat;
  final double? lng;

  const RouteBranch({required this.id, required this.name, this.city, this.lat, this.lng});

  LatLng? get latLng => (lat != null && lng != null) ? LatLng(lat!, lng!) : null;

  factory RouteBranch.fromJson(Map<String, dynamic> j) => RouteBranch(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        city: j['city']?.toString(),
        lat: _toD(j['gps_lat']),
        lng: _toD(j['gps_lng']),
      );
}

/// Sdružená data pro obrazovku tras.
class RoutesData {
  final List<RouteItem> routes;
  final Map<String, RouteBranch> branches;
  const RoutesData({required this.routes, required this.branches});

  /// Pobočky, které mají alespoň jednu trasu — v pořadí podle jména.
  List<RouteBranch> get branchesWithRoutes {
    final ids = routes.map((r) => r.branchId).whereType<String>().toSet();
    final list = ids.map((id) => branches[id]).whereType<RouteBranch>().toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }
}
