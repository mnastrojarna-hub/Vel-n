// Fixtures + provider overrides for the Jízdy v2 tests (PLAN §5.2): rides
// (S MotoGo / soukromá / s výpadkem signálu), saved routes, discovered
// places, navigation history, recorder states. Nothing touches Supabase.
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:motogo_app/core/i18n/translations.dart';
import 'package:motogo_app/core/i18n/translations_ext_56_v2_routes_a.dart';
import 'package:motogo_app/core/i18n/translations_ext_56_v2_routes_b.dart';
import 'package:motogo_app/core/i18n/translations_ext_57_v2_rides_a.dart';
import 'package:motogo_app/core/i18n/translations_ext_57_v2_rides_b.dart';
import 'package:motogo_app/core/i18n/translations_ext_57_v2_rides_c.dart';
import 'package:motogo_app/core/i18n/translations_ext_57_v2_rides_d.dart';
import 'package:motogo_app/core/i18n/translations_ext_57_v2_rides_e.dart';
import 'package:motogo_app/core/i18n/translations_ext_57_v2_rides_f.dart';
import 'package:motogo_app/features/loyalty/loyalty_provider.dart';
import 'package:motogo_app/features/routes/active_ride_provider.dart';
import 'package:motogo_app/features/routes/my_experiences_provider.dart';
import 'package:motogo_app/features/routes/ride_model.dart';
import 'package:motogo_app/features/routes/ride_recorder.dart';

/// Registers the Trasy + Jízdy v2 strings (idempotent) — the integration
/// step registers them in translations.dart for the app.
void registerRidesStrings() {
  for (final part in [
    translationsExt56V2RoutesA,
    translationsExt56V2RoutesB,
    translationsExt57V2RidesA,
    translationsExt57V2RidesB,
    translationsExt57V2RidesC,
    translationsExt57V2RidesD,
    translationsExt57V2RidesE,
    translationsExt57V2RidesF,
  ]) {
    part.forEach((lang, map) => translations.putIfAbsent(lang, () => {}).addAll(map));
  }
}

/// A wiggly track around Velké Němčice (n points from [start]).
List<LatLng> _track(LatLng start, int n, {double heading = 0.6}) => [
      for (var i = 0; i < n; i++)
        LatLng(
          start.latitude + i * 0.0021 * math.cos(heading) + 0.0012 * math.sin(i / 2.3),
          start.longitude + i * 0.0029 * math.sin(heading) + 0.0015 * math.cos(i / 3.1),
        ),
    ];

final _a = _track(const LatLng(48.9918, 16.6705), 26);
final _b = _track(const LatLng(49.0505, 16.7380), 18, heading: 1.2);

final kRideMg = UserRide(
  id: 'r1',
  bookingId: 'b1',
  motoName: 'Husqvarna 701 SM',
  name: 'Pálava za soumraku',
  description: 'Vinice, Děvičky a večerní světlo nad nádržemi. Zastávka na kávu v Pavlově.',
  track: _a,
  segments: [RideSegment(_a)],
  startedAt: DateTime(2026, 10, 9, 15, 20),
  endedAt: DateTime(2026, 10, 9, 18, 42),
  distanceKm: 186.4,
  durationMin: 202,
  movingSec: 9840,
  idleSec: 2280,
  avgSpeedKmh: 68,
  maxSpeedKmh: 131,
  elevationGainM: 1240,
  visibility: 'public',
  points: [
    RidePoint(id: 'p0', kind: 'start', lat: _a.first.latitude, lng: _a.first.longitude),
    RidePoint(
      id: 'p1',
      name: 'Rozhledna Děvičky',
      note: 'Výhled na celé Pálavské vrchy, parkování přímo pod hradem.',
      lat: _a[12].latitude,
      lng: _a[12].longitude,
      photos: const ['https://example.invalid/a.jpg', 'https://example.invalid/b.jpg'],
    ),
    RidePoint(id: 'p2', name: '', lat: _a[18].latitude, lng: _a[18].longitude),
    RidePoint(id: 'p3', kind: 'end', lat: _a.last.latitude, lng: _a.last.longitude),
  ],
);

final kRidePrivate = UserRide(
  id: 'r2',
  name: '',
  track: _b,
  segments: [RideSegment(_b)],
  startedAt: DateTime(2026, 10, 2, 9, 5),
  endedAt: DateTime(2026, 10, 2, 9, 48),
  distanceKm: 7.4,
  durationMin: 43,
  source: 'auto',
);

final kRideGap = UserRide(
  id: 'r3',
  name: 'Vysočina — výpadek signálu uprostřed lesa a dlouhý název jízdy',
  track: [..._a.take(10), ..._b.skip(6)],
  segments: [
    RideSegment(_a.take(10).toList()),
    RideSegment(_b.skip(6).toList(), gapBefore: RideGap(from: _a[9], to: _b[6], sec: 1860, km: 6.2)),
  ],
  startedAt: DateTime(2026, 9, 21, 10, 0),
  endedAt: DateTime(2026, 9, 21, 13, 12),
  distanceKm: 94.2,
  durationMin: 192,
  movingSec: 7200,
  idleSec: 1800,
  gapSec: 1860,
  avgSpeedKmh: 47,
  maxSpeedKmh: 104,
  elevationGainM: 640,
);

final kRideLive = UserRide(
  id: 'r4',
  name: '',
  track: _b.take(4).toList(),
  startedAt: DateTime(2026, 10, 16, 14, 2),
  distanceKm: 1.2,
  isRecording: true,
);

final kRides = [kRideLive, kRideMg, kRidePrivate, kRideGap];

final kSavedRoutes = [
  SavedRoute(
    id: 's1',
    name: 'Okruh Pálavou s výhledem',
    description: 'Vlastní okruh přes Mikulov, Pavlov a Dolní Věstonice — klidné silnice mezi vinicemi.',
    waypoints: [for (var i = 0; i < _a.length; i += 5) _a[i]],
    distanceKm: 92,
    durationMin: 134,
    createdAt: DateTime(2026, 9, 30),
  ),
  SavedRoute(id: 's2', name: 'Do Mezné', waypoints: [_b.first, _b.last], createdAt: DateTime(2026, 8, 12)),
];

final kPlaces = [
  VisitedPlace(
    id: 'v1',
    routePoiId: 'p1',
    name: 'Klášter Rajhrad',
    lat: 49.0906,
    lng: 16.6100,
    imageUrl: 'https://example.invalid/rajhrad.jpg',
    routeName: 'Brněnskem za klášterem',
    firstVisitedAt: DateTime(2026, 9, 14),
    visitCount: 3,
  ),
  VisitedPlace(id: 'v2', userPoiId: 'u1', name: 'Vyhlídka nad nádrží Nové Mlýny se jménem na dva řádky', firstVisitedAt: DateTime(2026, 8, 1)),
];

final kHistoryActive = ActiveRide(
  id: '1',
  key: 'k1',
  name: 'Pálava za soumraku',
  routeId: 'rt1',
  reached: const [0, 1],
  totalStops: 5,
  startedAt: DateTime(2026, 10, 16, 9),
  updatedAt: DateTime(2026, 10, 16, 11),
);

final kHistory = [
  ActiveRide(
    id: '2',
    key: 'k2',
    name: '',
    reached: const [0, 1, 2],
    totalStops: 3,
    done: true,
    startedAt: DateTime(2026, 10, 1, 9),
    updatedAt: DateTime(2026, 10, 1, 12),
  ),
];

const kLoyaltyRides = LoyaltyStatus(
  level: 3,
  percent: 3,
  rankName: 'Motorkář',
  colorHex: '#4ADE80',
  qualifyingCount: 5,
  nextRankName: 'Stálý jezdec',
  nextPercent: 4,
  bookingsToNext: 1,
);

/// Recorder notifier with a fixed state (restore from prefs never wins).
class FakeRidesRecorder extends RideRecorderNotifier {
  final RideRecorderState initial;
  final List<String> calls = [];
  FakeRidesRecorder(super.ref, this.initial) {
    state = initial;
    Future<void>.delayed(const Duration(milliseconds: 50), () {
      if (mounted) state = initial;
    });
  }

  @override
  Future<void> setEnabled(bool value) async {
    calls.add('setEnabled:$value');
    state = state.copyWith(enabled: value);
  }
}

const kRecIdle = RideRecorderState();
const kRecManual = RideRecorderState(recording: true, manual: true, rideId: 'r4', points: 128);
const kRecAuto = RideRecorderState(recording: true, rideId: 'r5', bookingId: 'b1', points: 2048);
const kRecGpsLost = RideRecorderState(recording: true, manual: true, rideId: 'r4', points: 64, gpsLost: true);
const kRecOff = RideRecorderState(enabled: false);

List<Override> ridesOverrides({RideRecorderState recorder = kRecIdle, LoyaltyStatus? loyalty = kLoyaltyRides}) => [
      rideRecorderProvider.overrideWith((ref) => FakeRidesRecorder(ref, recorder)),
      loyaltyStatusProvider.overrideWith((ref) async => loyalty),
    ];
