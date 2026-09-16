import 'package:latlong2/latlong.dart';

/// Model „Mojí jízdy" — projetá trasa jezdce (tabulky `user_rides` +
/// `user_ride_points`, čte se přes RPC `get_my_rides` / `get_booking_rides`).
///
/// Jízda vzniká AUTOMATICKY při aktivní výpůjčce, když má zákazník povolenou
/// polohu (stopa GPS + motorka + rezervace), nebo ručně. Body jízdy jsou
/// start / cíl a zastávky (body zájmu) — ke každé jdou přidat fotky a popisek.

double? _toD(dynamic v) =>
    v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));
int? _toI(dynamic v) =>
    v == null ? null : (v is num ? v.toInt() : int.tryParse(v.toString()));

/// Bod na jízdě: `start` / `end` (krajní body stopy) nebo `stop` (zastávka).
class RidePoint {
  final String id;
  final String kind;
  final String name;
  final String? note;
  final double lat;
  final double lng;
  final List<String> photos;
  final int sortOrder;
  final DateTime? happenedAt;

  const RidePoint({
    required this.id,
    this.kind = 'stop',
    this.name = '',
    this.note,
    required this.lat,
    required this.lng,
    this.photos = const [],
    this.sortOrder = 0,
    this.happenedAt,
  });

  LatLng get latLng => LatLng(lat, lng);
  bool get isStart => kind == 'start';
  bool get isEnd => kind == 'end';
  bool get isStop => kind == 'stop';

  static RidePoint? fromJson(Map<String, dynamic> j) {
    final lat = _toD(j['lat']);
    final lng = _toD(j['lng']);
    if (lat == null || lng == null) return null;
    final ph = j['photos'];
    return RidePoint(
      id: j['id']?.toString() ?? '',
      kind: j['kind']?.toString() ?? 'stop',
      name: j['name']?.toString() ?? '',
      note: (j['note']?.toString().trim().isEmpty ?? true) ? null : j['note'].toString(),
      lat: lat,
      lng: lng,
      photos: ph is List
          ? ph.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
          : const [],
      sortOrder: _toI(j['sort_order']) ?? 0,
      happenedAt: DateTime.tryParse(j['happened_at']?.toString() ?? ''),
    );
  }
}

/// Jedna jízda (zážitek) se stopou a body.
class UserRide {
  final String id;
  final String? bookingId;
  final String? motoId;
  final String? motoName;
  final String name;
  final String? description;
  final String source; // auto = záznam GPS, manual = ručně poskládaná
  final List<LatLng> track;
  final DateTime startedAt;
  final DateTime? endedAt;
  final double distanceKm;
  final int? durationMin;
  final double? maxSpeedKmh;
  final bool isRecording;
  final String visibility; // private / public
  final String status; // approved / hidden (moderace Velínem)
  final String? coverImage;
  final List<RidePoint> points;

  const UserRide({
    required this.id,
    this.bookingId,
    this.motoId,
    this.motoName,
    this.name = '',
    this.description,
    this.source = 'auto',
    this.track = const [],
    required this.startedAt,
    this.endedAt,
    this.distanceKm = 0,
    this.durationMin,
    this.maxSpeedKmh,
    this.isRecording = false,
    this.visibility = 'private',
    this.status = 'approved',
    this.coverImage,
    this.points = const [],
  });

  bool get isPublic => visibility == 'public';
  bool get isHidden => status == 'hidden';

  /// Zastávky (bez krajních bodů) v pořadí, jak je jezdec projel.
  List<RidePoint> get stops => points.where((p) => p.isStop).toList();

  /// Všechny fotky jízdy (napříč body) — první z nich je titulní náhled.
  List<String> get allPhotos => [
        if (coverImage != null && coverImage!.isNotEmpty) coverImage!,
        for (final p in points) ...p.photos,
      ];

  /// Body pro vykreslení mapy — stopa, jinak aspoň krajní body a zastávky.
  List<LatLng> get mapPoints =>
      track.length >= 2 ? track : points.map((p) => p.latLng).toList();

  static UserRide? fromJson(Map<String, dynamic> j) {
    final id = j['id']?.toString();
    if (id == null || id.isEmpty) return null;

    final track = <LatLng>[];
    final t = j['track'];
    if (t is List) {
      for (final p in t) {
        if (p is List && p.length >= 2) {
          final lat = _toD(p[0]);
          final lng = _toD(p[1]);
          if (lat != null && lng != null) track.add(LatLng(lat, lng));
        }
      }
    }

    final pts = <RidePoint>[];
    final rawPts = j['points'];
    if (rawPts is List) {
      for (final p in rawPts) {
        if (p is Map) {
          final pt = RidePoint.fromJson(Map<String, dynamic>.from(p));
          if (pt != null) pts.add(pt);
        }
      }
    }
    pts.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return UserRide(
      id: id,
      bookingId: j['booking_id']?.toString(),
      motoId: j['moto_id']?.toString(),
      motoName: j['moto_name']?.toString(),
      name: j['name']?.toString() ?? '',
      description: (j['description']?.toString().trim().isEmpty ?? true)
          ? null
          : j['description'].toString(),
      source: j['source']?.toString() ?? 'auto',
      track: track,
      startedAt: DateTime.tryParse(j['started_at']?.toString() ?? '') ?? DateTime.now(),
      endedAt: DateTime.tryParse(j['ended_at']?.toString() ?? ''),
      distanceKm: _toD(j['distance_km']) ?? 0,
      durationMin: _toI(j['duration_min']),
      maxSpeedKmh: _toD(j['max_speed_kmh']),
      isRecording: j['is_recording'] == true,
      visibility: j['visibility']?.toString() ?? 'private',
      status: j['status']?.toString() ?? 'approved',
      coverImage: j['cover_image']?.toString(),
      points: pts,
    );
  }
}
