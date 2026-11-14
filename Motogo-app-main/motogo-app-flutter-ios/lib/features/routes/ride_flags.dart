import 'dart:async';

import '../../core/supabase_client.dart';
import 'ride_motion.dart';

/// Flag `ride_autopause` (Velín → feature_flags) = KILL-SWITCH automatické
/// pauzy záznamu jízdy + prahy bez vydání verze (`conditions`:
/// `{"stop_min":5,"walk_min":3,"resume_kmh":20,"home_h":3,"long_h":48,"idle_h":20}`).
/// Chybějící řádek (starý server) = ZAPNUTO s výchozími prahy. Vypnutí =
/// nahrává se bez auto-pauzy (jako dřív); ruční pauza a cesty zůstávají.
class RideAutoPauseFlag {
  const RideAutoPauseFlag({
    this.enabled = true,
    this.stopMin,
    this.walkMin,
    this.resumeKmh,
    this.homeH,
    this.longH,
    this.idleH,
  });

  static const defaults = RideAutoPauseFlag();

  final bool enabled;
  final num? stopMin;
  final num? walkMin;
  final num? resumeKmh;
  final num? homeH;
  final num? longH;
  /// Vlastní cesta stojí ≥ tolik h → při otevření appky připomenout (GPS
  /// běží dál; 0 = ne).
  final num? idleH;

  RideMotionConfig toConfig() => const RideMotionConfig().withFlag(
      stopMin: stopMin, walkMin: walkMin, resumeKmh: resumeKmh, homeH: homeH, longH: longH, idleH: idleH);

  /// Zápis do `mg_ride_caps.ap`.
  Map<String, dynamic> toJson() => {
        'on': enabled,
        if (stopMin != null) 'stop': stopMin,
        if (walkMin != null) 'walk': walkMin,
        if (resumeKmh != null) 'resume': resumeKmh,
        if (homeH != null) 'home': homeH,
        if (longH != null) 'long': longH,
        if (idleH != null) 'idle': idleH,
      };

  static num? _n(Object? v) => v is num ? v : num.tryParse('${v ?? ''}');

  static RideAutoPauseFlag fromJson(Map<String, dynamic>? j) {
    if (j == null) return defaults;
    return RideAutoPauseFlag(
      enabled: j['on'] != false,
      stopMin: _n(j['stop']),
      walkMin: _n(j['walk']),
      resumeKmh: _n(j['resume']),
      homeH: _n(j['home']),
      longH: _n(j['long']),
      idleH: _n(j['idle']),
    );
  }

  /// Řádek `feature_flags` (`enabled`, `conditions`).
  static RideAutoPauseFlag fromRow(Map<String, dynamic>? row) {
    if (row == null) return defaults;
    final c = row['conditions'];
    final m = c is Map ? c : const {};
    return RideAutoPauseFlag(
      enabled: row['enabled'] != false,
      stopMin: _n(m['stop_min']),
      walkMin: _n(m['walk_min']),
      resumeKmh: _n(m['resume_kmh']),
      homeH: _n(m['home_h']),
      longH: _n(m['long_h']),
      idleH: _n(m['idle_h']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RideAutoPauseFlag &&
      other.enabled == enabled &&
      other.stopMin == stopMin &&
      other.walkMin == walkMin &&
      other.resumeKmh == resumeKmh &&
      other.homeH == homeH &&
      other.longH == longH &&
      other.idleH == idleH;

  @override
  int get hashCode => Object.hash(enabled, stopMin, walkMin, resumeKmh, homeH, longH, idleH);
}

/// Načte flag (timeout 8 s). null = nepodařilo se (offline) → platí poslední
/// uložená hodnota z `mg_ride_caps`, jinak výchozí.
Future<RideAutoPauseFlag?> fetchRideAutoPauseFlag() async {
  try {
    final row = await MotoGoSupabase.client
        .from('feature_flags')
        .select('enabled, conditions')
        .eq('key', 'ride_autopause')
        .maybeSingle()
        .timeout(const Duration(seconds: 8));
    return RideAutoPauseFlag.fromRow(row);
  } catch (_) {
    return null;
  }
}
