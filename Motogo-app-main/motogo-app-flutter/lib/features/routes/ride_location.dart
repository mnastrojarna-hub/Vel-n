import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_stripe/flutter_stripe.dart' show Stripe;
import 'package:geolocator/geolocator.dart';

import '../../core/debug_logger.dart';
import '../../core/i18n/i18n_provider.dart';
import 'ride_motion.dart';

/// GPS část záznamu jízdy („Moje jízdy") bez stavu: nastavení streamu,
/// převod fixu na bod stopy, udržení appky naživu a diagnostika.

const int kRideDistanceFilterM = 20; // hustota stopy
/// Nejkratší rozestup fixů na Androidu. Při 20m filtru a rychlosti nad
/// 15 km/h stejně rozhoduje vzdálenost — tohle jen drží službu naživu.
const Duration kRideMinInterval = Duration(seconds: 5);
/// Horší přesnost fixu (m) při STÁNÍ do stopy nebereme — na silnici má
/// telefon 5–15 m, přes 50 m je to typicky drift uvnitř budovy.
const double kRideMaxAccuracyM = 50;
/// Přesnost v řádu kilometrů (iOS „přibližná poloha") je k ničemu vždy.
const double kRideGarbageAccuracyM = 500;
/// Fix starší než tohle je stará poloha z cache, ne bod jízdy.
const Duration kRideFixStale = Duration(hours: 6);

/// Nastavení GPS streamu podle platformy.
///
/// BEZ tohohle appka na pozadí (zhasnutý displej, telefon v kapse, jiná
/// appka nahoře) přestane dostávat fixy — a přesně tak vznikaly „trasy"
/// z jedenácti bodů pospojovaných rovnou čarou přes celý kraj.
///   Android — foreground service s trvalou notifikací. Vystačí si
///     s oprávněním „při používání"; ACCESS_BACKGROUND_LOCATION netřeba.
///     Službu ale smí spustit jen appka V POPŘEDÍ (Android 12+), proto se
///     stream připojuje hned na začátku záznamu a při návratu do appky.
///   iOS — allowBackgroundLocationUpdates + modrý indikátor v liště;
///     vyžaduje `UIBackgroundModes: location` v Info.plist.
LocationSettings rideLocationSettings(String lang) {
  if (defaultTargetPlatform == TargetPlatform.android) {
    final tr = AppTranslations.of(lang);
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: kRideDistanceFilterM,
      intervalDuration: kRideMinInterval,
      foregroundNotificationConfig: ForegroundNotificationConfig(
        // Statický text služby (mění se jen při novém připojení streamu);
        // aktuální stav (nahrávám / pozastaveno) přepisuje nativně
        // `RideKeepAlive.notify`.
        notificationTitle: rideTrOr(tr, 'rpNotifTitle', 'rideNotifTitle'),
        notificationText: rideTrOr(tr, 'rpNotifDefault', 'rideNotifText'),
        // Název kanálu vidí uživatel v systémovém nastavení. Držíme ho
        // jazykově neutrální, ať se při přepnutí jazyka nezaloží druhý.
        notificationChannelName: 'MotoGo24',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
  }
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return AppleSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: kRideDistanceFilterM,
      activityType: ActivityType.automotiveNavigation,
      allowBackgroundLocationUpdates: true,
      // iOS umí stopu „uspat", když usoudí, že se nikam nejede. To je
      // přesně to, co u vyjížďky s pauzou na kafe nechceme.
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
    );
  }
  return const LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: kRideDistanceFilterM,
  );
}

/// Překlad s náhradním klíčem, když nový klíč ještě v překladech chybí.
String rideTrOr(AppTranslations tr, String key, String fallbackKey) {
  final v = tr.tr(key);
  return v == key ? tr.tr(fallbackKey) : v;
}

/// Překlad, nebo null, když klíč v překladech chybí (pak se text nemění).
String? rideTrOpt(AppTranslations tr, String key, [Map<String, Object?>? args]) {
  final v = args == null ? tr.tr(key) : tr.trArgs(key, args);
  return v == key ? null : v;
}

/// Platná Dopplerova rychlost ze zařízení (km/h), jinak null.
/// Neznámá rychlost NENÍ nula: Android ji bez měření vůbec nepošle
/// (`hasSpeed` false), iOS pošle −1; nepřesná (> 2,5 m/s) se nebere.
double? rideDopplerKmh(Position pos) {
  final v = pos.speed;
  if (!v.isFinite || v < 0 || !(pos.hasSpeed || v > 0)) return null;
  final sa = pos.speedAccuracy;
  if (pos.hasSpeedAccuracy && sa.isFinite && sa > RideMotionConfig.dopMaxSpeedAccMs) return null;
  final kmh = v * 3.6;
  return kmh > 300 ? null : kmh;
}

/// Fix z geolocatoru → [RideFix] pro detektor (SPEC §2.2, §5.5), nebo null,
/// když je k ničemu (přesnost v km, stará poloha z cache).
///
/// ČAS je čas FIXU, ne čas příjmu (systém po probuzení doručí nastřádané
/// fixy najednou). [clockOffset] = server − telefon (s): když fix nese čas
/// telefonu (± 2 min od „teď"), posune se o něj; když nese skutečný čas GPS,
/// nechá se. Rozbité hodiny fixu (budoucnost, roky zpět) → opravené „teď".
RideFix? rideFixFromPosition(Position pos, {DateTime? now, double clockOffset = 0}) {
  final local = now ?? DateTime.now();
  final off = Duration(milliseconds: (clockOffset * 1000).round());
  final corrNow = local.add(off);
  final rawAcc = pos.accuracy;
  final acc = (pos.hasAccuracy || rawAcc > 0) && rawAcc.isFinite && rawAcc >= 0 ? rawAcc : null;
  if (acc != null && acc > kRideGarbageAccuracyM) return null;
  var t = pos.timestamp;
  if (clockOffset != 0 && t.difference(local).abs() < const Duration(seconds: 120)) {
    t = t.add(off);
  }
  final age = corrNow.difference(t);
  if (age < const Duration(minutes: -2) || age > const Duration(days: 30)) {
    t = corrNow; // hodiny přijímače mimo realitu → čas příjmu
  } else if (age > kRideFixStale) {
    return null; // stará poloha z cache, ne bod téhle jízdy
  }
  final alt = pos.altitude;
  final altOk = alt.isFinite && alt != 0 &&
      (!pos.hasAltitudeAccuracy || pos.altitudeAccuracy <= 20);
  return RideFix(
    ts: (t.millisecondsSinceEpoch / 100).round() / 10,
    lat: pos.latitude,
    lng: pos.longitude,
    acc: acc,
    kmh: rideDopplerKmh(pos),
    alt: altOk ? alt : null,
  );
}

/// Fix → bod stopy `[lat, lng, čas (epoch s), rychlost km/h, výška m]`, nebo
/// null (viz [rideFixFromPosition] + `ridePointFromRideFix`). [last] =
/// poslední bod stopy; [notBefore]: první bod (bez [last]) nesmí být starší —
/// iOS po spuštění streamu pošle nejdřív polohu z cache. Záznamník používá
/// přímo `RidePauseEngine`; tohle zůstává pro jednorázové převody a testy.
List<double>? ridePointFromFix(Position pos, List<double>? last,
    {DateTime? now, DateTime? notBefore}) {
  final f = rideFixFromPosition(pos, now: now);
  if (f == null) return null;
  if (last == null && notBefore != null &&
      f.ts < notBefore.millisecondsSinceEpoch / 1000) {
    return null; // poloha z cache z doby před záznamem
  }
  return ridePointFromRideFix(f, last);
}

/// Vzdálenost dvou bodů v metrech (haversine — stejně jako server).
double rideDistanceM(double lat1, double lng1, double lat2, double lng2) =>
    rideDistM(lat1, lng1, lat2, lng2);

/// Android: dokud se nahrává jízda, nechá nativní strana Flutter engine
/// naživu i po zavření okna appky (odsunutí z posledních aplikací, Zpět na
/// Androidu 11 a starším). Bez toho zavření okna zrušilo i GPS službu
/// a stopa skončila — `MainActivity` (kanál `cz.motogo24/ride`).
class RideKeepAlive {
  static const _ch = MethodChannel('cz.motogo24/ride');
  static bool? _sent;
  static bool _listening = false;

  static Future<void> set(bool on) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (!_listening) {
      _listening = true;
      _ch.setMethodCallHandler(_onNative);
    }
    if (_sent == on) return;
    _sent = on;
    try {
      await _ch.invokeMethod<void>('keepAlive', {'on': on});
    } catch (e) {
      _sent = null; // zkusí se příště znovu
      rideLog('keep_alive_failed', detail: '$e');
    }
  }

  /// Text trvalé notifikace GPS služby podle stavu záznamu (nahrávám /
  /// připraveno / pozastaveno). Nativně přepíše notifikaci geolocatoru
  /// (id 75415) — jen když jeho služba běží na popředí. Vrací false, když to
  /// nešlo (služba neběží, chyba) — pak zůstává statický text.
  static Future<bool> notify(String title, String text) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _ch.invokeMethod<bool>('notify', {'title': title, 'text': text}) ?? false;
    } catch (e) {
      rideLog('notif_failed', detail: '$e');
      return false;
    }
  }

  /// Běžná (zavíratelná) notifikace „záznam cesty čeká" — pojistka doma /
  /// dlouhá pauza vypnula GPS. Klepnutí otevře appku.
  static Future<void> notifyIdle(String title, String text) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _ch.invokeMethod<void>('notifyIdle', {'title': title, 'text': text});
    } catch (e) {
      rideLog('notif_failed', detail: 'idle: $e');
    }
  }

  static Future<void> cancelIdle() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _ch.invokeMethod<void>('cancelIdle');
    } catch (_) {}
  }

  /// Stav baterie `{pct, charging}` pro diagnostiku (jen Android, jinak null).
  static Future<Map<String, Object?>?> battery() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final r = await _ch.invokeMethod<Map<Object?, Object?>>('battery');
      return r == null ? null : {for (final e in r.entries) '${e.key}': e.value};
    } catch (_) {
      return null;
    }
  }

  /// Nové okno převzalo zaparkovaný engine (`MainActivity.onStart`). Dart
  /// běží dál, ale pluginy vázané na okno si nativní moduly vytvořily znovu
  /// prázdné — Stripe bez nové inicializace neumí přidat kartu ani zaplatit.
  static Future<dynamic> _onNative(MethodCall call) async {
    if (call.method == 'reattached') {
      Stripe.instance.markNeedsSettings();
      rideLog('engine_reattached');
    }
    return null;
  }
}

/// Obrazovky s vlastním GPS streamem (navigace). geolocator drží JEDEN
/// stream na appku a nastavení mu dá ten, kdo ho otevře první — navigace
/// bez služby na popředí. Když se záznam jízdy připojil k takovému cizímu
/// streamu, po jeho zavření se musí připojit znovu se svým nastavením.
class RideForeignStreams {
  static int _open = 0;
  static VoidCallback? onAllClosed; // nastavuje záznamník jízdy

  static bool get any => _open > 0;
  static void opened() => _open++;
  static void closed() {
    if (_open > 0) _open--;
    if (_open == 0) onAllClosed?.call();
  }
}

/// Diagnostika záznamu do `app_debug_logs` (kategorie `ride`) — Velín ji
/// ukazuje u jízdy, ať je vidět, PROČ ve stopě chybí úsek (appka na pozadí
/// bez fixů, zavřená, chyba GPS služby…).
void rideLog(String action, {String? detail, Map<String, dynamic>? data}) {
  final sink = rideLogTestSink;
  if (sink != null) return sink(action, detail, data);
  AppDebugLogger.instance.log(LogCategory.ride, action, detail: detail, data: data);
}

/// Testy: místo odesílání do `app_debug_logs` sbírat logy sem.
@visibleForTesting
void Function(String action, String? detail, Map<String, dynamic>? data)? rideLogTestSink;
