import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/native/gps_service.dart';
import 'ride_flags.dart';
import 'ride_live_stats.dart';
import 'ride_location.dart';
import 'ride_pause_engine.dart';
import 'ride_provider.dart';
import 'ride_recorder_state.dart';
import 'ride_server_api.dart';
import 'ride_server_seam.dart';
import 'ride_session.dart';

export 'ride_recorder_state.dart';
export 'ride_recorder_watcher.dart' show RideRecorderWatcher;
export 'ride_session.dart' show RidePhase, RidePauseReason;

part 'ride_recorder_stream.dart';
part 'ride_recorder_server.dart';
part 'ride_recorder_pause.dart';
part 'ride_recorder_offline.dart';
part 'ride_recorder_handoff.dart';

/// Záznam jízdy — automaticky během výpůjčky („Moje jízdy") i ručně
/// („Zaznamenat vlastní jízdu").
///
/// Automaticky se nahrává POUZE když: zákazník je přihlášený a má převzatou
/// výpůjčku, má POVOLENOU POLOHU (appka si o ni kvůli záznamu sama neříká)
/// a záznam si nevypnul přepínačem. Body se hromadí lokálně a po dávkách
/// jdou do `user_rides`; rozjetý záznam přežije zavření appky.
///
/// Pauzy (SPEC 2026-10-22): nahrává se JEN když se jede. Stání / chůzi /
/// noc pozná `RidePauseEngine` (auto-pauza, GPS běží, nic se neposílá) a po
/// rozjezdu pokračuje — první bod po pauze nese značku `kmh = −1`. Ruční
/// pauza GPS vypne úplně. Vícedenní cesta zůstává JEDNOU jízdou.
/// Části: `ride_recorder_stream.dart` (GPS stream, lifecycle),
/// `ride_recorder_server.dart` (server, dávky, navázání), `ride_recorder_pause.dart`
/// (pauzy, relace, živé součty, notifikace); hlídač výpůjčky
/// `ride_recorder_watcher.dart`.

/// Hodiny záznamníku — testy je posouvají (vícedenní cesta za pár sekund).
@visibleForTesting
DateTime Function() rideRecorderClock = DateTime.now;

const String kRideAutoRecordKey = 'mg_ride_autorecord'; // přepínač jezdce
const String kRideRecIdKey = 'mg_ride_rec_id'; // id rozjeté nahrávky
const String kRideRecBufKey = 'mg_ride_rec_buf'; // neodeslané GPS body
/// Rozjetá nahrávka je RUČNÍ (vlastní motorka) — hlídač ji pak neukončí jen
/// proto, že zákazník nemá běžící rezervaci.
const String kRideRecManualKey = 'mg_ride_rec_manual';
/// Jezdec dal Ukončit, server to nevzal (offline) — po restartu appky se
/// jízda NErozjede, jen se dál zkouší uložit.
const String kRideStopReqKey = 'mg_ride_stop_req';

const int _kFlushPoints = 20; // dávka bodů
/// Nejvýš tolik bodů v jednom `append_ride_track` (týden offline = desítky
/// tisíc bodů → posílá se po částech, chyba zopakuje jen jednu část).
const int _kAppendChunk = 2000;
const Duration _kFlushEvery = Duration(seconds: 90);
/// Neodeslané body se ukládají do zařízení nejvýš jednou za 30 s / 20 bodů
/// (a vždy při odeslání, pauze, přechodu do pozadí a ukončení).
const Duration _kPersistEvery = Duration(seconds: 30);
/// Nový start: fixy se chvíli drží, než server řekne posun hodin telefonu
/// (jinak by se první body zapsaly s časem telefonu a další „o hodiny zpět").
const Duration _kClockWait = Duration(seconds: 20);
/// Jak dlouho počkat, než se po neúspěchu zkusí jízdu ukončit znovu.
const Duration _kStopRetryAfter = Duration(minutes: 2);
/// Body v dávce starší než tohle patří k předchozí jízdě (stejné okno má
/// server v append_ride_track).
const Duration _kStaleBufferAge = Duration(hours: 1);
/// Bez fixu déle → po návratu do appky se GPS stream připojí znovu (během
/// auto-pauzy je ticho normální → až po 30 min).
const Duration _kNoFixReattach = Duration(minutes: 2);
const Duration _kNoFixReattachPaused = Duration(minutes: 30);
/// Pauza mezi fixy, kterou si zapíšeme do diagnostiky (Velín → jízda).
const Duration _kGapLog = Duration(minutes: 3);

class RideRecorderNotifier extends StateNotifier<RideRecorderState> {
  RideRecorderNotifier(this._ref) : super(const RideRecorderState()) {
    RideForeignStreams.onAllClosed = _onForeignStreamsClosed;
    _restore();
  }

  final Ref _ref;
  RideServerSeam get _api => _ref.read(rideServerSeamProvider);
  /// Stav pro části knihovny (`part` soubory) — `state` je chráněný člen.
  RideRecorderState get _st => state;
  set _st(RideRecorderState v) => state = v;
  StreamSubscription<Position>? _sub;
  StreamSubscription<ServiceStatus>? _svcSub;
  Timer? _timer;
  Timer? _pendTimer; // 30 s, jen v pomalém úseku
  final List<List<double>> _buffer = [];
  double _maxSpeedKmh = 0;
  bool _starting = false;
  /// Právě probíhající odeslání dávky (počká na něj i `stop()`).
  Future<void>? _flushing;
  bool _stopping = false;
  DateTime? _lastStopFail;
  bool _preciseDeclined = false; // iOS: odmítl dočasné zpřesnění polohy
  RideStartResult? _startFail;

  // ── Zdraví GPS streamu a serverové jízdy ──
  DateTime? _attachedAt; // kdy se stream (znovu) připojil
  DateTime? _lastFixAt; // kdy naposledy přišel JAKÝKOLI fix
  Object? _streamError; // stream hlásí chybu / skončil
  String? _lastErrLogged;
  /// Stream je náš (s GPS službou na popředí), ne převzatý od navigace.
  bool _ownStream = true;
  int _attaches = 0;
  int _noFixRetries = 0;
  /// Stream běží, ale serverová jízda ještě není potvrzená (start offline,
  /// čeká se na odpověď) — body se jen hromadí.
  bool _needsServerRide = false;
  Future<bool>? _creating;
  bool _sentFirst = false; // první bod odešel → Velín vidí polohu
  /// Server předchozí jízdu uzavřel / nezná, stream běží dál → navázat.
  bool _continuation = false;
  String? _contFrom;
  String? _contReason;
  bool _abortStart = false;

  // ── Pauzy, relace, server ──
  RidePauseEngine? _engine;
  RideSessionMeta? _restoredSession;
  RideServerCaps _caps = RideServerCaps();
  RideAutoPauseFlag _flag = RideAutoPauseFlag.defaults;
  DateTime? _flagAt;
  DateTime? _probeAt;
  double _clockOff = 0; // server − telefon (s)
  String _proto = 'legacy'; // trip = start_user_trip, legacy = start_user_ride
  double _srvKm = 0;
  int _srvMov = 0;
  int _srvStages = 0; // 0 = server etapy neposílá (starý server)
  int _localStages = 1;
  List<double>? _lastSentPt; // poslední bod, který už server má
  double? _lastEmitTs; // čas posledního vyslaného bodu (odhad etap)
  bool _capsLoaded = false;
  String? _activeBooking; // převzatá výpůjčka (hlídač) — přiřazení ručního startu
  String? _inactiveBooking;
  DateTime? _inactiveAt;
  DateTime? _suppressAutoUntil;
  String? _notifText;
  DateTime? _notifAt;
  DateTime? _notifTry;
  /// Fixy přijaté před první odpovědí serveru (posun hodin) + čas příjmu.
  List<(Position, DateTime)>? _clockQueue;
  DateTime? _clockWaitUntil;
  int _bufDirty = 0; // body přidané od posledního uložení dávky
  DateTime? _persistAt;
  /// Ukázaná notifikace „jsi u startu cesty" / „cesta stojí od …" (zmizí po rozjezdu).
  bool _homeNotified = false;
  /// Začátek relace, která ještě nemá jízdu na serveru (nový start; epoch s
  /// na ose bodů). Body od něj patří k téhle jízdě, i když se ji podaří
  /// založit až za hodiny (start offline) — `start_user_trip_from`.
  double? _sessFrom;
  /// `start_user_trip_from` server nezná (starý server) — kdy to zjistil.
  DateTime? _tripFromMissingAt;
  /// Neúspěšné ukončení (offline) se zkouší znovu i bez dalších událostí.
  Timer? _stopRetryTimer;
  /// Ukončení v tomhle běhu appky selhalo (offline) a ještě se nepovedlo.
  bool _stopFailed = false;
  /// Obnova po startu appky doběhla (do té doby ruční jízda s id „nenahrává"
  /// jen zdánlivě — nesmí se ukončit jako neuložená).
  bool _restoreDone = false;
  Future<bool?>? _stopFlight;
  /// Výměna výpůjčky, body po jejím konci, kontrola vrácení v auto-pauze.
  final _RideHandoff _hand = _RideHandoff();

  Future<void> _restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      final enabled = p.getBool(kRideAutoRecordKey) ?? true;
      final id = p.getString(kRideRecIdKey);
      final manual = p.getBool(kRideRecManualKey) ?? false;
      final raw = p.getString(kRideRecBufKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw);
        if (list is List) {
          for (final e in list) {
            if (e is List && e.length >= 2) {
              _buffer.add([
                for (final v in e)
                  if (v is num) v.toDouble(),
              ]);
            }
          }
        }
      }
      await _loadCaps();
      state = state.copyWith(enabled: enabled, rideId: id, manual: manual);
      // Neuložené Ukončit (offline) se po restartu jen dál ukládá.
      if (_restoreStopReq(p.getString(kRideStopReqKey), id)) return;
      final s = id == null ? null : await RideSessionMeta.load();
      final session = s != null && s.ride == id ? s : null;
      await _restoreSession(id, manual, session);
    } catch (_) {
      /* poškozený cache → začneme načisto */
    } finally {
      _restoreDone = true;
    }
  }

  /// Přepínač v „Mých zážitcích". Vypnutí rozjetou AUTOMATICKOU jízdu
  /// (výpůjčku) ukončí — v kterékoli fázi, i pozastavenou.
  Future<void> setEnabled(bool value) async {
    state = state.copyWith(enabled: value);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(kRideAutoRecordKey, value);
    } catch (_) {}
    if (!value && !state.manual) await stop();
  }

  /// Ruční spuštění záznamu („Zaznamenat vlastní jízdu"). Na rozdíl od
  /// automatického startu si o polohu sám řekne (jezdec klepl).
  Future<bool> startManual() async => await startManualResult() == RideStartResult.ok;

  /// Jako [startManual], ale s důvodem neúspěchu. Do Nastavení NEodvádí —
  /// nápravu nabídne UI. Během převzaté výpůjčky se jízda přiřadí k ní.
  Future<RideStartResult> startManualResult() async {
    if (state.recording) return RideStartResult.ok;
    // Předchozí jízda je ukončená, ale server to nevzal (offline): nejdřív
    // ji uložit. Jinak by ji nový start (server obnovuje otevřenou vlastní
    // cestu) tiše prodloužil o novou jízdu, nebo by se smíchaly body.
    if (stopPending || _stopping) {
      await stop();
      if (stopPending) return RideStartResult.failed;
    }
    final why = await _canUseGps();
    if (why != null) return why;
    _startFail = null;
    await _start(_activeBooking, manual: true);
    if (state.recording) return RideStartResult.ok;
    return _startFail ?? RideStartResult.failed;
  }

  /// Přihlášený + poloha (zeptá se systému, při klepnutí smí i dialogem).
  Future<RideStartResult?> _canUseGps() async {
    if (!_api.signedIn) return RideStartResult.notSignedIn;
    if (!await hasLocationPermission()) {
      final st = await GpsService.status();
      if (st == GpsStatus.serviceOff) return RideStartResult.locationOff;
      if (st != GpsStatus.ok) return RideStartResult.noPermission;
      if (!await hasLocationPermission()) return RideStartResult.noPermission;
    }
    return null;
  }

  /// Má zákazník polohu povolenou? (NEŽÁDÁ o ni — jen se ptá systému.)
  static Future<bool> hasLocationPermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      final perm = await Geolocator.checkPermission();
      return perm == LocationPermission.whileInUse || perm == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  /// Spustí (nebo po restartu appky obnoví) záznam pro běžící výpůjčku.
  /// Pozastavená cesta má `recording == true` → tady se nic nemění.
  Future<void> ensureRecording(String? bookingId) async {
    if (!state.enabled || state.recording || _starting) return;
    if (stopPending) {
      // Neuložená předchozí jízda (offline) má přednost — body obou jízd
      // by se jinak smíchaly v jedné dávce.
      if (canRetryStop) await stop();
      if (stopPending || state.recording) return;
    }
    final now = rideRecorderClock();
    if (_suppressAutoUntil != null && now.isBefore(_suppressAutoUntil!)) return;
    if (bookingId != null && bookingId == _inactiveBooking && _inactiveAt != null &&
        now.difference(_inactiveAt!) < const Duration(minutes: 10)) {
      return; // server výpůjčku už ukončil, seznam rezervací to ještě neví
    }
    if (!_api.signedIn) return;
    if (!await hasLocationPermission()) return;
    await _start(bookingId);
  }

  /// Společné rozjetí nahrávky (automatické i ruční).
  Future<void> _start(String? bookingId, {bool manual = false}) async {
    if (state.recording || _starting) return;
    _starting = true;
    try {
      if (!await _ensurePreciseOnIos()) {
        _startFail = RideStartResult.imprecise;
        return;
      }
      await _loadCaps();
      // GPS stream HNED, dokud je appka v popředí: Android 12+ smí službu na
      // popředí s polohou spustit jen z popředí (a iOS „při používání" taky).
      _sentFirst = false;
      _attaches = 0;
      _noFixRetries = 0;
      _needsServerRide = true; // do potvrzení serverem se nic neposílá
      _continuation = false;
      _abortStart = false;
      _initEngine(bookingId, manual);
      // Body po konci předchozí výpůjčky, které patří téhle (SOS výměna).
      if (!manual && _sessFrom != null) _takeCarry(bookingId);
      final bufStart = _buffer.length; // body tohoto pokusu (viz níže)
      final pointsStart = state.points;
      _attachStream('start');
      state = state.copyWith(recording: true, bookingId: bookingId, manual: manual);
      _syncPhase(log: false);
      final ok = await _ensureServerRide();
      if (!ok && state.recording && (manual || _abortStart)) {
        if (manual) _startFail = RideStartResult.failed; // offline / server
        // Body, které stream mezitím nasbíral, patří k nepovedenému pokusu.
        await _detachStream();
        _needsServerRide = false;
        _abortStart = false;
        _engine = null;
        if (_buffer.length > bufStart) _buffer.removeRange(bufStart, _buffer.length);
        _recomputeMax();
        await _persistBuffer();
        state = state.copyWith(recording: false, points: pointsStart, clearPause: true);
      }
      unawaited(_refreshFlag());
    } finally {
      _starting = false;
    }
  }

  /// iOS 14+: přibližná poloha → požádat o DOČASNÉ zpřesnění (klíč
  /// `rideTracking`). false = jezdec odmítl (pamatuje se do restartu).
  Future<bool> _ensurePreciseOnIos() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return true;
    if (_preciseDeclined) return false;
    try {
      var acc = await Geolocator.getLocationAccuracy();
      if (acc == LocationAccuracyStatus.reduced) {
        acc = await Geolocator.requestTemporaryFullAccuracy(purposeKey: 'rideTracking');
      }
      if (acc == LocationAccuracyStatus.reduced) {
        _preciseDeclined = true;
        return false;
      }
      return true;
    } catch (_) {
      return true; // starší iOS bez tohohle API → přesnost neřešíme
    }
  }

  /// Jazyk appky bez `BuildContext` (hlídač i záznamník běží mimo strom).
  String _lang() {
    try {
      return _ref.read(localeProvider).languageCode;
    } catch (_) {
      return 'cs';
    }
  }

  static String _appState() => WidgetsBinding.instance.lifecycleState?.name ?? 'unknown';

  static bool _isForeground() =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  /// Odešle nasbíranou dávku bodů (dávky, časovač, přechod do pozadí).
  /// Single-flight: souběžné volání počká na rozjeté a skončí (dřív se
  /// stejné body posílaly dvakrát → pád „RangeError (end)", 4.0.2+107).
  Future<void> flush() async {
    final running = _flushing;
    if (running != null) return running;
    // Ukončování předává zbytek dávky samo (finishUserRide). Výjimka:
    // založení jízdy, která vznikla offline — `stop()` na něj počká.
    if (_stopping && _creating == null) return;
    final done = Completer<void>();
    _flushing = done.future;
    try {
      await _flushOnce();
    } catch (e) {
      // Nikdy nepropadne ven — flush se volá bez `await` (časovač, lifecycle).
      debugPrint('[rides] flush selhal: $e');
    } finally {
      // I offline (dávka zůstala) — appku může systém v pozadí zabít.
      if (_bufDirty > 0) await _persistBuffer();
      _flushing = null;
      done.complete();
    }
  }

  /// Ukončí jízdu (v kterékoli fázi) — zbytek dávky se pošle s ukončením,
  /// krátkou jízdu server zahodí. true = uložená, false = zahozená (< 1 km),
  /// null = NEUZAVŘENO (offline) — id zůstává a zkusí se to znovu; UI to
  /// nesmí hlásit jako „příliš krátká".
  /// Souběžné volání (dvojí klepnutí, hlídač, časovač) dostane výsledek
  /// téhož ukončení.
  Future<bool?> stop() => _stopFlight ??= _stopImpl().whenComplete(() => _stopFlight = null);

  /// Smí se teď zkusit (znovu) ukončit jízdu? Po neúspěchu chvíli počkáme.
  bool get canRetryStop =>
      !_stopping &&
      (_lastStopFail == null || rideRecorderClock().difference(_lastStopFail!) > _kStopRetryAfter);

  /// Ukončení se nepovedlo (offline) a čeká na opakování — i když jízdu
  /// server ještě nezaložil (start i konec bez dat) a i po restartu appky
  /// (`mg_ride_stop_req`). Hlídač, návrat do appky i časovač to zkouší
  /// znovu; nový start počká, až se uloží. Jízda obnovená po restartu BEZ
  /// Ukončit (výpůjčka, vlastní cesta bez polohy) sem NEPATŘÍ — tu nic
  /// neukončuje (cesta se nesmí rozdělit).
  bool get stopPending => _restoreDone && !state.recording && !_stopping && _stopFailed;

  // ── Pauzy a cesty (veřejné API pro UI — viz LOGIC_API.md) ──

  /// Ruční pauza (vlastní i výpůjčka): GPS se vypne, nic se nenahrává.
  /// Lokální — nemůže selhat; pokračuje se jen klepnutím [resume].
  Future<void> pause() => _pauseImpl();

  /// Pokračovat po ruční pauze / pojistce (jen z popředí — klepnutí).
  /// Stejné kontroly jako ruční start; `ok` = „připraveno", nahrávat se
  /// začne po rozjezdu.
  Future<RideStartResult> resume() => _resumeImpl();

  /// Odpojit a zapomenout rozjetý záznam BEZ ukončení na serveru (detail
  /// jízdy ho volá před smazáním právě nahrávané jízdy).
  Future<void> discardCurrent() => _discardImpl();

  /// Hláška ([RideRecorderState.notice]) byla ukázaná.
  void consumeNotice() => _consumeNoticeImpl();

  /// Hlídač: převzatá výpůjčka (null = žádná) a kdy ji zákazník převzal.
  /// Ruční start se k ní přiřadí; čas převzetí dělí body při výměně motorky.
  void setActiveBooking(String? bookingId, {DateTime? pickedUpAt}) {
    _activeBooking = bookingId;
    _hand.pickup = bookingId == null ? null : pickedUpAt;
  }

  /// Hlídač vidí jinou převzatou výpůjčku, než do které se nahrává (SOS
  /// výměna motorky, navazující výpůjčka) → starou uložit, nahrávat novou.
  Future<void> switchRental(String bookingId) => _switchRentalImpl(bookingId);

  /// Převzal výpůjčku, zatímco vlastní cesta stojí → vlastní uložit
  /// a nahrávat výpůjčku (SPEC §7.6).
  Future<void> finishOwnForRental(String bookingId) => _finishOwnForRentalImpl(bookingId);

  /// Návrat appky do popředí (hlídač): kontrola GPS streamu, doposlání.
  void onAppResumed() => _onAppResumedImpl();

  /// Navigace zavřela svůj GPS stream. Pokud se záznam připojil k němu
  /// (byl otevřený dřív), má teď nastavení bez služby na popředí → znovu.
  void _onForeignStreamsClosed() {
    if (state.recording && !_ownStream && !_stopping && !state.isManualPaused) {
      _attachStream('foreign_closed');
    }
  }

  /// Testy: tik časovače bez čekání 90 s.
  @visibleForTesting
  void debugTick() => _tick();

  @override
  void dispose() {
    if (RideForeignStreams.onAllClosed == _onForeignStreamsClosed) {
      RideForeignStreams.onAllClosed = null;
    }
    _sub?.cancel();
    _svcSub?.cancel();
    _timer?.cancel();
    _pendTimer?.cancel();
    _stopRetryTimer?.cancel();
    super.dispose();
  }
}

final rideRecorderProvider = StateNotifierProvider<RideRecorderNotifier, RideRecorderState>(
    (ref) => RideRecorderNotifier(ref));
