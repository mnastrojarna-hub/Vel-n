// Syntetické GPS stopy pro testy detektoru pauz (poledník lng 16.6 na sever).
import 'package:motogo_app/features/routes/ride_motion.dart';
import 'package:motogo_app/features/routes/ride_pause_engine.dart';
import 'package:motogo_app/features/routes/ride_session.dart';

const double kMPerDegLat = 111194.93; // R = 6371 km

class Trace {
  Trace(this.e, {this.t = 1792000000, this.lat = 49.2, this.lng = 16.6});

  final RidePauseEngine e;
  double t;
  double lat;
  double lng;

  final List<List<double>> emitted = [];
  final List<RideEngineLog> logs = [];
  final List<({double t, RidePhase phase, RidePauseReason? reason})> phases = [];
  bool detached = false;

  void _take(RideEngineStep s, double at) {
    emitted.addAll(s.emit);
    logs.addAll(s.logs);
    if (s.detach) detached = true;
    if (s.phaseChanged) phases.add((t: at, phase: e.phase, reason: e.reason));
  }

  RideFix fixHere({double? kmh, double? acc = 8, double? alt}) =>
      RideFix(ts: t, lat: lat, lng: lng, acc: acc, kmh: kmh, alt: alt);

  /// Pošle fix v aktuální poloze a čase.
  void fix({double? kmh, double? acc = 8}) => _take(e.onFix(fixHere(kmh: kmh, acc: acc)), t);

  /// Posun o [m] metrů (kladně na sever).
  void move(double m) => lat += m / kMPerDegLat;

  /// Jízda / chůze rychlostí [kmh] po dobu [sec], fix každých [dt] s.
  /// [dop] = Doppler v fixu (null = bez rychlosti), [dir] = 1 sever / −1 jih.
  void go(double kmh, double sec, {double dt = 5, double? dop, bool noDop = false, double dir = 1, double acc = 8}) {
    final steps = (sec / dt).round();
    for (var i = 0; i < steps; i++) {
      t += dt;
      move(dir * kmh / 3.6 * dt);
      fix(kmh: noDop ? null : (dop ?? kmh), acc: acc);
    }
  }

  /// Ticho [sec] s tiky časovače každých [every] s (0 = bez tiků).
  void wait(double sec, {double every = 90, double liveKm = 0}) {
    if (every <= 0) {
      t += sec;
      return;
    }
    final end = t + sec;
    while (t + every <= end) {
      t += every;
      tick(liveKm: liveKm);
    }
    t = end;
  }

  void tick({double liveKm = 0}) => _take(e.onTick(t, liveKm: liveKm), t);

  void pauseManual() => _take(e.pauseManual(t), t);
  void resumeManual() => _take(e.resumeManual(), t);
  void stop() => _take(e.stopFlush(), t);

  List<RideEngineLog> logsOf(String a) => logs.where((l) => l.action == a).toList();
  List<List<double>> get flagged => emitted.where((p) => p.length > 3 && p[3] < 0).toList();
}
