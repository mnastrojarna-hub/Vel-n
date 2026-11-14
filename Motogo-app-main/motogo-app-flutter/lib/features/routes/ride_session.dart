import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Stav rozjetého záznamu, který musí přežít restart i zabití appky
/// (fáze pauzy, kotva, posun hodin, živé součty) + co umí server.
/// Oba klíče jsou v `CacheCleanupService._preserveKeys` (oba stromy).

const String kRideSessionKey = 'mg_ride_session';
const String kRideCapsKey = 'mg_ride_caps';

/// Fáze záznamu (platí jen když `recording == true`).
///   riding       – nahrává se (i krátké zpomalení / držené pomalé body)
///   autoPaused   – stojí / jde pěšky / čeká na rozjezd; GPS běží, nic se neposílá
///   manualPaused – pozastaveno ručně (nebo pojistkou doma / dlouhá pauza): GPS vypnuté
enum RidePhase { riding, autoPaused, manualPaused }

/// Proč záznam stojí. `start` = připraveno, čeká na první rozjezd.
enum RidePauseReason { start, stop, walk, silence, manual, home, long }

T? _enumByName<T extends Enum>(List<T> values, Object? name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

List<double>? _pt(Object? v) {
  if (v is! List || v.length < 3) return null;
  final out = <double>[];
  for (final e in v) {
    if (e is! num) return null;
    out.add(e.toDouble());
  }
  return out;
}

double? _d(Object? v) => v is num ? v.toDouble() : null;

/// `mg_ride_session` v1 (SPEC §5.3).
class RideSessionMeta {
  const RideSessionMeta({
    required this.ride,
    this.booking,
    this.manual = false,
    this.proto = 'legacy',
    this.phase = RidePhase.riding,
    this.reason,
    this.since,
    this.anchor,
    this.last,
    this.start,
    this.off = 0,
    this.liveKm = 0,
    this.liveMov = 0,
    this.liveStages = 1,
    this.liveAt,
    this.noticeKey,
    this.noticeArgs,
  });

  final String ride;
  final String? booking;
  final bool manual;
  /// `trip` = jízda založená `start_user_trip` (server zná pauzy),
  /// `legacy` = `start_user_ride` (starý server / starší build).
  final String proto;
  final RidePhase phase;
  final RidePauseReason? reason;
  final double? since; // epoch s — začátek pauzy (kotva)
  final List<double>? anchor; // kde motorka zastavila
  final List<double>? last; // poslední odeslaný / vyslaný bod
  final List<double>? start; // první bod cesty (pojistka „doma")
  final double off; // posun hodin telefonu vůči serveru (s)
  final double liveKm;
  final int liveMov;
  final int liveStages;
  final double? liveAt;
  final String? noticeKey;
  final Map<String, String>? noticeArgs;

  Map<String, dynamic> toJson() => {
        'v': 1,
        'ride': ride,
        'booking': booking,
        'manual': manual,
        'proto': proto,
        'phase': phase.name,
        if (reason != null) 'reason': reason!.name,
        if (since != null) 'since': since,
        if (anchor != null) 'anchor': anchor,
        if (last != null) 'last': last,
        if (start != null) 'start': start,
        'off': off,
        'live': {'km': liveKm, 'mov': liveMov, 'st': liveStages, if (liveAt != null) 'at': liveAt},
        if (noticeKey != null) 'notice': {'k': noticeKey, 'a': noticeArgs ?? const {}},
      };

  /// Neznámý / starší / poškozený formát → null (začne se načisto, bez pádu).
  static RideSessionMeta? fromJson(Object? j) {
    if (j is! Map || j['v'] != 1) return null;
    final ride = j['ride'];
    if (ride is! String || ride.isEmpty) return null;
    final live = j['live'] is Map ? j['live'] as Map : const {};
    final notice = j['notice'] is Map ? j['notice'] as Map : null;
    final args = notice?['a'];
    return RideSessionMeta(
      ride: ride,
      booking: j['booking'] is String ? j['booking'] as String : null,
      manual: j['manual'] == true,
      proto: j['proto'] == 'trip' ? 'trip' : 'legacy',
      phase: _enumByName(RidePhase.values, j['phase']) ?? RidePhase.riding,
      reason: _enumByName(RidePauseReason.values, j['reason']),
      since: _d(j['since']),
      anchor: _pt(j['anchor']),
      last: _pt(j['last']),
      start: _pt(j['start']),
      off: _d(j['off']) ?? 0,
      liveKm: _d(live['km']) ?? 0,
      liveMov: (_d(live['mov']) ?? 0).round(),
      liveStages: (_d(live['st']) ?? 1).round(),
      liveAt: _d(live['at']),
      noticeKey: notice?['k'] is String ? notice!['k'] as String : null,
      noticeArgs: args is Map ? {for (final e in args.entries) '${e.key}': '${e.value}'} : null,
    );
  }

  static Future<RideSessionMeta?> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(kRideSessionKey);
      if (raw == null || raw.isEmpty) return null;
      return fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(kRideSessionKey, jsonEncode(toJson()));
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(kRideSessionKey);
    } catch (_) {}
  }
}

/// `mg_ride_caps` — co umí server (+ poslední známý flag auto-pauzy).
class RideServerCaps {
  RideServerCaps({this.trips, this.at, this.ap, this.apAt});

  /// true = server zná pauzy a cesty (`start_user_trip`, sloupce), false =
  /// starý server (fallback), null = ještě nevíme.
  bool? trips;
  double? at; // kdy se to naposledy zjistilo (epoch s)
  Map<String, dynamic>? ap; // {on, stop, walk, resume, home, long}
  double? apAt;

  /// Zjištění starší než 30 min se smí zopakovat.
  bool stale(double now) => at == null || now - at! > 1800;

  Map<String, dynamic> toJson() => {
        if (trips != null) 'trips': trips,
        if (at != null) 'at': at,
        if (ap != null) 'ap': ap,
        if (apAt != null) 'apAt': apAt,
      };

  static RideServerCaps fromJson(Object? j) {
    if (j is! Map) return RideServerCaps();
    final ap = j['ap'];
    return RideServerCaps(
      trips: j['trips'] is bool ? j['trips'] as bool : null,
      at: _d(j['at']),
      ap: ap is Map ? {for (final e in ap.entries) '${e.key}': e.value} : null,
      apAt: _d(j['apAt']),
    );
  }

  static Future<RideServerCaps> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(kRideCapsKey);
      if (raw == null || raw.isEmpty) return RideServerCaps();
      return fromJson(jsonDecode(raw));
    } catch (_) {
      return RideServerCaps();
    }
  }

  Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(kRideCapsKey, jsonEncode(toJson()));
    } catch (_) {}
  }
}
