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

/// Rozdělí stopu na souvislé úseky a mezery mezi nimi — stejnou hranicí jako
/// server (`_ride_stats`): dlouhá pauza S POSUNEM je mezera, dlouhá pauza bez
/// posunu je jen stání na místě (semafor, tankování, focení).
///
/// Stopa BEZ časových značek (starý klient, ručně poskládaná jízda) se nedělí
/// vůbec — nemáme podle čeho, a řezat ji podle vzdálenosti by rozbilo ruční
/// trasy, které jsou rovnou spojnicí bodů záměrně.
List<RideSegment> _splitOnGaps(List<LatLng> track, List<int?> times) {
  if (track.isEmpty) return const [];
  if (track.length == 1) return [RideSegment(List.unmodifiable(track))];

  const dist = Distance();
  final out = <RideSegment>[];
  var current = <LatLng>[track.first];
  RideGap? pendingGap;
  int? prevTs = times.isNotEmpty ? times.first : null;

  for (var i = 1; i < track.length; i++) {
    final ts = i < times.length ? times[i] : null;
    final dt = (ts != null && prevTs != null) ? ts - prevTs : null;
    final km = dist.as(LengthUnit.Kilometer, track[i - 1], track[i]);
    final isGap =
        dt != null && dt > kRideGapSec && dt < 86400 && km > kRideStillKm;

    if (isGap) {
      out.add(RideSegment(List.unmodifiable(current), gapBefore: pendingGap));
      pendingGap = RideGap(
        from: track[i - 1],
        to: track[i],
        sec: dt,
        km: km,
      );
      current = <LatLng>[track[i]];
    } else {
      current.add(track[i]);
    }
    // Bod bez času si drží čas předchozího bodu — stejně jako server.
    if (ts != null) prevTs = ts;
  }
  out.add(RideSegment(List.unmodifiable(current), gapBefore: pendingGap));
  return List.unmodifiable(out);
}

/// Mezera ve stopě: appka běžela na pozadí bez signálu / s vypnutou polohou,
/// takže mezi dvěma body NEVÍME, kudy jezdec jel. Spojit je plnou čarou by
/// znamenalo tvrdit trasu, která se nestala.
class RideGap {
  final LatLng from;
  final LatLng to;
  final int sec; // jak dlouho jsme byli "slepí"
  final double km; // vzdušná čára přes mezeru (NE ujetá vzdálenost)

  const RideGap({
    required this.from,
    required this.to,
    required this.sec,
    required this.km,
  });
}

/// Souvislý úsek stopy (mezi dvěma mezerami) + mezera, která mu předchází.
class RideSegment {
  final List<LatLng> points;
  final RideGap? gapBefore;

  const RideSegment(this.points, {this.gapBefore});
}

/// Hranice pro rozdělení stopy — MUSÍ sedět se serverem (`_ride_stats`
/// v `20260921g_user_rides_real_track.sql`), jinak by appka ukazovala jiné
/// mezery, než z jakých server počítá kilometry.
const int kRideGapSec = 180; // delší pauza = už ne souvislá jízda
const double kRideStillKm = 0.05; // posun do 50 m = stál na místě, ne mezera

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

  /// Stopa rozdělená na souvislé úseky a mezery mezi nimi. Počítá se jednou
  /// při parsování (v `build()` by to u 4000 bodů byla zbytečná práce).
  final List<RideSegment> segments;
  final DateTime startedAt;
  final DateTime? endedAt;
  final double distanceKm;
  final int? durationMin; // celkový čas (start → konec)
  final int movingSec; // čas v pohybu
  final int idleSec; // čas stání (pauzy, zastávky, semafory)
  final int gapSec; // čas BEZ GPS signálu (km přes něj se nepočítají)
  final DateTime? lastFixAt; // kdy naposledy dorazil GPS bod
  final double? avgSpeedKmh; // průměr z času jízdy
  final double? maxSpeedKmh;
  final int elevationGainM; // nastoupáno
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
    this.segments = const [],
    required this.startedAt,
    this.endedAt,
    this.distanceKm = 0,
    this.durationMin,
    this.movingSec = 0,
    this.idleSec = 0,
    this.gapSec = 0,
    this.lastFixAt,
    this.avgSpeedKmh,
    this.maxSpeedKmh,
    this.elevationGainM = 0,
    this.isRecording = false,
    this.visibility = 'private',
    this.status = 'approved',
    this.coverImage,
    this.points = const [],
  });

  bool get isPublic => visibility == 'public';

  /// Čas jízdy v minutách (0 = stopa bez časových značek).
  int get movingMin => (movingSec / 60).round();

  /// Čas stání v minutách — pauzy, zastávky, semafory.
  int get idleMin => (idleSec / 60).round();

  /// Čas bez GPS signálu v minutách.
  int get gapMin => (gapSec / 60).round();

  /// Má jízda díry ve stopě? (Pak je „celkem ujeto" jen to, co víme jistě.)
  bool get hasGaps => gapSec > 0 || segments.length > 1;

  /// Celkový čas jízdy v minutách (fallback ze součtu jízda + stání + mezery).
  int get totalMin => durationMin ?? ((movingSec + idleSec + gapSec) / 60).round();

  /// Průměrná rychlost za čas, kdy jsme o jezdci VĚDĚLI — km/h.
  ///
  /// Mezery se odečítají: kilometry přes ně server nezapočítal, takže dělit
  /// jimi by průměr uměle srazilo (u jízdy s 32 h bez signálu klidně 5×).
  double? get avgOverallKmh {
    final t = totalMin - gapMin;
    if (t <= 0 || distanceKm <= 0) return null;
    final v = distanceKm / (t / 60);
    return v.isFinite && v < 200 ? v : null;
  }

  /// Počet fotek napříč zastávkami.
  int get photoCount =>
      points.fold<int>(0, (s, p) => s + p.photos.length);

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

  /// Nejdelší SOUVISLÝ úsek stopy — jediná část, o které víme, že se opravdu
  /// projela. Sdílení posílá tohle, ne celou stopu: odkaz do map vedený přes
  /// mezeru by příjemci nakreslil cestu, kterou jezdec nikdy neprojel.
  List<LatLng> get longestSegment {
    if (segments.isEmpty) return mapPoints;
    var best = segments.first.points;
    for (final s in segments) {
      if (s.points.length > best.length) best = s.points;
    }
    return best.length >= 2 ? best : mapPoints;
  }

  static UserRide? fromJson(Map<String, dynamic> j) {
    final id = j['id']?.toString();
    if (id == null || id.isEmpty) return null;

    // Stopa + ČASOVÉ ZNAČKY. Časy se dřív zahazovaly, takže appka neměla
    // z čeho poznat, že mezi dvěma body uběhly hodiny — a kreslila je
    // spojené rovnou čarou.
    final track = <LatLng>[];
    final times = <int?>[];
    final t = j['track'];
    if (t is List) {
      for (final p in t) {
        if (p is List && p.length >= 2) {
          final lat = _toD(p[0]);
          final lng = _toD(p[1]);
          if (lat == null || lng == null) continue;
          track.add(LatLng(lat, lng));
          times.add(p.length > 2 ? _toI(p[2]) : null);
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
      segments: _splitOnGaps(track, times),
      startedAt: DateTime.tryParse(j['started_at']?.toString() ?? '') ?? DateTime.now(),
      endedAt: DateTime.tryParse(j['ended_at']?.toString() ?? ''),
      distanceKm: _toD(j['distance_km']) ?? 0,
      durationMin: _toI(j['duration_min']),
      movingSec: _toI(j['moving_sec']) ?? 0,
      idleSec: _toI(j['idle_sec']) ?? 0,
      gapSec: _toI(j['gap_sec']) ?? 0,
      lastFixAt: DateTime.tryParse(j['last_fix_at']?.toString() ?? ''),
      avgSpeedKmh: _toD(j['avg_speed_kmh']),
      maxSpeedKmh: _toD(j['max_speed_kmh']),
      elevationGainM: _toI(j['elevation_gain_m']) ?? 0,
      isRecording: j['is_recording'] == true,
      visibility: j['visibility']?.toString() ?? 'private',
      status: j['status']?.toString() ?? 'approved',
      coverImage: j['cover_image']?.toString(),
      points: pts,
    );
  }
}
