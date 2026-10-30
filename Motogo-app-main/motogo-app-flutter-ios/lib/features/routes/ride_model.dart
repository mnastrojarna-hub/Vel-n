import 'package:latlong2/latlong.dart';

import 'ride_stage.dart';

export 'ride_stage.dart';

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
String? _str(dynamic v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}

/// Rozdělí stopu na souvislé úseky a mezery / pauzy mezi nimi — STEJNÝM
/// pravidlem jako server (`_ride_stats_v2`, SPEC §3.2) a Velín:
///   pauza  = bod se značkou (`kmh < 0`), nebo ticho > 180 s, které NENÍ
///            projetím a trvá ≥ 5 min (noc, oběd — i když se telefon posunul)
///   mezera = ticho > 180 s, ve kterém se ujelo > 300 m rychlostí ≥ 15 km/h
///            (slabý signál, vypnutá appka: nevíme, kudy jel)
/// Ticho ≥ 30 dní nebo čas jdoucí zpět = vadný čas (nedělí se).
///
/// Stopa BEZ časových značek (starý klient, ručně poskládaná jízda) se nedělí
/// vůbec — nemáme podle čeho, a řezat ji podle vzdálenosti by rozbilo ruční
/// trasy, které jsou rovnou spojnicí bodů záměrně.
List<RideSegment> _splitOnGaps(List<LatLng> track, List<double?> times, List<bool> flags) {
  if (track.isEmpty) return const [];
  if (track.length == 1) return [RideSegment(List.unmodifiable(track))];

  // Haversine (roundResult: false — výchozí zaokrouhlí km na CELÉ km):
  // stejný vzorec jako server a Velín, hranice 300 m padne u všech stejně.
  const dist = Distance(roundResult: false, calculator: Haversine());
  final out = <RideSegment>[];
  var current = <LatLng>[track.first];
  RideGap? pendingGap;
  double? prevTs = times.isNotEmpty ? times.first : null;

  for (var i = 1; i < track.length; i++) {
    final ts = i < times.length ? times[i] : null;
    final dt = (ts != null && prevTs != null) ? ts - prevTs : null;
    final km = dist.as(LengthUnit.Kilometer, track[i - 1], track[i]);
    RideGapKind? kind;
    if (dt != null && dt >= 0 && dt < kRideBadDtSec) {
      final flag = i < flags.length && flags[i];
      final through = dt > 0 && km / dt * 3600 >= 15 && km > kRideStillKm;
      if (flag) {
        kind = RideGapKind.pause;
      } else if (dt > kRideGapSec) {
        kind = through ? RideGapKind.gap : (dt >= kRidePauseSec ? RideGapKind.pause : null);
      }
    }
    if (kind != null) {
      out.add(RideSegment(List.unmodifiable(current), gapBefore: pendingGap));
      pendingGap = RideGap(from: track[i - 1], to: track[i], sec: dt!.round(), km: km, kind: kind);
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

/// Druh přerušení stopy: mezera (bez signálu) / pauza (stání, noc, přesun
/// trajektem — do km ani do času na cestě se nepočítá).
enum RideGapKind { gap, pause }

/// Mezera ve stopě: appka běžela na pozadí bez signálu / s vypnutou polohou,
/// takže mezi dvěma body NEVÍME, kudy jezdec jel. Spojit je plnou čarou by
/// znamenalo tvrdit trasu, která se nestala.
class RideGap {
  final LatLng from;
  final LatLng to;
  final int sec; // jak dlouho jsme byli "slepí" / jak dlouho pauza trvala
  final double km; // vzdušná čára přes mezeru (NE ujetá vzdálenost)
  final RideGapKind kind;

  const RideGap({
    required this.from,
    required this.to,
    required this.sec,
    required this.km,
    this.kind = RideGapKind.gap,
  });

  bool get isPause => kind == RideGapKind.pause;
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
/// Posun do 300 m = stál na místě, ne mezera. Při filtru 20 m + intervalu
/// 5 s je první fix po rozjezdu 40–100 m od posledního, takže 50 m dělalo
/// mezeru i z tříminutového tankování.
const double kRideStillKm = 0.3;
/// Ticho od 5 min bez projetí = pauza (noc, oběd), ne zastávka.
const int kRidePauseSec = 300;
/// Ticho od 30 dní = vadný čas (nic se nepočítá ani nedělí).
const int kRideBadDtSec = 2592000;

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
  /// Čas NA CESTĚ v minutách = start → konec BEZ pauz (nový server; u jízdy
  /// bez pauz totéž co dřív „celkem").
  final int? durationMin;
  final int movingSec; // čas v sedle (jen jízda ≥ 7 km/h podle Doppleru)
  final int idleSec; // zastávky (semafory, krátké stání) = zbytek času na cestě
  final int gapSec; // čas BEZ GPS signálu (km přes něj se nepočítají)
  /// Pauzy (noc, oběd, ruční pauza…) — mimo čas na cestě i zastávky.
  final int pauseSec;
  /// Jízdu nahrála appka, která sama pauzuje (server `pause_aware`).
  final bool pauseAware;
  /// Cesta: null = výchozí seskupení (podle výpůjčky), == id = samostatná,
  /// jiné = člen cesty s tímhle klíčem (viz `ride_trip.dart`).
  final String? tripId;
  final String? tripName;
  /// Etapy (dny) ze serveru; starý server → prázdné.
  final List<RideStage> stages;
  /// Řádek přišel z nového serveru (zná pauzy a cesty) — JEN schopnost
  /// serveru (cesty, slučování), ne vzorec statistik.
  final bool serverV2;
  /// Statistiky spočítal nový vzorec (noci a pauzy mimo „na cestě"; server
  /// `stats_v2`). Starší jízda drží staré součty → staré popisky (stejně
  /// jako Velín); bez klíče = false.
  final bool statsV2;
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
    this.pauseSec = 0,
    this.pauseAware = false,
    this.tripId,
    this.tripName,
    this.stages = const [],
    this.serverV2 = false,
    this.statsV2 = false,
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

  /// Má jízda díry ve stopě (bez signálu)? Pauzy sem nepatří.
  bool get hasGaps =>
      gapSec > 0 || segments.any((s) => s.gapBefore != null && !s.gapBefore!.isPause);

  /// Pauzy v minutách.
  int get pauseMin => (pauseSec / 60).round();

  /// Počet pauz (úseky stopy oddělené pauzou).
  int get pauseCount => segments.where((s) => s.gapBefore?.isPause == true).length;

  /// Čas na cestě bez pauz (min).
  int get activeMin => totalMin;

  /// Dny na cestě: z etap serveru, jinak kalendářní dny jízdy (jen když se
  /// opravdu jelo ≥ 5 min).
  int get days {
    if (stages.isNotEmpty) return rideDaysOfStages(stages);
    if (movingSec < 300) return 1;
    return rideCalendarDays(startedAt, endedAt ?? lastFixAt ?? startedAt);
  }

  /// Člen explicitní cesty (sloučené jezdcem)?
  bool get inExplicitTrip => tripId != null && tripId != id;

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
    final times = <double?>[];
    final flags = <bool>[];
    final t = j['track'];
    if (t is List) {
      for (final p in t) {
        if (p is List && p.length >= 2) {
          final lat = _toD(p[0]);
          final lng = _toD(p[1]);
          if (lat == null || lng == null) continue;
          track.add(LatLng(lat, lng));
          // Čas může přijít i jako desetinné číslo (1758000000.4) — `_toI`
          // by ho zahodil a mezery by se v appce přestaly poznávat.
          times.add(p.length > 2 ? _toD(p[2]) : null);
          // kmh < 0 = značka pauzy (první bod po pauze).
          flags.add(p.length > 3 && (_toD(p[3]) ?? 0) < 0);
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
      segments: _splitOnGaps(track, times, flags),
      startedAt: DateTime.tryParse(j['started_at']?.toString() ?? '') ?? DateTime.now(),
      endedAt: DateTime.tryParse(j['ended_at']?.toString() ?? ''),
      distanceKm: _toD(j['distance_km']) ?? 0,
      durationMin: _toI(j['duration_min']),
      movingSec: _toI(j['moving_sec']) ?? 0,
      idleSec: _toI(j['idle_sec']) ?? 0,
      gapSec: _toI(j['gap_sec']) ?? 0,
      pauseSec: _toI(j['pause_sec']) ?? 0,
      pauseAware: j['pause_aware'] == true,
      tripId: _str(j['trip_id']),
      tripName: _str(j['trip_name']),
      stages: RideStage.listFromJson(j['stages']),
      serverV2: j.containsKey('pause_aware'),
      statsV2: j['stats_v2'] == true,
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
