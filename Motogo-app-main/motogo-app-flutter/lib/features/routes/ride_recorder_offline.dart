part of 'ride_recorder.dart';

/// Lokální dávka a jízdy bez spojení: uložení / zapomenutí dávky, začátek
/// relace, která na serveru ještě nemá jízdu (start offline →
/// `start_user_trip_from`), doručení bodů skončené výpůjčky a opakování
/// ukončení, které server nevzal.
extension _RideRecOffline on RideRecorderNotifier {
  void _recomputeMax() {
    _maxSpeedKmh = 0;
    for (final p in _buffer) {
      if (p.length > 3 && p[3] > _maxSpeedKmh) _maxSpeedKmh = p[3];
    }
  }

  /// Zahodí lokální stav jízdy, kterou server už nepřijímá (výpůjčka
  /// skončila, jízda smazaná). [keepBuffer]: čerstvé body si necháme pro
  /// jízdu, kterou hlídač rozjede vzápětí (staré odfiltruje start podle času).
  Future<void> _forgetRide({bool keepBuffer = false}) async {
    await _detachStream();
    _clockWaitUntil = null;
    _clockQueue = null;
    if (!keepBuffer) _buffer.clear();
    _maxSpeedKmh = 0;
    _needsServerRide = false;
    _continuation = false;
    _sessFrom = null;
    _stopFailed = false;
    _engine = null;
    _cancelPendTimer();
    _cancelStopRetry();
    _resetLive();
    _st = _st.copyWith(recording: false, points: 0, clearRide: true);
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(kRideRecIdKey);
      if (!keepBuffer) await p.remove(kRideRecBufKey);
      await p.remove(kRideRecManualKey);
    } catch (_) {}
    await RideSessionMeta.clear();
    _ref.invalidate(myRidesProvider);
  }

  Future<void> _persistBuffer() async {
    _bufDirty = 0;
    _persistAt = rideRecorderClock();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(kRideRecBufKey, jsonEncode(_buffer));
    } catch (_) {}
  }

  /// Nejstarší bod relace, která na serveru ještě nemá jízdu (start bez
  /// dat). null = běžný start (body ještě nejsou) / navázání / obnova.
  double? _sessionFirstTs() {
    final from = _sessFrom;
    if (from == null || _st.rideId != null || _continuation) return null;
    double? first;
    for (final p in _buffer) {
      if (p.length > 2 && p[2] >= from && (first == null || p[2] < first)) first = p[2];
    }
    return first;
  }

  /// `start_user_trip_from` (jízda začne prvním bodem relace), když jsou
  /// body z doby offline; server, který ji nezná, → `start_user_trip`.
  Future<RideTripStart> _startTripCall(String? booking, double? firstTs) async {
    final now = rideRecorderClock();
    final m = _tripFromMissingAt;
    if (firstTs != null && (m == null || now.difference(m) > const Duration(minutes: 30))) {
      final r = await _api.startTripFrom(booking, firstTs);
      if (r.kind == RideTripStartKind.missing) {
        if (m == null) rideLog('trip_from_missing', data: {'booking': booking});
        _tripFromMissingAt = now;
      } else if (r.kind != RideTripStartKind.error) {
        return r;
      }
    }
    return _api.startTrip(booking);
  }

  /// Výpůjčka skončila, ale v telefonu zbyly body jízdy [_st.rideId]
  /// (offline v den vrácení, restart appky, ztracená odpověď): doručit je
  /// po částech do TÉŽE jízdy. Server je do uzavřené výpůjčky ještě uloží
  /// a duplicity i body po vrácení zahodí sám, proto se odpověď části
  /// nevyhodnocuje (část z duplicit vrací „uzavřeno" bez důvodu, další už
  /// uložit jde). Vrací počet odeslaných bodů; null = offline (zkusí znovu).
  Future<int?> _drainEndedRental() async {
    final id = _st.rideId;
    var sent = 0;
    for (var round = 0; id != null && round < 100 && _buffer.isNotEmpty; round++) {
      final n = _buffer.length < _kAppendChunk ? _buffer.length : _kAppendChunk;
      final res = await _api.append(id, List<List<double>>.from(_buffer.take(n)));
      if (res.result == RideAppendResult.retry) {
        await _persistBuffer();
        return null;
      }
      if (_st.rideId != id) break;
      _buffer.removeRange(0, n < _buffer.length ? n : _buffer.length);
      sent += n;
      if (res.result == RideAppendResult.gone) break; // smazaná → konec
    }
    if (sent > 0) await _persistBuffer();
    return sent;
  }

  /// Neuložené ukončení zkoušet znovu i bez dalších událostí (appka otevřená
  /// v jiné záložce, žádná změna stavu) — každé ~2 min, dokud se nepovede.
  void _armStopRetry() {
    if (_stopRetryTimer != null) return;
    _stopRetryTimer = Timer.periodic(_kStopRetryAfter + const Duration(seconds: 5), (_) {
      if (!stopPending) {
        _cancelStopRetry();
      } else if (canRetryStop) {
        unawaited(stop());
      }
    });
  }

  void _cancelStopRetry() {
    _stopRetryTimer?.cancel();
    _stopRetryTimer = null;
  }
}
