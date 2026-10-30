part of 'ride_recorder.dart';

/// Serverová strana záznamu: založení / obnova jízdy (nový `start_user_trip`
/// s fallbackem na `start_user_ride`), dávky, navázání po uzavření serverem,
/// schopnosti serveru, flag auto-pauzy, posun hodin.
extension _RideRecServer on RideRecorderNotifier {
  /// Založí (nebo obnoví) jízdu na serveru. Stream už běží a body se drží
  /// v dávce; offline to zkusí znovu časovač.
  Future<bool> _ensureServerRide() =>
      _creating ??= _createServerRide().whenComplete(() => _creating = null);

  Future<bool> _createServerRide() async {
    try {
      return await _createServerRideOnce();
    } catch (e) {
      debugPrint('[rides] založení jízdy selhalo: $e');
      return false;
    } finally {
      // Odpověď (nebo chyba) je tu → posun hodin platí, fixy zpracovat.
      _releaseClockQueue();
    }
  }

  /// Uložit, co server umí (a kdy se to zjistilo).
  void _setCaps(bool trips) {
    final changed = _caps.trips != trips;
    _caps
      ..trips = trips
      ..at = rideRecorderClock().millisecondsSinceEpoch / 1000;
    unawaited(_caps.save());
    if (changed) rideLog('caps', data: {'trips': trips});
  }

  Future<bool> _createServerRideOnce() async {
    _needsServerRide = true;
    final api = _api;
    final booking = _st.bookingId;
    RideStart? started;
    var proto = 'legacy';
    final nowS = rideRecorderClock().millisecondsSinceEpoch / 1000;
    // Start offline (zahraničí bez dat, hotelová Wi-Fi až večer): jízda
    // začne prvním bodem relace, ne až teď — body z doby offline jsou její.
    final firstTs = _sessionFirstTs();
    if (_caps.trips != false || _caps.stale(nowS)) {
      final r = await _startTripCall(booking, firstTs);
      // Mezitím zastaveno (vypnutý přepínač…) — kromě ukončování.
      if (!_st.recording && !_stopping) {
        _continuation = false;
        return false;
      }
      switch (r.kind) {
        case RideTripStartKind.ok:
          _setCaps(true);
          started = (id: r.id!, resumed: r.resumed, bookingId: r.bookingId);
          proto = 'trip';
          _applyClock(r.clockOffset);
          if (r.resumed) {
            _srvKm = r.distanceKm;
            _srvMov = r.movingSec;
            _srvStages = r.stagesN;
          }
          if (r.startedAt != null && r.resumed) {
            _st = _st.copyWith(tripStartedAt: r.startedAt!.toLocal());
          }
        case RideTripStartKind.missing:
          _setCaps(false); // starý server → start_user_ride níže
        case RideTripStartKind.bookingInactive:
          if (_continuation) {
            // Výpůjčka skončila (vrácení) → žádná jízda po vrácení motorky.
            // Body, které ještě nedošly, nejdřív do TÉŽE jízdy.
            final late = await _drainEndedRental();
            if (late == null) return false; // offline → znovu časovačem
            rideLog('ride_continue_no_booking', data: {'ride': _contFrom, 'booking': booking, 'late': late});
            _continuation = false;
            await _forgetRide();
            return false;
          }
          _inactiveBooking = booking;
          _inactiveAt = rideRecorderClock();
          if (_st.manual) {
            // Ruční start přiřazený k výpůjčce, kterou server už ukončil →
            // nahrává se jako vlastní jízda (jezdec klepl „Zaznamenat").
            _st = _st.copyWith(clearBooking: true);
            _engine?.own = true;
            return _createServerRideOnce();
          }
          // Hlídač ještě neví, že server výpůjčku ukončil → nenahrávat.
          rideLog('server_start_failed', detail: 'booking_inactive', data: {'booking': booking});
          if (_starting) {
            _abortStart = true; // body uložené jízdy doručí Stop hlídače
          } else {
            // Start offline (restart appky): body uložené jízdy doručit.
            final late = await _drainEndedRental();
            if (late == null) return false;
            if (late > 0) rideLog('ride_continue_no_booking', data: {'ride': _st.rideId, 'booking': booking, 'late': late});
            if (_st.rideId == null && _buffer.isNotEmpty) {
              // Výpůjčka celá bez dat a server ji zpětně založit odmítl
              // (starý server / vráceno před víc než 7 dny) — nic tiše.
              rideLog('ride_points_lost', detail: 'booking_inactive', data: {
                'n': _buffer.length,
                'booking': booking,
                if (firstTs != null) 'from': firstTs.round(),
              });
            }
            await _forgetRide();
          }
          return false;
        case RideTripStartKind.notAuthenticated:
        case RideTripStartKind.offline:
        case RideTripStartKind.error:
          // Offline NIKDY neznamená starý server — zkusí se znovu.
          rideLog('server_start_failed', detail: r.kind.name, data: {'manual': _st.manual});
          return false;
      }
    }
    if (started == null) {
      // Bez souřadnic: první bod pošle stream s ČASEM FIXU.
      final s = await api.startLegacy(booking);
      if (!_st.recording && !_stopping) {
        _continuation = false;
        return false;
      }
      if (s == null) {
        rideLog('server_start_failed', data: {'manual': _st.manual, 'proto': 'legacy'});
        return false;
      }
      if (_continuation && booking != null && !s.resumed && s.bookingId == null) {
        // Starý server: výpůjčka už neběží → prázdnou jízdu hned uzavřít.
        rideLog('ride_continue_no_booking', data: {'ride': s.id});
        await api.finish(s.id);
        _continuation = false;
        await _forgetRide();
        return false;
      }
      started = s;
    }
    final wasCont = _continuation;
    _continuation = false;
    if (!started.resumed) {
      // NOVÁ jízda: body staré jízdy (> 1 h) do ní nepatří — kromě bodů
      // TÉHLE relace (start offline: jízda vznikla až teď, body jsou její;
      // server s `start_user_trip_from` ji začne prvním z nich).
      var cutoff = rideRecorderClock().subtract(_kStaleBufferAge).millisecondsSinceEpoch / 1000;
      if (!wasCont && firstTs != null && firstTs < cutoff) cutoff = firstTs;
      final n0 = _buffer.length;
      _buffer.removeWhere((p) => p.length > 2 && p[2] < cutoff);
      if (_buffer.length < n0) rideLog('buffer_stale_cut', data: {'n': n0 - _buffer.length, 'cont': wasCont});
      _recomputeMax();
      await _persistBuffer();
      _resetLive();
    }
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(kRideRecIdKey, started.id);
      await p.setBool(kRideRecManualKey, _st.manual);
    } catch (_) {}
    _proto = proto;
    _st = _st.copyWith(rideId: started.id);
    _needsServerRide = false;
    _sessFrom = null;
    rideLog('ride_start', data: {
      'ride': started.id,
      'resumed': started.resumed,
      'manual': _st.manual,
      'booking': booking,
      'proto': proto,
      if (firstTs != null) 'from': firstTs.round(),
      'app': RideRecorderNotifier._appState(),
    });
    if (wasCont && booking == null && started.id != _contFrom) {
      // Vlastní cesta pokračuje novou jízdou — nikdy tiché zastavení.
      rideLog('trip_continue', data: {'old': _contFrom, 'reason': _contReason, 'ride': started.id});
      _setNotice(proto == 'trip' ? 'rpTripContinuedNew' : 'rpTripContinuedNewOld');
    }
    _updateLive();
    _saveSession();
    flush(); // co se nasbíralo (i první bod → Velín hned vidí polohu)
    return true;
  }

  /// Odeslání dávky a reakce na odpověď serveru (SPEC §7.4). Velká dávka
  /// (dlouho offline) jde po částech [_kAppendChunk].
  Future<void> _flushOnce() async {
    for (var round = 0; round < 100; round++) {
      if (!await _flushChunk()) return;
    }
  }

  /// Jedna část dávky; true = odesláno a ve dávce ještě něco zbývá.
  Future<bool> _flushChunk() async {
    final id = _st.rideId;
    if (id == null || _needsServerRide || _buffer.isEmpty) return false;
    final n = _buffer.length < _kAppendChunk ? _buffer.length : _kAppendChunk;
    final batch = List<List<double>>.from(_buffer.take(n));
    final t0 = rideRecorderClock();
    final res = await _api.append(id, batch, maxSpeedKmh: _maxSpeedKmh > 0 ? _maxSpeedKmh : null);
    final t1 = rideRecorderClock();
    switch (res.result) {
      case RideAppendResult.retry:
        return false; // body zůstanou na příště
      case RideAppendResult.closed:
      case RideAppendResult.gone:
        if (_st.rideId != id) return false;
        if (res.result == RideAppendResult.closed && res.bookingEnded) {
          // Uzavřená výpůjčka část přijala (pozdní body z doby offline; body
          // po vrácení zahodila). Zbytek dávky patří do TÉŽE jízdy — navázání
          // by po vrácení skončilo `booking_inactive` a zbytek zahodilo.
          _buffer.removeRange(0, batch.length < _buffer.length ? batch.length : _buffer.length);
          await _persistBuffer();
          if (_buffer.isNotEmpty && _st.rideId == id) return true;
        }
        if (_st.rideId != id || !_st.recording) return false;
        rideLog('ride_closed_by_server', data: {
          'ride': id,
          'result': res.result.name,
          if (res.bookingEnded) 'booking_ended': true,
          'app': RideRecorderNotifier._appState(),
        });
        // Smazaná vlastní jízda (jezdec ji smazal) → konec záznamu.
        if (res.result == RideAppendResult.gone && _st.bookingId == null) {
          await _forgetRide();
          return false;
        }
        // Jinak navázat: výpůjčka novou jízdou k výpůjčce (konec výpůjčky →
        // `booking_inactive` → konec), vlastní cesta novou jízdou + hláška.
        _continuation = true;
        _contFrom = id;
        _contReason = res.bookingEnded ? 'booking_ended' : res.result.name;
        _needsServerRide = true;
        _resetLive();
        unawaited(_ensureServerRide());
        return false;
      case RideAppendResult.ok:
        break;
    }
    // Mezitím mohla jízda skončit a v dávce už být body jízdy JINÉ.
    if (_st.rideId != id) return false;
    _sentFirst = true;
    final sent = batch.length < _buffer.length ? batch.length : _buffer.length;
    if (sent > 0) _buffer.removeRange(0, sent);
    _lastSentPt = batch.last;
    if (res.distanceKm != null) _srvKm = res.distanceKm!;
    if (res.movingSec != null) _srvMov = res.movingSec!;
    if (res.stagesN != null) _srvStages = res.stagesN!;
    final now = res.serverNow;
    if (now != null) {
      final off = rideClockOffset(now, t0, t1);
      if ((off - _clockOff).abs() > 60) _applyClock(off);
    }
    await _persistBuffer();
    _updateLive();
    _saveSession();
    return _buffer.isNotEmpty && _st.rideId == id;
  }

  /// Posun hodin telefonu vůči serveru (SPEC §5.5).
  void _applyClock(double off) {
    if (off == _clockOff) return;
    _clockOff = off;
    // Stream se připojil s dřívějším posunem → čas připojení na novou osu,
    // jinak by detektor skutečné fixy zahodil jako „z cache".
    final at = _attachedAt;
    if (at != null) _engine?.rebaseAttach(at.millisecondsSinceEpoch / 1000 + off);
    if (off != 0) rideLog('clock_offset', data: {'sec': off.round()});
  }

  Future<void> _loadCaps() async {
    if (_capsLoaded) return;
    _capsLoaded = true;
    _caps = await RideServerCaps.load();
    _flag = RideAutoPauseFlag.fromJson(_caps.ap);
  }

  /// Flag `ride_autopause` (nejvýš jednou za 30 min). Změna za běhu se
  /// promítne do detektoru (vypnutí uvolní držené body / ukončí auto-pauzu).
  Future<void> _refreshFlag({bool force = false}) async {
    final now = rideRecorderClock();
    if (!force && _flagAt != null && now.difference(_flagAt!) < const Duration(minutes: 30)) return;
    _flagAt = now;
    final f = await _api.fetchFlag();
    if (f == null) return; // offline → platí uložený
    _caps
      ..ap = f.toJson()
      ..apAt = now.millisecondsSinceEpoch / 1000;
    unawaited(_caps.save());
    if (f == _flag) return;
    _flag = f;
    rideLog('flag', data: {'on': f.enabled, 'cond': f.toJson()});
    final e = _engine;
    if (e != null && mounted) {
      _applyStep(e.applyConfig(f.toConfig(), f.enabled));
      _st = _st.copyWith(autoPauseOn: f.enabled);
    }
  }

  /// Údržba při návratu do appky: flag, zjištění nového serveru (upgrade
  /// rozjeté „legacy" jízdy na cestu), rozhodnutí detektoru.
  void _maintenance() {
    unawaited(_refreshFlag());
    unawaited(_probeAndUpgrade());
    _engineTick();
  }

  Future<void> _probeAndUpgrade() async {
    final now = rideRecorderClock();
    if (_probeAt != null && now.difference(_probeAt!) < const Duration(minutes: 30)) return;
    if (_caps.trips == true && _proto == 'trip') return;
    _probeAt = now;
    if (_caps.trips != true) {
      final ok = await _api.probe();
      if (ok == null) return;
      _setCaps(ok);
      if (!ok) return;
    }
    // Server se mezitím aktualizoval → rozjetou „legacy" jízdu převzít jako
    // cestu (server ji označí pause_aware a přestane ji v noci dělit).
    final id = _st.rideId;
    if (_proto != 'legacy' || id == null || !_st.recording || _needsServerRide || _starting) return;
    final r = await _api.startTrip(_st.bookingId);
    if (!r.ok || _st.rideId != id) return;
    _applyClock(r.clockOffset);
    if (r.id == id) {
      _proto = 'trip';
      rideLog('caps', detail: 'upgrade', data: {'ride': id, 'trips': true});
    } else {
      // Starou jízdu server mezitím uzavřel → pokračuje se v nové.
      _proto = 'trip';
      _resetLive();
      try {
        final p = await SharedPreferences.getInstance();
        await p.setString(kRideRecIdKey, r.id!);
      } catch (_) {}
      _st = _st.copyWith(rideId: r.id);
      rideLog('trip_continue', data: {'old': id, 'reason': 'upgrade', 'ride': r.id});
      if (_st.bookingId == null) _setNotice('rpTripContinuedNew');
    }
    _saveSession();
  }

  /// Ukončí jízdu (v kterékoli fázi) — zbytek dávky se pošle s ukončením,
  /// krátkou jízdu server zahodí. true = uložená, false = zahozená (< 1 km),
  /// null = NEUZAVŘENO (offline) — id zůstává a zkusí se to znovu.
  Future<bool?> _stopImpl() async {
    if (_stopping) return null;
    _stopping = true;
    try {
      // Po odhlášení nemá kdo jízdu uzavřít — lokální stav zahodit celý.
      if (!_api.signedIn) {
        await _forgetRide();
        return null;
      }
      await _detachStream();
      _releaseClockQueue();
      // Z pomalého úseku jen kotva (kde motorka zastavila); během pauzy nic.
      final tail = _engine?.stopFlush();
      if (tail != null && tail.emit.isNotEmpty) {
        _buffer.addAll(tail.emit);
        await _persistBuffer();
      }
      _cancelPendTimer();
      // Start proběhl offline a jízda na serveru ještě není → založit.
      if (_needsServerRide && !await _ensureServerRide()) {
        if (!_needsServerRide && _st.rideId == null && !_st.recording) {
          // Server jízdu odmítl založit (výpůjčka skončila) a záznam se
          // zapomněl (`_forgetRide`, ztráta je v diagnostice) — není co
          // zkoušet znovu.
          return false;
        }
        _lastStopFail = rideRecorderClock();
        await _detachStream();
        _st = _st.copyWith(recording: false);
        _stopFailed = true;
        _armStopRetry();
        return null;
      }
      // Rozjeté odeslání dávky necháme doběhnout DŘÍV (jinak body 2×).
      final pending = _flushing;
      if (pending != null) await pending;

      final id = _st.rideId;
      var kept = false;
      var closed = id == null;
      if (id != null) {
        final res = await _api.finish(id, points: List<List<double>>.from(_buffer));
        closed = res != null;
        kept = res != null && !res.discarded;
      }
      if (!closed) {
        // Server jízdu NEUZAVŘEL (offline) → id si necháme, zkusí se znovu.
        _lastStopFail = rideRecorderClock();
        await _detachStream();
        _st = _st.copyWith(recording: false);
        _stopFailed = true;
        _armStopRetry();
        return null;
      }
      await _detachStream();
      rideLog('ride_stop', data: {'ride': id, 'kept': kept, 'phase': _st.phase.name, 'app': RideRecorderNotifier._appState()});
      _engine = null;
      _sessFrom = null;
      _stopFailed = false;
      _cancelStopRetry();
      _resetLive();
      _st = _st.copyWith(recording: false, points: 0, clearRide: true);
      _lastStopFail = null;
      _buffer.clear();
      _maxSpeedKmh = 0;
      try {
        final p = await SharedPreferences.getInstance();
        await p.remove(kRideRecIdKey);
        await p.remove(kRideRecBufKey);
        await p.remove(kRideRecManualKey);
      } catch (_) {}
      await RideSessionMeta.clear();
      unawaited(RideKeepAlive.cancelIdle());
      _ref.invalidate(myRidesProvider);
      return kept;
    } finally {
      _stopping = false;
    }
  }
}
