// Data pro widget testy starého vzhledu jízd: stavy záznamníku (každá fáze)
// a jízdy (vícedenní s etapami, pauzami a výpadkem, sloučená cesta,
// výpůjčka rozdělená nocí ze starého serveru, krátká samostatná jízda).
import 'package:motogo_app/features/routes/ride_model.dart';
import 'package:motogo_app/features/routes/ride_recorder.dart';

DateTime _ago(Duration d) => DateTime.now().subtract(d);

RideRecorderState _own({
  RidePhase phase = RidePhase.riding,
  RidePauseReason? reason,
  Duration since = const Duration(minutes: 40),
  bool gpsLost = false,
}) =>
    RideRecorderState(
      recording: true,
      manual: true,
      rideId: 'trip3',
      phase: phase,
      pauseReason: reason,
      pausedSince: reason == null ? null : _ago(since),
      liveKm: 1234.6,
      liveMovingSec: 26 * 3600 + 1260,
      liveStages: 7,
      gpsLost: gpsLost,
    );

RideRecorderState _rent({RidePhase phase = RidePhase.riding, RidePauseReason? reason}) => RideRecorderState(
      recording: true,
      rideId: 'rent1',
      bookingId: 'b1',
      phase: phase,
      pauseReason: reason,
      pausedSince: reason == null ? null : _ago(const Duration(minutes: 12)),
      liveKm: reason == RidePauseReason.start ? 0 : 86.4,
      liveMovingSec: reason == RidePauseReason.start ? 0 : 4200,
    );

/// Každá fáze záznamu, kterou UI rozlišuje.
Map<String, RideRecorderState> recStates() => {
      'idle': const RideRecorderState(),
      'own_riding': _own(),
      'own_armed': _own(phase: RidePhase.autoPaused, reason: RidePauseReason.start),
      'own_auto_stop': _own(phase: RidePhase.autoPaused, reason: RidePauseReason.stop),
      'own_auto_walk': _own(phase: RidePhase.autoPaused, reason: RidePauseReason.walk),
      'own_manual': _own(phase: RidePhase.manualPaused, reason: RidePauseReason.manual),
      'own_home': _own(phase: RidePhase.manualPaused, reason: RidePauseReason.home, since: const Duration(hours: 4)),
      'own_long': _own(phase: RidePhase.manualPaused, reason: RidePauseReason.long, since: const Duration(hours: 22)),
      'own_gpslost': _own(gpsLost: true),
      'rent_riding': _rent(),
      'rent_armed': _rent(phase: RidePhase.autoPaused, reason: RidePauseReason.start),
      'rent_auto': _rent(phase: RidePhase.autoPaused, reason: RidePauseReason.silence),
      'rent_manual': _rent(phase: RidePhase.manualPaused, reason: RidePauseReason.manual),
    };

/// Bod stopy `[lat, lng, ts, kmh, alt]`.
List<double> _p(double lat, double lng, double ts, double kmh) => [lat, lng, ts, kmh, 300];

/// Vícedenní jízda: 3 dny (2 noční pauzy se značkou), pauza na oběd,
/// výpadek signálu za jízdy a přesun trajektem během pauzy.
UserRide multiDayRide({String id = 'multi', bool recording = false}) {
  final t0 = DateTime(2026, 9, 28, 8).millisecondsSinceEpoch / 1000;
  final pts = <List<double>>[];
  var lat = 49.0, lng = 16.0, ts = t0;
  void ride(int n) {
    for (var i = 0; i < n; i++) {
      lat += 0.004;
      ts += 20;
      pts.add(_p(lat, lng, ts, 72));
    }
  }

  ride(30);
  ts += 3600; // oběd (pauza)
  pts.add(_p(lat, lng, ts, -1));
  ride(30);
  ts += 900; // výpadek signálu za jízdy (13 km za 15 min)
  lat += 0.12;
  pts.add(_p(lat, lng, ts, 52));
  ride(20);
  ts += 14 * 3600; // noc
  pts.add(_p(lat, lng, ts, -1));
  ride(30);
  ts += 5400; // trajekt (pauza, posun 20 km)
  lng += 0.27;
  pts.add(_p(lat, lng, ts, -1));
  ride(30);
  ts += 13 * 3600; // noc
  pts.add(_p(lat, lng, ts, -1));
  ride(25);
  // Konec třetí den odpoledne (časy stopy jsou zhuštěné, na součty nemají vliv).
  final end = DateTime(2026, 9, 30, 15);
  double st(int d, int h) => DateTime(2026, 9, 28 + d, h).millisecondsSinceEpoch / 1000;
  return UserRide.fromJson({
    'id': id,
    'name': 'Alpy přes Dolomity a Grossglockner',
    'moto_name': 'BMW R 1250 GS Adventure',
    'track': pts,
    'started_at': DateTime(2026, 9, 28, 8).toUtc().toIso8601String(),
    'ended_at': recording ? null : end.toUtc().toIso8601String(),
    'last_fix_at': end.toUtc().toIso8601String(),
    'is_recording': recording,
    'distance_km': 812.4,
    'duration_min': 1290,
    'moving_sec': 61200,
    'idle_sec': 4800,
    'gap_sec': 900,
    'pause_sec': 115200,
    'pause_aware': true,
    'avg_speed_kmh': 47.8,
    'max_speed_kmh': 143,
    'elevation_gain_m': 9840,
    'stages': [
      {'f': st(0, 8), 't': st(0, 19), 'km': 301.2, 'mv': 21600, 'gap': 900, 'ps': 3600, 'gain': 3120, 'max': 131},
      {'f': st(1, 9), 't': st(1, 18), 'km': 288.0, 'mv': 21000, 'gap': 0, 'ps': 5400, 'gain': 4210, 'max': 143},
      {'f': st(2, 8), 't': st(2, 15), 'km': 223.2, 'mv': 18600, 'gap': 0, 'ps': 0, 'gain': 2510, 'max': 118},
    ],
    'points': [
      {'id': 's1', 'kind': 'stop', 'name': 'Passo Giau', 'lat': 49.1, 'lng': 16.0, 'photos': ['https://example.invalid/a.jpg']},
    ],
  })!;
}

UserRide _simple(String id, DateTime start, {String? booking, String? tripId, String? tripName, bool v2 = true, String name = ''}) =>
    UserRide.fromJson({
      'id': id,
      'name': name,
      'booking_id': booking,
      'moto_name': booking != null ? 'Husqvarna 701 SM' : null,
      'trip_id': tripId,
      'trip_name': tripName,
      'track': [
        for (var i = 0; i < 12; i++)
          _p(49.2 + i * 0.01, 16.6, start.millisecondsSinceEpoch / 1000 + i * 30, 60),
      ],
      'started_at': start.toUtc().toIso8601String(),
      'ended_at': start.add(const Duration(hours: 3)).toUtc().toIso8601String(),
      'distance_km': 142.6,
      'duration_min': 180,
      'moving_sec': 8400,
      'idle_sec': 1800,
      'avg_speed_kmh': 61,
      'max_speed_kmh': 118,
      'elevation_gain_m': 820,
      if (v2) 'pause_aware': true,
      if (v2) 'pause_sec': 0,
    })!;

/// Sloučená cesta (2 jízdy) + výpůjčka rozdělená nocí (2 jízdy, starý
/// server) + vícedenní jízda + krátká samostatná jízda.
List<UserRide> ridesFixture({bool v2 = true}) => [
      _simple('t2', DateTime(2026, 10, 12, 9), tripId: 't1', tripName: 'Šumava s kamarády', v2: v2),
      _simple('t1', DateTime(2026, 10, 11, 9), tripId: 't1', tripName: 'Šumava s kamarády', v2: v2),
      _simple('b2', DateTime(2026, 10, 6, 8), booking: 'b1', v2: false),
      _simple('b1r', DateTime(2026, 10, 5, 14), booking: 'b1', v2: false),
      if (v2) multiDayRide(),
      _simple('solo', DateTime(2026, 9, 20, 16), name: 'Večerní projížďka', v2: v2),
    ];
