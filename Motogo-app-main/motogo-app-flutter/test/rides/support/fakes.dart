// Falešný server (šev `RideServerSeam`) a falešný geolocator pro testy
// záznamníku jízd — žádná síť, žádné platformní kanály.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:motogo_app/features/routes/ride_flags.dart';
import 'package:motogo_app/features/routes/ride_live_stats.dart';
import 'package:motogo_app/features/routes/ride_location.dart';
import 'package:motogo_app/features/routes/ride_provider.dart';
import 'package:motogo_app/features/routes/ride_recorder.dart';
import 'package:motogo_app/features/routes/ride_server_api.dart';
import 'package:motogo_app/features/routes/ride_server_seam.dart';

class FakeRide {
  FakeRide(this.id, this.booking);
  final String id;
  final String? booking;
  bool open = true;
  bool gone = false;
  bool bookingEnded = false;
  /// Kdo jízdu uzavřel (`cron` = úklid po 72 h → nová data ji znovu otevřou).
  String? closedBy;
  /// Začátek jízdy (epoch s) — `start_user_trip_from` ho posune na první bod.
  double? startedAt;
  final List<List<double>> pts = [];
  double get km => rideLiveDelta(null, pts).km;
}

class FakeServer extends RideServerSeam {
  FakeServer({this.trips = true});

  bool trips;
  bool offline = false;
  final Set<String> inactive = {};
  /// Server zná `start_user_trip_from` (zpětný začátek jízdy).
  bool fromSupported = true;
  final List<double> fromCalls = [];
  /// Vrácené výpůjčky (epoch s): body po vrácení (+30 s) server zahodí;
  /// `start_user_trip_from` s prvním bodem před vrácením jízdu založí zpětně.
  final Map<String, double> returns = {};
  final List<FakeRide> rides = [];
  int tripCalls = 0, legacyCalls = 0, appendCalls = 0;
  double Function() now = () => 0;

  FakeRide? get openRide {
    for (final r in rides.reversed) {
      if (r.open) return r;
    }
    return null;
  }

  FakeRide byId(String id) => rides.firstWhere((r) => r.id == id);

  FakeRide _open(String? booking) {
    final o = openRide;
    if (o != null) o.open = false; // server starou uzavře
    final r = FakeRide('ride${rides.length + 1}', booking);
    rides.add(r);
    return r;
  }

  @override
  bool get signedIn => true;

  @override
  Future<RideTripStart> startTrip(String? bookingId) async {
    tripCalls++;
    if (offline) return const RideTripStart(RideTripStartKind.offline);
    if (!trips) return const RideTripStart(RideTripStartKind.missing);
    if (bookingId != null && inactive.contains(bookingId)) {
      return const RideTripStart(RideTripStartKind.bookingInactive);
    }
    final o = openRide;
    if (o != null && o.booking == bookingId) {
      return RideTripStart(RideTripStartKind.ok, id: o.id, resumed: true, bookingId: bookingId, distanceKm: o.km);
    }
    final r = _open(bookingId);
    return RideTripStart(RideTripStartKind.ok, id: r.id, bookingId: bookingId, serverNow: now());
  }

  @override
  Future<RideTripStart> startTripFrom(String? bookingId, double firstTs) async {
    tripCalls++;
    if (offline) return const RideTripStart(RideTripStartKind.offline);
    if (!trips || !fromSupported) return const RideTripStart(RideTripStartKind.missing);
    fromCalls.add(firstTs);
    if (bookingId != null && inactive.contains(bookingId)) {
      final ret = returns[bookingId];
      if (ret == null || firstTs >= ret) return const RideTripStart(RideTripStartKind.bookingInactive);
      final r = _open(bookingId)..startedAt = firstTs;
      return RideTripStart(RideTripStartKind.ok, id: r.id, bookingId: bookingId, serverNow: now());
    }
    final o = openRide;
    if (o != null && o.booking == bookingId) {
      return RideTripStart(RideTripStartKind.ok, id: o.id, resumed: true, bookingId: bookingId, distanceKm: o.km);
    }
    final r = _open(bookingId)..startedAt = firstTs;
    return RideTripStart(RideTripStartKind.ok, id: r.id, bookingId: bookingId, serverNow: now());
  }

  /// Úklid (cron 72 h): otevřenou jízdu uzavře; vlastní cestu nová data
  /// znovu otevřou (`_ride_reopen`).
  void cronClose(FakeRide r) {
    r.open = false;
    r.closedBy = 'cron';
  }

  List<List<double>> _beforeReturn(FakeRide r, List<List<double>> points) {
    final ret = r.booking == null ? null : returns[r.booking];
    if (ret == null) return points;
    return [for (final p in points) if (p.length < 3 || p[2] <= ret + 30) p];
  }

  @override
  Future<RideStart?> startLegacy(String? bookingId) async {
    legacyCalls++;
    if (offline) return null;
    final o = openRide;
    if (o != null && o.booking == bookingId) return (id: o.id, resumed: true, bookingId: bookingId);
    final r = _open(bookingId);
    return (id: r.id, resumed: false, bookingId: bookingId);
  }

  @override
  Future<RideAppendOutcome> append(String id, List<List<double>> points, {double? maxSpeedKmh}) async {
    appendCalls++;
    if (offline) return RideAppendOutcome.retry;
    final r = rides.where((x) => x.id == id).firstOrNull;
    if (r == null || r.gone) return const RideAppendOutcome(RideAppendResult.gone);
    if (!r.open && r.closedBy == 'cron' && r.booking == null && openRide == null && points.isNotEmpty) {
      r.open = true; // _ride_reopen: vlastní cesta uzavřená úklidem, nová data
      r.closedBy = null;
    }
    if (!r.open) return RideAppendOutcome(RideAppendResult.closed, bookingEnded: r.bookingEnded);
    final keep = _beforeReturn(r, points);
    if (keep.isEmpty && points.isNotEmpty) {
      r.open = false; // jen body po vrácení → server výpůjčku uzavře
      r.bookingEnded = true;
      return const RideAppendOutcome(RideAppendResult.closed, bookingEnded: true);
    }
    r.pts.addAll([for (final p in keep) List<double>.from(p)]);
    final d = rideLiveDelta(null, r.pts);
    return RideAppendOutcome(RideAppendResult.ok,
        distanceKm: d.km, movingSec: d.movingSec, stagesN: trips ? 1 : null, serverNow: trips ? now() : null);
  }

  @override
  Future<RideFinish?> finish(String id, {List<List<double>> points = const []}) async {
    if (offline) return null;
    final r = rides.where((x) => x.id == id).firstOrNull;
    if (r == null) return const RideFinish(discarded: true, distanceKm: 0);
    r.pts.addAll(_beforeReturn(r, points));
    r.open = false;
    return RideFinish(discarded: r.km < 1, distanceKm: r.km);
  }

  @override
  Future<bool?> probe() async => offline ? null : trips;

  @override
  Future<RideAutoPauseFlag?> fetchFlag() async => RideAutoPauseFlag.defaults;
}

class FakeGeo extends GeolocatorPlatform {
  FakeGeo() {
    ctrl = StreamController<Position>.broadcast(
      onListen: () {
        listens++;
        listening = true;
      },
      onCancel: () => listening = false,
    );
  }

  late final StreamController<Position> ctrl;
  int listens = 0;
  bool listening = false;

  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async => LocationPermission.whileInUse;
  @override
  Future<LocationPermission> requestPermission() async => LocationPermission.whileInUse;
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) => ctrl.stream;
  @override
  Stream<ServiceStatus> getServiceStatusStream() => const Stream<ServiceStatus>.empty();
  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async => LocationAccuracyStatus.precise;
}

/// Simulovaný čas + poloha (poledník na sever).
class Sim {
  Sim(this.geo);
  final FakeGeo geo;
  DateTime now = DateTime.utc(2026, 10, 5, 6, 0);
  double lat = 49.2;
  final List<({String action, String? detail, Map<String, dynamic>? data})> logs = [];
  final List<MethodCall> native = [];

  double get epoch => now.millisecondsSinceEpoch / 1000;

  void install(FakeServer server) {
    rideRecorderClock = () => now;
    server.now = () => epoch;
    rideLogTestSink = (a, d, m) => logs.add((action: a, detail: d, data: m));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('cz.motogo24/ride'), (c) async {
      native.add(c);
      return c.method == 'notify' ? true : null;
    });
  }

  Future<void> settle() async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> fix(double kmh, {double acc = 8}) async {
    geo.ctrl.add(Position(
      latitude: lat,
      longitude: 16.6,
      timestamp: now,
      accuracy: acc,
      altitude: 300,
      altitudeAccuracy: 5,
      heading: 0,
      headingAccuracy: 1,
      speed: kmh / 3.6,
      speedAccuracy: 0.5,
      hasAccuracy: true,
      hasAltitude: true,
      hasAltitudeAccuracy: true,
      hasSpeed: true,
      hasSpeedAccuracy: true,
    ));
    await settle();
  }

  Future<void> ride(double kmh, Duration d, {double dt = 5}) async {
    final n = d.inSeconds ~/ dt;
    for (var i = 0; i < n; i++) {
      now = now.add(Duration(milliseconds: (dt * 1000).round()));
      lat += kmh / 3.6 * dt / 111194.93;
      await fix(kmh);
    }
  }

  /// Ticho s tiky časovače záznamníku.
  Future<void> wait(Duration d, RideRecorderNotifier n, {Duration every = const Duration(seconds: 90)}) async {
    final end = now.add(d);
    while (now.add(every).isBefore(end) || now.add(every) == end) {
      now = now.add(every);
      n.debugTick();
      await settle();
    }
    now = end;
  }

  int count(String action, [String? detail]) =>
      logs.where((l) => l.action == action && (detail == null || l.detail == detail)).length;
}
