// Fixtures for the v2 ride pause / trips tests (SPEC §9.2): recorder
// states of every phase, multi-day rides with stages and pauses, an
// explicit trip, an implicit rental group, a legacy (old-server) ride, a
// recorder fake that logs pause / resume / stop and trip-server seams.
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:motogo_app/features/loyalty/loyalty_provider.dart';
import 'package:motogo_app/features/routes/ride_model.dart';
import 'package:motogo_app/features/routes/ride_provider.dart';
import 'package:motogo_app/features/routes/ride_recorder.dart';
import 'package:motogo_app/features/routes/ride_server_api.dart';
import 'package:motogo_app/features/routes/ride_trip.dart';
import 'package:motogo_app/features/routes/ride_trip_api.dart';
import 'package:motogo_app/features/routes/v2/rides/trip_actions_v2.dart';

import 'fakes_rides.dart';

final kPausedAt = DateTime.now().subtract(const Duration(minutes: 42));
final kPausedYesterday = DateTime.now().subtract(const Duration(hours: 22));

const kRecRiding = RideRecorderState(
    recording: true, manual: true, rideId: 'r4', points: 900, liveKm: 128.4, liveMovingSec: 7380, liveStages: 2);
const kRecRidingRental =
    RideRecorderState(recording: true, rideId: 'r5', bookingId: 'b1', points: 300, liveKm: 46.2, liveMovingSec: 3120);
final kRecAutoPaused = RideRecorderState(
  recording: true,
  manual: true,
  rideId: 'r4',
  phase: RidePhase.autoPaused,
  pauseReason: RidePauseReason.stop,
  pausedSince: kPausedAt,
  liveKm: 312.6,
  liveMovingSec: 15420,
  liveStages: 3,
);
final kRecManualPaused = RideRecorderState(
  recording: true,
  manual: true,
  rideId: 'r4',
  phase: RidePhase.manualPaused,
  pauseReason: RidePauseReason.manual,
  pausedSince: kPausedYesterday,
  liveKm: 1240.8,
  liveMovingSec: 61200,
  liveStages: 4,
);
final kRecArmed = RideRecorderState(
  recording: true,
  rideId: 'r5',
  bookingId: 'b1',
  phase: RidePhase.autoPaused,
  pauseReason: RidePauseReason.start,
  pausedSince: kPausedAt,
);
final kRecHome = RideRecorderState(
  recording: true,
  manual: true,
  rideId: 'r4',
  phase: RidePhase.manualPaused,
  pauseReason: RidePauseReason.home,
  pausedSince: kPausedYesterday,
  liveKm: 412.3,
  liveMovingSec: 21900,
  liveStages: 2,
);
final kRecLong = kRecHome.copyWith(pauseReason: RidePauseReason.long);
final kRecRentalWalk = RideRecorderState(
  recording: true,
  rideId: 'r5',
  bookingId: 'b1',
  phase: RidePhase.autoPaused,
  pauseReason: RidePauseReason.walk,
  pausedSince: kPausedAt,
  liveKm: 88.1,
  liveMovingSec: 5400,
);
final kRecRentalManualPaused = kRecRentalWalk.copyWith(phase: RidePhase.manualPaused, pauseReason: RidePauseReason.manual);

/// Every recorder state of the matrix (name → state).
Map<String, RideRecorderState> recStates() => {
      'riding': kRecRiding,
      'riding-rental': kRecRidingRental,
      'armed': kRecArmed,
      'auto-paused': kRecAutoPaused,
      'manual-paused': kRecManualPaused,
      'rental-walk': kRecRentalWalk,
      'rental-paused': kRecRentalManualPaused,
      'home': kRecHome,
      'long': kRecLong,
      'gps-lost': kRecGpsLost,
    };

/// Recorder fake that logs the pause / resume / stop calls of the v2 UI.
class FakePauseRecorder extends FakeRidesRecorder {
  RideStartResult resumeResult;
  FakePauseRecorder(super.ref, super.initial, {this.resumeResult = RideStartResult.ok});

  @override
  Future<void> pause() async {
    calls.add('pause');
    state = state.copyWith(phase: RidePhase.manualPaused, pauseReason: RidePauseReason.manual, pausedSince: DateTime.now());
  }

  @override
  Future<RideStartResult> resume() async {
    calls.add('resume');
    if (resumeResult == RideStartResult.ok) {
      state = state.copyWith(phase: RidePhase.autoPaused, pauseReason: RidePauseReason.start);
    }
    return resumeResult;
  }

  @override
  Future<bool?> stop() async {
    calls.add('stop');
    state = state.copyWith(recording: false, clearRide: true);
    return true;
  }
}

List<LatLng> _line(LatLng a, int n, double dLat, double dLng) => [
      for (var i = 0; i < n; i++) LatLng(a.latitude + i * dLat + 0.001 * math.sin(i / 2), a.longitude + i * dLng),
    ];

final _d1 = _line(const LatLng(48.99, 16.67), 14, 0.004, 0.006);
final _d2 = _line(LatLng(_d1.last.latitude + 0.0004, _d1.last.longitude), 14, 0.005, 0.002);
final _ferry = _line(const LatLng(49.30, 16.80), 10, 0.003, 0.004);

RideStage _stage(int day, double km, int mvMin, {int gain = 0, double? max, int psMin = 0}) {
  final f = DateTime(2026, 9, 27 + day, 8, 30);
  return RideStage(
    from: f,
    to: f.add(Duration(minutes: mvMin + psMin + 40)),
    km: km,
    movingSec: mvMin * 60,
    pauseSec: psMin * 60,
    gain: gain,
    max: max,
  );
}

/// A 3-day own ride (new server): nights as pauses, one moved pause
/// (ferry), one gap, stages per day.
final kRideMultiDay = UserRide(
  id: 'm1',
  name: 'Tři dny Šumavou a Bavorskem s přejezdem trajektem',
  track: [..._d1, ..._d2, ..._ferry],
  segments: [
    RideSegment(_d1),
    RideSegment(_d2, gapBefore: RideGap(from: _d1.last, to: _d2.first, sec: 46800, km: 0.05, kind: RideGapKind.pause)),
    RideSegment(_ferry, gapBefore: RideGap(from: _d2.last, to: _ferry.first, sec: 3600, km: 6.4, kind: RideGapKind.pause)),
  ],
  startedAt: DateTime(2026, 9, 28, 8, 30),
  endedAt: DateTime(2026, 9, 30, 17, 10),
  distanceKm: 912.4,
  durationMin: 1630,
  movingSec: 76200,
  idleSec: 19200,
  gapSec: 2400,
  pauseSec: 133200,
  pauseAware: true,
  serverV2: true,
  stages: [_stage(1, 321.4, 395, gain: 2140, max: 128, psMin: 45), _stage(2, 288.9, 352, gain: 1820, max: 121), _stage(3, 302.1, 523, gain: 980, max: 139)],
  avgSpeedKmh: 43.1,
  maxSpeedKmh: 139,
  elevationGainM: 4940,
  motoName: 'BMW R 1250 GS Adventure',
);

UserRide _tripRide(String id, int day, double km, {String? tripId, String? tripName, String? booking, String? moto, bool rec = false}) =>
    UserRide(
      id: id,
      bookingId: booking,
      motoName: moto,
      tripId: tripId,
      tripName: tripName,
      name: '',
      track: day.isEven ? _d1 : _d2,
      segments: [RideSegment(day.isEven ? _d1 : _d2)],
      startedAt: DateTime(2026, 8, day, 9),
      endedAt: rec ? null : DateTime(2026, 8, day, 17),
      lastFixAt: DateTime(2026, 8, day, 17),
      distanceKm: km,
      durationMin: 420,
      movingSec: 18000,
      idleSec: 3600,
      pauseAware: true,
      serverV2: true,
      avgSpeedKmh: km / 5,
      maxSpeedKmh: 118,
      elevationGainM: 1200,
      isRecording: rec,
    );

final kTrip1 = _tripRide('t1', 10, 312, tripId: 't1', tripName: 'Alpy 2026 — Grossglockner a Dolomity');
final kTrip2 = _tripRide('t2', 11, 288, tripId: 't1', tripName: 'Alpy 2026 — Grossglockner a Dolomity');
final kTrip3 = _tripRide('t3', 12, 341, tripId: 't1', tripName: 'Alpy 2026 — Grossglockner a Dolomity');
final kRent1 = _tripRide('b91', 20, 205, booking: 'b9', moto: 'Honda Africa Twin');
final kRent2 = _tripRide('b92', 21, 187, booking: 'b9', moto: 'Honda Africa Twin', rec: true);
final kSolo = _tripRide('s1', 3, 96);
final kLegacy = UserRide(
  id: 'l1',
  name: 'Stará jízda (starý server)',
  track: _d1,
  segments: [RideSegment(_d1)],
  startedAt: DateTime(2026, 7, 5, 10),
  endedAt: DateTime(2026, 7, 5, 13),
  distanceKm: 120,
  durationMin: 180,
  movingSec: 9000,
);

/// Rides of the trip screens: an explicit trip (3), a rental group (2),
/// a multi-day ride, a single ride and a legacy ride.
List<UserRide> kTripRides() => [kRent2, kRent1, kTrip3, kTrip2, kTrip1, kRideMultiDay, kSolo, kLegacy];

RideTrip tripOf(List<UserRide> rides, String leaderId) =>
    groupRides(rides).whereType<RideListItemTrip>().map((i) => i.trip).firstWhere((t) => t.rides.any((r) => r.id == leaderId));

/// Calls of the trip-server seams.
class TripSeamLog {
  final List<List<RideTripItem>> sets = [];
  final List<String> other = [];
  RideTripSetKind kind = RideTripSetKind.ok;
}

List<Override> tripOverrides({
  RideRecorderState recorder = kRecIdle,
  List<UserRide>? rides,
  TripSeamLog? log,
  RideStartResult resumeResult = RideStartResult.ok,
}) {
  final l = log ?? TripSeamLog();
  return [
    rideRecorderProvider.overrideWith((ref) => FakePauseRecorder(ref, recorder, resumeResult: resumeResult)),
    loyaltyStatusProvider.overrideWith((ref) async => kLoyaltyRides),
    myRidesProvider.overrideWith((ref) async => rides ?? kTripRides()),
    tripSetSeamV2.overrideWithValue((items) async {
      l.sets.add(items);
      return RideTripSetResult(l.kind, updated: l.kind == RideTripSetKind.ok ? items.length : 0);
    }),
    tripVisibilitySeamV2.overrideWithValue((ref, trip, public) async {
      l.other.add('visibility:$public:${trip.rides.length}');
      return RideTripOpResult.ok;
    }),
    tripDeleteSeamV2.overrideWithValue((ref, trip) async {
      l.other.add('delete:${trip.rides.length}');
      return RideTripOpResult.ok;
    }),
  ];
}
