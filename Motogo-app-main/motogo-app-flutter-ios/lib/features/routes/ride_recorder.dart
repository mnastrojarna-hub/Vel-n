import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import '../../core/native/gps_service.dart';
import 'ride_location.dart';
import 'ride_provider.dart';

export 'ride_recorder_watcher.dart' show RideRecorderWatcher;

/// Automatický záznam jízdy během výpůjčky („Moje jízdy").
///
/// Nahrává se POUZE když jsou splněné VŠECHNY podmínky:
///   1. zákazník je přihlášený a má právě běžící rezervaci (aktivní výpůjčku),
///   2. má POVOLENOU POLOHU (oprávnění už udělené — appka si o ně kvůli
///      záznamu sama NEŘÍKÁ) a zapnuté polohové služby,
///   3. záznam si v „Mých zážitcích" nevypnul přepínačem.
/// Body se hromadí lokálně a po dávkách se posílají do `user_rides`. Rozjetý
/// záznam přežije zavření appky (id + nedoručená dávka v SharedPreferences).
/// Jízda končí spolu s výpůjčkou (nebo ručně) a kratší než 1 km se zahodí.
/// GPS část (nastavení streamu, převod fixu na bod) je v `ride_location.dart`,
/// hlídač výpůjčky v `ride_recorder_watcher.dart`.

const String kRideAutoRecordKey = 'mg_ride_autorecord'; // přepínač jezdce
const String kRideRecIdKey = 'mg_ride_rec_id'; // id rozjeté nahrávky
const String kRideRecBufKey = 'mg_ride_rec_buf'; // neodeslané GPS body
/// Rozjetá nahrávka je RUČNÍ (vlastní motorka, bez výpůjčky) — hlídač ji pak
/// neukončí jen proto, že zákazník nemá běžící rezervaci.
const String kRideRecManualKey = 'mg_ride_rec_manual';

const int _kFlushPoints = 20; // dávka bodů
const Duration _kFlushEvery = Duration(seconds: 90);
/// Jak dlouho počkat, než se po neúspěchu zkusí jízdu ukončit znovu.
const Duration _kStopRetryAfter = Duration(minutes: 2);
/// Body v dávce starší než tohle patří k předchozí jízdě (stejné okno má
/// server v append_ride_track).
const Duration _kStaleBufferAge = Duration(hours: 1);
/// Bez fixu déle → po návratu do appky se GPS stream připojí znovu.
const Duration _kNoFixReattach = Duration(minutes: 2);
/// Pauza mezi fixy, kterou si zapíšeme do diagnostiky (Velín → jízda).
const Duration _kGapLog = Duration(minutes: 3);

class RideRecorderState {
  final bool enabled; // přepínač „zaznamenávat jízdy"
  final bool recording;
  final String? rideId;
  final String? bookingId;
  final int points; // body poslané + čekající v dávce
  /// Ruční záznam (vlastní motorka, bez výpůjčky) — spustil ho jezdec
  /// tlačítkem v „Mých zážitcích" a ukončí ho zase jen on.
  final bool manual;

  const RideRecorderState({
    this.enabled = true,
    this.recording = false,
    this.rideId,
    this.bookingId,
    this.points = 0,
    this.manual = false,
  });

  RideRecorderState copyWith({
    bool? enabled,
    bool? recording,
    String? rideId,
    String? bookingId,
    int? points,
    bool? manual,
    bool clearRide = false,
  }) =>
      RideRecorderState(
        enabled: enabled ?? this.enabled,
        recording: recording ?? this.recording,
        rideId: clearRide ? null : (rideId ?? this.rideId),
        bookingId: clearRide ? null : (bookingId ?? this.bookingId),
        points: points ?? this.points,
        manual: clearRide ? false : (manual ?? this.manual),
      );
}

class RideRecorderNotifier extends StateNotifier<RideRecorderState> {
  RideRecorderNotifier(this._ref) : super(const RideRecorderState()) {
    RideForeignStreams.onAllClosed = _onForeignStreamsClosed;
    _restore();
  }

  final Ref _ref;
  StreamSubscription<Position>? _sub;
  Timer? _timer;
  final List<List<double>> _buffer = [];
  double _maxSpeedKmh = 0;
  bool _starting = false;
  /// Právě probíhající odeslání dávky. Drží se jako `Future`, ne jako pouhý
  /// příznak — počká si na něj i `stop()`, viz níže.
  Future<void>? _flushing;
  bool _stopping = false;
  DateTime? _lastStopFail;
  bool _preciseDeclined = false; // iOS: odmítl dočasné zpřesnění polohy

  // ── Zdraví GPS streamu a serverové jízdy ──
  List<double>? _lastKept; // poslední bod stopy (čas + filtr vzdálenosti)
  DateTime? _attachedAt; // kdy se stream (znovu) připojil
  DateTime? _lastFixAt; // kdy naposledy přišel JAKÝKOLI fix
  Object? _streamError; // stream hlásí chybu / skončil
  String? _lastErrLogged;
  bool _overForeign = false; // připojeno k cizímu (navigačnímu) streamu
  int _attaches = 0;
  int _noFixRetries = 0;
  /// Stream běží, ale serverová jízda ještě není potvrzená (start offline,
  /// nebo se čeká na odpověď). Do té doby se body jen hromadí.
  bool _needsServerRide = false;
  Future<bool>? _creating;
  bool _sentFirst = false; // první bod odešel → Velín vidí polohu

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
      state = state.copyWith(enabled: enabled, rideId: id, manual: manual);
      // RUČNÍ jízdu po restartu appky nikdo jiný neobnoví (hlídač řeší jen
      // výpůjčky), takže se stopa rozjede rovnou tady — jinak by nahrávání
      // po zavření appky tiše skončilo a jezdec by přišel o zbytek vyjížďky.
      if (manual && id != null && await hasLocationPermission()) {
        await _ensurePreciseOnIos();
        _attachStream('restore');
        state = state.copyWith(recording: true);
      }
    } catch (_) {/* poškozený cache → začneme načisto */}
  }

  /// Přepínač v „Mých zážitcích". Vypnutí rozjetou jízdu rovnou ukončí.
  Future<void> setEnabled(bool value) async {
    state = state.copyWith(enabled: value);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(kRideAutoRecordKey, value);
    } catch (_) {}
    // Přepínač řídí AUTOMATICKÝ záznam při výpůjčce — ručně rozjetou jízdu
    // ukončí jen tlačítko „Ukončit záznam".
    if (!value && !state.manual) await stop();
  }

  /// Ruční spuštění záznamu BEZ vypůjčené motorky („Zaznamenat vlastní jízdu").
  /// Na rozdíl od automatického startu si o polohu sám řekne — jezdec tuhle
  /// funkci vyvolal klepnutím, takže je systémový dialog očekávaný.
  /// Vrací false, když se záznam nepodařilo rozjet (nepřihlášený / bez polohy).
  Future<bool> startManual() async {
    if (state.recording) return true;
    if (MotoGoSupabase.currentUser == null) return false;
    if (!await hasLocationPermission()) {
      if (!await GpsService.ensurePermission()) return false;
      if (!await hasLocationPermission()) return false;
    }
    await _start(null, manual: true);
    return state.recording;
  }

  /// Má zákazník polohu povolenou? (NEŽÁDÁ o ni — jen se ptá systému.)
  static Future<bool> hasLocationPermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      final perm = await Geolocator.checkPermission();
      return perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  /// Spustí (nebo po restartu appky obnoví) záznam pro běžící výpůjčku.
  Future<void> ensureRecording(String? bookingId) async {
    if (!state.enabled || state.recording || _starting) return;
    if (MotoGoSupabase.currentUser == null) return;
    if (!await hasLocationPermission()) return;
    await _start(bookingId);
  }

  /// Společné rozjetí nahrávky (automatické i ruční).
  Future<void> _start(String? bookingId, {bool manual = false}) async {
    if (state.recording || _starting) return;
    _starting = true;
    try {
      // Bez přesné polohy se nerozjíždí ani serverová jízda — neměla by
      // co dostat. (Ruční start pak vrátí false → hláška v UI.)
      if (!await _ensurePreciseOnIos()) return;
      // GPS stream HNED, dokud je appka v popředí: Android 12+ smí službu na
      // popředí s polohou spustit jen z popředí (a iOS „při používání" taky).
      // Dřív se stream připojoval až po odpovědi serveru — kdo mezitím
      // zamkl telefon, tomu se služba nespustila a vyjížďka zůstala bez bodů.
      _lastKept = null;
      _sentFirst = false;
      _attaches = 0;
      _noFixRetries = 0;
      _needsServerRide = true; // do potvrzení serverem se nic neposílá
      _attachStream('start');
      state = state.copyWith(recording: true, bookingId: bookingId, manual: manual);
      final ok = await _ensureServerRide();
      if (!ok && manual && state.recording) {
        // Ruční start bez serveru se jako dřív nerozjede (UI ohlásí chybu).
        await _detachStream();
        _needsServerRide = false;
        state = state.copyWith(recording: false);
      }
    } finally {
      _starting = false;
    }
  }

  /// Založí (nebo po restartu appky obnoví) jízdu na serveru. Stream už běží
  /// a body se mezitím drží v dávce; offline to zkusí znovu časovač.
  Future<bool> _ensureServerRide() =>
      _creating ??= _createServerRide().whenComplete(() => _creating = null);

  Future<bool> _createServerRide() async {
    try {
      return await _createServerRideOnce();
    } catch (e) {
      debugPrint('[rides] založení jízdy selhalo: $e');
      return false;
    }
  }

  /// [_continuation]: server předchozí jízdu uzavřel (3 h bez fixu — oběd,
  /// noc u vícedenní výpůjčky), ale stream pořád běží. Navazuje se novou
  /// jízdou JEN když ji server přiřadí k té výpůjčce — jinak výpůjčka
  /// skončila a záznam se zastaví (žádné jízdy po vrácení motorky).
  bool _continuation = false;

  Future<bool> _createServerRideOnce() async {
    _needsServerRide = true;
    // Bez souřadnic: první bod pošle stream s ČASEM FIXU. Start s polohou by
    // dostal čas serveru a mícháním dvou hodin vznikal falešný první úsek.
    final started = await startUserRide(bookingId: state.bookingId);
    // Mezitím zastaveno (vypnutý přepínač…) — kromě ukončování: `stop()`
    // jízdu, která vznikla offline, zakládá právě kvůli uzavření.
    if (!state.recording && !_stopping) return false;
    if (started == null) {
      rideLog('server_start_failed', data: {'manual': state.manual});
      return false;
    }
    if (_continuation && !started.resumed && started.bookingId == null) {
      // Výpůjčka už neběží: prázdnou jízdu hned uzavřít (< 1 km → smaže se)
      // a nahrávání ukončit. Body po vrácení nepatří nikam.
      rideLog('ride_continue_no_booking', data: {'ride': started.id});
      await finishUserRide(started.id);
      _continuation = false;
      await _forgetRide();
      return false;
    }
    _continuation = false;
    if (!started.resumed) {
      // Server založil NOVOU jízdu (starou mezitím uzavřel úklid, nebo
      // skončila vrácením). Body staré jízdy (např. po vracení bez signálu)
      // do nové nepatří — server by je viděl jako hodiny starý start.
      final cutoff = DateTime.now().subtract(_kStaleBufferAge)
              .millisecondsSinceEpoch / 1000;
      _buffer.removeWhere((p) => p.length > 2 && p[2] < cutoff);
      _maxSpeedKmh = 0;
      for (final p in _buffer) {
        if (p.length > 3 && p[3] > _maxSpeedKmh) _maxSpeedKmh = p[3];
      }
      await _persistBuffer();
    }
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(kRideRecIdKey, started.id);
      await p.setBool(kRideRecManualKey, state.manual);
    } catch (_) {}
    state = state.copyWith(rideId: started.id);
    _needsServerRide = false;
    rideLog('ride_start', data: {
      'ride': started.id,
      'resumed': started.resumed,
      'manual': state.manual,
      'booking': state.bookingId,
      'app': _appState(),
    });
    flush(); // co se nasbíralo (i první bod → Velín hned vidí polohu)
    return true;
  }

  /// iOS 14+: zákazník může mít polohu povolenou, ale jen „přibližnou"
  /// (Nastavení → Přesná poloha = vypnuto). Fixy pak chodí s přesností
  /// v kilometrech. Požádáme o DOČASNÉ zpřesnění (klíč `rideTracking`
  /// v Info.plist). Vrací false, když ho jezdec odmítl — s přesností
  /// v kilometrech by se nenahrálo nic použitelného (filtr fixů to zahodí)
  /// a jízda by se jako prázdná tiše smazala. Odmítnutí si pamatujeme do
  /// restartu appky, ať se dialog neukazuje při každém překreslení.
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

  static String _appState() =>
      WidgetsBinding.instance.lifecycleState?.name ?? 'unknown';

  static bool _isForeground() =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  /// (Znovu) připojí GPS stream + časovač odesílání dávek.
  void _attachStream(String reason) {
    _sub?.cancel();
    _overForeign = RideForeignStreams.any;
    _attachedAt = DateTime.now();
    _streamError = null;
    try {
      _sub = Geolocator.getPositionStream(
        locationSettings: rideLocationSettings(_lang()),
      ).listen(_onPosition, onError: _onStreamError, onDone: _onStreamDone);
    } catch (e) {
      _sub = null;
      _streamError = e;
    }
    _timer?.cancel();
    _timer = Timer.periodic(_kFlushEvery, (_) => _tick());
    RideKeepAlive.set(true);
    rideLog('stream_attach', detail: reason, data: {
      'n': ++_attaches,
      'app': _appState(),
      if (_overForeign) 'shared': true,
      if (_streamError != null) 'error': '$_streamError',
    });
  }

  Future<void> _detachStream() async {
    final sub = _sub;
    _sub = null;
    _timer?.cancel();
    _timer = null;
    await sub?.cancel();
    RideKeepAlive.set(false);
  }

  void _onStreamError(Object e) {
    _streamError = e;
    final msg = '$e';
    if (msg == _lastErrLogged) return; // stejnou chybu stačí zapsat jednou
    _lastErrLogged = msg;
    rideLog('stream_error', detail: msg, data: {'app': _appState()});
  }

  void _onStreamDone() {
    _streamError ??= 'done';
    _sub = null;
    rideLog('stream_done', data: {'app': _appState()});
  }

  /// Navigace zavřela svůj GPS stream. Pokud se záznam připojil k němu
  /// (byl otevřený dřív), má teď nastavení bez služby na popředí → znovu.
  void _onForeignStreamsClosed() {
    if (state.recording && _overForeign) _attachStream('foreign_closed');
  }

  /// Návrat appky do popředí: tady (a jen tady) smí Android znovu spustit
  /// GPS službu. Stream, který hlásí chybu, skončil, nebo dlouho nedal ani
  /// jeden fix (služba se nespustila / systém ji zabil), se připojí znovu.
  void onAppResumed() {
    if (!state.recording) return;
    final last = _lastFixAt ?? _attachedAt;
    final quiet = last == null || DateTime.now().difference(last) > _kNoFixReattach;
    if (_sub == null || _streamError != null || quiet) {
      _attachStream(_sub == null
          ? 'resume_no_stream'
          : (_streamError != null ? 'resume_error' : 'resume_no_fix'));
    }
    if (_needsServerRide) _ensureServerRide();
    flush();
  }

  /// Časovač (90 s): odeslání dávky, dokončení startu bez sítě a pojistka
  /// pro stream, který po připojení v popředí nedal ani jeden fix.
  void _tick() {
    if (!state.recording) return;
    if (_needsServerRide && !_starting) _ensureServerRide();
    final at = _attachedAt;
    if (at != null && _isForeground() && _noFixRetries < 2 &&
        (_lastFixAt == null || _lastFixAt!.isBefore(at)) &&
        DateTime.now().difference(at) > const Duration(seconds: 60)) {
      _noFixRetries++;
      _attachStream('no_fix');
    }
    flush();
  }

  /// Nový fix → bod stopy (`ridePointFromFix`: čas fixu, filtry přesnosti
  /// a vzdálenosti). Pauzu bez fixů zapíše do diagnostiky.
  void _onPosition(Position pos) {
    if (!state.recording) return;
    final now = DateTime.now();
    final prev = _lastFixAt ?? _attachedAt;
    if (prev != null && now.difference(prev) > _kGapLog) {
      final last = _lastKept;
      rideLog('fix_gap', data: {
        'sec': now.difference(prev).inSeconds,
        if (last != null)
          'm': rideDistanceM(last[0], last[1], pos.latitude, pos.longitude).round(),
        'app': _appState(),
      });
    }
    _lastFixAt = now;
    _streamError = null;
    final point = ridePointFromFix(pos, _lastKept, now: now);
    if (point == null) return;
    _lastKept = point;
    _buffer.add(point);
    if (point[3] > _maxSpeedKmh) _maxSpeedKmh = point[3];
    state = state.copyWith(points: state.points + 1);
    _persistBuffer();
    final first = !_sentFirst && !_needsServerRide && state.rideId != null;
    if (first) _sentFirst = true;
    if (first || _buffer.length >= _kFlushPoints) flush();
  }

  /// Zahodí lokální stopu po jízdě, kterou server už nepřijímá (uzavřel ji
  /// úklid, nebo byla smazaná jako příliš krátká). Nahrávání zastaví —
  /// hlídač ho při běžící výpůjčce rozjede znovu, už do nové jízdy.
  ///
  /// [keepBuffer]: dávku, která uzavření odhalila, si necháme — jsou to
  /// čerstvé body (≤ 90 s) a patří do jízdy, kterou hlídač rozjede vzápětí;
  /// staré body z ní `_createServerRide` odfiltruje podle času.
  Future<void> _forgetRide({bool keepBuffer = false}) async {
    await _detachStream();
    if (!keepBuffer) _buffer.clear();
    _maxSpeedKmh = 0;
    _lastKept = null;
    _needsServerRide = false;
    state = state.copyWith(recording: false, points: 0, clearRide: true);
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(kRideRecIdKey);
      if (!keepBuffer) await p.remove(kRideRecBufKey);
      await p.remove(kRideRecManualKey);
    } catch (_) {}
    _ref.invalidate(myRidesProvider);
  }

  Future<void> _persistBuffer() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(kRideRecBufKey, jsonEncode(_buffer));
    } catch (_) {}
  }

  /// Odešle nasbíranou dávku bodů (volá se po dávkách, časovačem a při
  /// přechodu appky do pozadí).
  ///
  /// Časovač, naplněná dávka i lifecycle (`inactive` a `paused` přijdou hned
  /// po sobě) volají flush() nezávisle na sobě. Bez pojistky se stejné body
  /// poslaly dvakrát (server přičítá km přírůstkově) a dvě souběžná odeslání
  /// si sahala na tutéž dávku → pád „RangeError (end)" (4.0.2+107). Další
  /// volání proto počká na to rozjeté a skončí.
  Future<void> flush() async {
    final running = _flushing;
    if (running != null) return running;
    final done = Completer<void>();
    _flushing = done.future;
    try {
      await _flushOnce();
    } catch (e) {
      // Nikdy nepropadne ven — flush se volá bez `await` (časovač, lifecycle)
      // a neodchycená chyba by skončila jako pád appky.
      debugPrint('[rides] flush selhal: $e');
    } finally {
      _flushing = null;
      done.complete();
    }
  }

  Future<void> _flushOnce() async {
    final id = state.rideId;
    // Jízda ještě není na serveru potvrzená (start offline / čeká se na
    // odpověď) → body držíme, `_createServerRide` je pak pošle sám.
    if (id == null || _needsServerRide || _buffer.isEmpty) return;
    final batch = List<List<double>>.from(_buffer);
    final res = await appendRideTrack(id, batch,
        maxSpeedKmh: _maxSpeedKmh > 0 ? _maxSpeedKmh : null);
    if (res == RideAppendResult.retry) return; // body zůstanou na příště
    if (res == RideAppendResult.finished) {
      // Server jízdu mezitím uzavřel (úklid zatuhlých nahrávek) nebo
      // smazal. Dřív se tu záznam vždy zastavil a rozjel ho až hlídač —
      // tedy až když zákazník appku otevřel. U vícedenní výpůjčky (noc =
      // 3 h bez fixu → úklid) tak další dny nevznikalo nic. Automatická
      // jízda proto naváže novou (stream běží dál, i na pozadí), ruční
      // skončí jako dřív.
      rideLog('ride_closed_by_server', data: {'ride': id, 'app': _appState()});
      if (!state.manual && state.bookingId != null && state.recording) {
        _continuation = true;
        _needsServerRide = true; // do odpovědi serveru nic neposílat
        unawaited(_ensureServerRide());
        return;
      }
      await _forgetRide(keepBuffer: true);
      return;
    }
    // Mezitím mohla jízda skončit a v dávce už být body jízdy JINÉ.
    if (state.rideId != id) return;
    _sentFirst = true;
    // Během odesílání mohly přibýt další body a `stop()` mohl dávku
    // vyprázdnit — ubereme jen tolik, kolik jich tam opravdu je.
    final sent = batch.length < _buffer.length ? batch.length : _buffer.length;
    if (sent > 0) _buffer.removeRange(0, sent);
    await _persistBuffer();
  }

  /// Ukončí jízdu — zbytek dávky se pošle s ukončením, krátkou jízdu server
  /// zahodí. Vrací true = jízda uložená, false = server ji zahodil (krátká),
  /// null = NEUZAVŘENO (offline, výpadek) — lokální id zůstává a zkusí se
  /// to znovu; UI to nesmí hlásit jako „příliš krátká".
  Future<bool?> stop() async {
    if (_stopping) return null;
    _stopping = true;
    try {
      // Po odhlášení nemá kdo jízdu uzavřít (RPC vrátí not_authenticated).
      // Lokální stav zahodíme celý — včetně dávky, ať ji nezdědí jiný účet;
      // serverovou jízdu uklidí cron.
      if (MotoGoSupabase.currentUser == null) {
        await _forgetRide();
        return null;
      }
      await _detachStream();
      // Start proběhl offline a jízda na serveru ještě není → nejdřív ji
      // založit (jinak by dávka skončila v jiné / žádné jízdě).
      if (_needsServerRide && !await _ensureServerRide()) {
        _lastStopFail = DateTime.now();
        state = state.copyWith(recording: false);
        return null;
      }
      // Rozjeté odeslání dávky necháme doběhnout DŘÍV, než dávku převezme
      // `finishUserRide` — jinak by body dostal server podruhé.
      final pending = _flushing;
      if (pending != null) await pending;

      final id = state.rideId;
      var kept = false;
      var closed = id == null;
      if (id != null) {
        final res =
            await finishUserRide(id, points: List<List<double>>.from(_buffer));
        closed = res != null;
        kept = res != null && !res.discarded;
      }

      if (!closed) {
        // Server jízdu NEUZAVŘEL (offline). Id si necháme a zkusíme to
        // znovu — jinak by na serveru zůstala věčně nahrávaná „zombie"
        // a `uq_user_rides_recording` by do ní slepil další vyjížďky.
        _lastStopFail = DateTime.now();
        state = state.copyWith(recording: false);
        return null;
      }

      rideLog('ride_stop', data: {'ride': id, 'kept': kept, 'app': _appState()});
      state = state.copyWith(recording: false, points: 0, clearRide: true);
      _lastStopFail = null;
      _buffer.clear();
      _maxSpeedKmh = 0;
      _lastKept = null;
      try {
        final p = await SharedPreferences.getInstance();
        await p.remove(kRideRecIdKey);
        await p.remove(kRideRecBufKey);
        await p.remove(kRideRecManualKey);
      } catch (_) {}
      _ref.invalidate(myRidesProvider);
      return kept;
    } finally {
      _stopping = false;
    }
  }

  /// Smí se teď zkusit (znovu) ukončit jízdu? Po neúspěchu chvíli počkáme,
  /// ať hlídač nebombarduje server při každém překreslení.
  bool get canRetryStop =>
      !_stopping &&
      (_lastStopFail == null ||
          DateTime.now().difference(_lastStopFail!) > _kStopRetryAfter);

  @override
  void dispose() {
    if (RideForeignStreams.onAllClosed == _onForeignStreamsClosed) {
      RideForeignStreams.onAllClosed = null;
    }
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }
}

final rideRecorderProvider =
    StateNotifierProvider<RideRecorderNotifier, RideRecorderState>(
        (ref) => RideRecorderNotifier(ref));
