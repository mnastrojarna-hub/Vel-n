import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/debug_logger.dart';
import '../../core/i18n/i18n_provider.dart';

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
        notificationTitle: tr.tr('rideNotifTitle'),
        notificationText: tr.tr('rideNotifText'),
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

/// Fix → bod stopy `[lat, lng, čas (epoch s), rychlost km/h, výška m]`.
/// Vrací null, když fix do stopy nepatří. [last] = poslední bod stopy.
///
/// ČAS je čas FIXU, ne čas příjmu. Dřív se bral `DateTime.now()` — jenže
/// systém, který appku na pozadí uspí, po probuzení doručí nastřádané fixy
/// najednou: všechny dostaly tutéž sekundu a server mezi nimi počítal
/// kilometry „za 0 s" (Velín pak ukázal 2,3 km v Ø 97 km/h a čas jízdy —).
/// Rozbité hodiny fixu (budoucnost, roky zpět) se nahradí časem příjmu,
/// hodiny staré fixy z cache a fixy starší než poslední bod se zahodí.
List<double>? ridePointFromFix(Position pos, List<double>? last, {DateTime? now}) {
  var kmh = pos.speed * 3.6;
  if (!kmh.isFinite || kmh < 0) kmh = 0;
  // Nepřesný fix zahazujeme JEN při stání (drift v kavárně = vymyšlené
  // metry). Za jízdy ho necháme — v tunelu nebo městě má fix 60–100 m a
  // pořád kreslí správnou silnici. Přesnost v kilometrech je pryč vždy.
  if (pos.accuracy.isFinite &&
      (pos.accuracy > kRideGarbageAccuracyM ||
          (pos.accuracy > kRideMaxAccuracyM && kmh < 3))) {
    return null;
  }
  if (kmh > 300) kmh = 0;

  final at = now ?? DateTime.now();
  var t = pos.timestamp;
  final age = at.difference(t);
  if (age < const Duration(minutes: -2) || age > const Duration(days: 30)) {
    t = at; // hodiny přijímače mimo realitu → čas příjmu
  } else if (age > kRideFixStale) {
    return null; // stará poloha z cache, ne bod téhle jízdy
  }
  final ts = (t.millisecondsSinceEpoch / 1000).roundToDouble();
  final lat = double.parse(pos.latitude.toStringAsFixed(5));
  final lng = double.parse(pos.longitude.toStringAsFixed(5));

  if (last != null && last.length > 2) {
    // Opožděný / zopakovaný fix (po znovupřipojení streamu přijde nejdřív
    // poslední známá poloha) — do stopy patří jen čas jdoucí dopředu.
    if (ts < last[2]) return null;
    // Vlastní filtr vzdálenosti: stream může být sdílený s navigací, která
    // si ho otevřela s hustším filtrem (geolocator drží jeden na appku).
    if (rideDistanceM(last[0], last[1], lat, lng) < kRideDistanceFilterM) {
      return null;
    }
  }
  final alt = pos.altitude;
  return <double>[
    lat,
    lng,
    ts,
    double.parse(kmh.toStringAsFixed(1)),
    if (alt.isFinite && alt != 0) double.parse(alt.toStringAsFixed(1)),
  ];
}

/// Vzdálenost dvou bodů v metrech (haversine — stejně jako server).
double rideDistanceM(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final h = math.pow(math.sin(rad(lat2 - lat1) / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) *
          math.pow(math.sin(rad(lng2 - lng1) / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}

/// Android: dokud se nahrává jízda, nechá nativní strana Flutter engine
/// naživu i po zavření okna appky (odsunutí z posledních aplikací, Zpět na
/// Androidu 11 a starším). Bez toho zavření okna zrušilo i GPS službu
/// a stopa skončila — `MainActivity` (kanál `cz.motogo24/ride`).
class RideKeepAlive {
  static const _ch = MethodChannel('cz.motogo24/ride');
  static bool? _sent;

  static Future<void> set(bool on) async {
    if (defaultTargetPlatform != TargetPlatform.android || _sent == on) return;
    _sent = on;
    try {
      await _ch.invokeMethod<void>('keepAlive', {'on': on});
    } catch (e) {
      _sent = null; // zkusí se příště znovu
      rideLog('keep_alive_failed', detail: '$e');
    }
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
  AppDebugLogger.instance.log(LogCategory.ride, action, detail: detail, data: data);
}
