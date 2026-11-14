part of 'ride_recorder.dart';

/// Body další výpůjčky: od jejího převzetí − 2 min (rezerva na hodiny;
/// server novou jízdu začne nejdřív 10 min před převzetím).
const double _kCarrySlackS = 120;
/// Body skončené výpůjčky čekají na start další výpůjčky nejvýš tak dlouho.
const Duration _kCarryKeep = Duration(hours: 12);
/// Výpůjčka stojící v auto-pauze: jak často se zeptat, jestli ještě běží.
const Duration _kRentalCheckEvery = Duration(minutes: 30);
/// Jízdu výpůjčky uzavřel server (motorka v kóji kiosku, výpůjčka běží
/// dál): GPS ještě tak dlouho čeká na ranní vyjetí (táž jízda se po něm
/// sama znovu otevře), pak se vypne — zaparkování bývá i předčasné vrácení.
const Duration _kParkedKeep = Duration(hours: 16);

/// Stav předávání mezi jízdami (výměna motorky, konec výpůjčky).
class _RideHandoff {
  /// Kdy zákazník převzal aktivní výpůjčku (hlídač; serverový čas).
  DateTime? pickup;
  /// Body po konci výpůjčky [carryFrom] — mohou patřit DALŠÍ výpůjčce (SOS
  /// výměna motorky, navazující výpůjčka), kterou hlídač ještě nezná.
  List<List<double>>? carry;
  String? carryFrom;
  DateTime? carryAt;
  /// Nová jízda převzala body z [carry] → po startu oříznout podle
  /// `started_at` serveru (body před převzetím patří předchozí výpůjčce).
  bool cutStart = false;
  bool switching = false;
  DateTime? rentalCheckAt;
  /// Kdy server uzavřel jízdu zaparkované výpůjčky (už zapsané do logu).
  DateTime? parkedAt;
  /// Probíhá probuzení výpůjčky po pojistce (otevření appky).
  bool waking = false;
}

/// Předávání: výměna výpůjčky za jízdy, výpůjčka vrácená během auto-pauzy,
/// ukončení, které server nevzal (přežije zabití appky).
extension _RideRecHandoff on RideRecorderNotifier {
  /// Hlídač vidí jinou převzatou výpůjčku, než do které se nahrává (SOS
  /// výměna motorky, navazující výpůjčka): starou jízdu uložit, body od
  /// převzetí nové motorky dát nové jízdě. Jen výpůjčka převzatá AŽ po
  /// začátku nahrávané jízdy — dvě souběžné výpůjčky jednoho účtu (dvě
  /// motorky) se nikdy nepřepínají; jinak jako dřív [ensureRecording].
  Future<void> _switchRentalImpl(String to) async {
    final from = _st.bookingId;
    if (_st.manual || from == null || from == to || _hand.switching || _stopping || _starting) return;
    final restored = !_st.recording && _st.rideId != null; // po restartu, ještě nenavázaná
    final pickup = _activeBooking == to ? _hand.pickup : null;
    final started = _st.tripStartedAt;
    if (!restored && (pickup == null || started == null || !pickup.isAfter(started))) {
      return ensureRecording(to);
    }
    if (!canRetryStop) return;
    _hand.switching = true;
    try {
      final carry = <List<double>>[];
      if (pickup != null) {
        final cut = pickup.millisecondsSinceEpoch / 1000 - _kCarrySlackS;
        carry.addAll([for (final p in _buffer) if (p.length > 2 && p[2] >= cut) p]);
        if (carry.isNotEmpty) {
          _buffer.removeWhere((p) => p.length > 2 && p[2] >= cut);
          _recomputeMax();
          await _persistBuffer();
        }
      }
      rideLog('rental_switch', data: {
        'from': from,
        'to': to,
        'carry': carry.length,
        if (restored) 'restored': true,
        'app': RideRecorderNotifier._appState(),
      });
      await stop();
      _addCarry(carry, from);
      // Stará jízda ještě neuložená (offline) → hlídač to zkusí znovu.
      if (_st.recording || _st.rideId != null || stopPending) return;
      await ensureRecording(to);
    } finally {
      _hand.switching = false;
    }
  }

  /// Body, které skončená výpůjčka [from] nevzala (nebo nemusela vzít:
  /// po jejím konci), schovat pro start další výpůjčky (`_takeCarry`).
  void _addCarry(List<List<double>> pts, String? from) {
    if (from == null || pts.isEmpty) return;
    final byTs = <double, List<double>>{
      if (_hand.carryFrom == from)
        for (final p in _hand.carry ?? const <List<double>>[]) p[2]: p,
      for (final p in pts)
        if (p.length > 2) p[2]: p,
    };
    _hand
      ..carry = (byTs.values.toList()..sort((a, b) => a[2].compareTo(b[2])))
      ..carryFrom = from
      ..carryAt = rideRecorderClock();
  }

  /// Start výpůjčky [to] hned po konci jiné: body z doby, kdy už jela tahle
  /// (od převzetí − 2 min; bez času převzetí rozhodne `started_at`
  /// serveru), dostane nová jízda přes `start_user_trip_from`.
  void _takeCarry(String? to) {
    _hand.cutStart = false;
    final c = _hand.carry, at = _hand.carryAt, from = _hand.carryFrom;
    if (c == null || at == null) return;
    if (rideRecorderClock().difference(at) > _kCarryKeep) {
      _hand.carry = null;
      return;
    }
    if (to == null || to == from) return; // počká na start jiné výpůjčky
    _hand.carry = null;
    final p = _activeBooking == to ? _hand.pickup : null;
    final cut = p == null ? null : p.millisecondsSinceEpoch / 1000 - _kCarrySlackS;
    final keep = [for (final q in c) if (q.length > 2 && (cut == null || q[2] >= cut)) q];
    if (keep.isEmpty) return;
    _buffer
      ..addAll(keep)
      ..sort((a, b) => a[2].compareTo(b[2]));
    final first = keep.first[2];
    final sf = _sessFrom;
    if (sf == null || first < sf) _sessFrom = first;
    _hand.cutStart = true;
    _recomputeMax();
    rideLog('rental_carry', data: {'n': keep.length, 'from': from, 'to': to});
  }

  /// Po startu jízdy s převzatými body: body před `started_at` serveru
  /// patří předchozí výpůjčce (server novou jízdu začne nejdřív 10 min před
  /// převzetím; bez něj — starý server — jen body této relace).
  void _cutCarried(DateTime? srvStart) {
    if (!_hand.cutStart) return;
    _hand.cutStart = false;
    final s0 = srvStart != null
        ? srvStart.millisecondsSinceEpoch / 1000 - 1
        : rideRecorderClock().millisecondsSinceEpoch / 1000 - 180;
    final n0 = _buffer.length;
    _buffer.removeWhere((p) => p.length > 2 && p[2] < s0);
    if (_buffer.length < n0) {
      _recomputeMax();
      rideLog('rental_carry_cut', data: {'n': n0 - _buffer.length});
    }
  }

  /// Výpůjčka vrácená, zatímco záznam stojí v auto-pauze: na server nic
  /// nejde a hlídač běží jen s otevřenou appkou → jednou za 30 min pauzy se
  /// zeptat, jestli ještě běží; vrácená / dokončená / zrušená → ukončit
  /// (GPS vypnout). Výpůjčka běží, ale jízdu server uzavřel sám (motorka
  /// v kóji kiosku — přes noc i předčasné vrácení, které kiosk dokončí až
  /// den po konci) → GPS čeká na ranní vyjetí [_kParkedKeep], pak Ukončit
  /// (jízda už uzavřená zůstane, jak je; vyjede-li motorka později, start
  /// po otevření appky naváže tutéž jízdu).
  void _checkRentalEnded() {
    final b = _st.bookingId;
    final now = rideRecorderClock();
    if (b == null || !_st.recording || _st.phase != RidePhase.autoPaused || _st.rideId == null ||
        _stopping || _starting) {
      _hand.rentalCheckAt = null;
      return;
    }
    final at = _hand.rentalCheckAt;
    if (at == null) {
      _hand.rentalCheckAt = now;
      return;
    }
    if (now.difference(at) < _kRentalCheckEvery) return;
    _hand.rentalCheckAt = now;
    unawaited(() async {
      bool still() =>
          mounted && _st.bookingId == b && _st.recording && _st.phase != RidePhase.riding && !_stopping;
      final ended = await _api.rentalEnded(b);
      if (ended == false && still()) return _checkRentalParked(b);
      if (ended != true || !still()) return;
      rideLog('rental_ended', data: {'booking': b, 'app': RideRecorderNotifier._appState()});
      await stop();
    }());
  }

  /// Výpůjčka běží, jízdu ale server uzavřel sám (kóje kiosku) → po
  /// [_kParkedKeep] od uzavření GPS vypnout (Ukončit). Starý server → nic.
  Future<void> _checkRentalParked(String b) async {
    final id = _st.rideId;
    if (id == null) return;
    final at = await _api.rentalRideClosedAt(id);
    if (at == null || !mounted || _st.rideId != id || _st.bookingId != b || !_st.recording ||
        _st.phase == RidePhase.riding || _stopping) {
      return;
    }
    final h = (_nowEpoch() - at.millisecondsSinceEpoch / 1000) / 3600;
    final data = {'booking': b, 'ride': id, 'closed': at.toUtc().toIso8601String(), 'h': (h * 10).round() / 10};
    if (_hand.parkedAt != at) {
      _hand.parkedAt = at;
      rideLog('rental_parked', data: {...data, 'app': RideRecorderNotifier._appState()});
    }
    if (h * 3600 < _kParkedKeep.inSeconds) return;
    rideLog('rental_parked_end', data: {...data, 'app': RideRecorderNotifier._appState()});
    await stop();
  }

  /// Výpůjčka, které pojistka vypnula GPS (48 h bez jízdy i bez otevření
  /// appky): otevřením appky se záznam sám znovu zapne („připraveno" —
  /// výpůjčka nikdy nepotřebuje klepnutí). Bez povolené polohy nic (UI
  /// nabídne Pokračovat; o polohu se tu neříká).
  bool get _rentalGuarded =>
      _st.recording && !_st.manual && _st.bookingId != null && _st.isManualPaused &&
      _st.pauseReason == RidePauseReason.long;

  Future<void> _wakeRentalGuard() async {
    if (!_rentalGuarded || _hand.waking || _stopping || _starting) return;
    _hand.waking = true;
    try {
      if (!await RideRecorderNotifier.hasLocationPermission() || !_rentalGuarded) return;
      final since = _st.pausedSince;
      final r = await resume();
      rideLog('rental_guard_wake', data: {'booking': _st.bookingId, 'result': r.name});
      if (r == RideStartResult.ok) {
        _setNotice('rpRentGuardWoke', {'date': rideShortDate(since ?? rideRecorderClock())});
      }
    } finally {
      _hand.waking = false;
    }
  }

  /// Ukončení, které server nevzal (offline) — přežije i zabití appky.
  Future<void> _saveStopReq() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(kRideStopReqKey, jsonEncode({
        'ride': _st.rideId,
        'booking': _st.bookingId,
        'manual': _st.manual,
        if (_sessFrom != null) 'from': _sessFrom,
        'at': rideRecorderClock().millisecondsSinceEpoch / 1000,
      }));
    } catch (_) {}
  }

  /// Obnova po restartu: jezdec dal Ukončit, server to nevzal → jízda se
  /// znovu NEROZJEDE, jen se dál zkouší uložit (hlídač, návrat, časovač).
  /// true = takové ukončení čeká (relace se neobnovuje).
  bool _restoreStopReq(String? raw, String? id) {
    if (raw == null || raw.isEmpty) return false;
    Object? j;
    try {
      j = jsonDecode(raw);
    } catch (_) {}
    final ride = j is Map && j['ride'] is String ? j['ride'] as String : null;
    if (j is! Map || ride != id || (id == null && _buffer.isEmpty)) {
      unawaited(SharedPreferences.getInstance().then((p) => p.remove(kRideStopReqKey)).catchError((_) => false));
      return false;
    }
    final from = j['from'];
    _st = _st.copyWith(
      rideId: id,
      bookingId: j['booking'] is String ? j['booking'] as String : null,
      manual: j['manual'] == true,
      recording: false,
    );
    _stopFailed = true;
    _needsServerRide = id == null;
    _sessFrom = from is num ? from.toDouble() : null;
    _armStopRetry();
    rideLog('stop_pending_restored', data: {'ride': id, 'n': _buffer.length});
    return true;
  }
}
