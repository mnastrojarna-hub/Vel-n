part of 'ride_recorder.dart';

/// GPS stream záznamu, lifecycle, časovač a příjem fixů.
extension _RideRecStream on RideRecorderNotifier {
  /// Teď (epoch s) opravené o posun hodin telefonu — stejná osa jako čas fixů.
  double _nowEpoch() => rideRecorderClock().millisecondsSinceEpoch / 1000 + _clockOff;

  /// (Znovu) připojí GPS stream + časovač odesílání dávek.
  void _attachStream(String reason) {
    final hadSub = _sub != null;
    _sub?.cancel();
    // Bez cizích odběrů vznikne po zrušení našeho odběru stream nový = náš.
    // Při otevřené navigaci zůstává stream, který tu už byl.
    _ownStream = !RideForeignStreams.any || (hadSub && _ownStream);
    _attachedAt = rideRecorderClock();
    _streamError = null;
    _engine?.onAttach(_nowEpoch(), byTap: reason == 'resume_manual');
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
    _watchService();
    // Engine po zavření okna nechat běžet má smysl jen s VLASTNÍ GPS službou.
    RideKeepAlive.set(_ownStream);
    _notifText = null; // služba ukáže svůj statický text → přepsat znovu
    rideLog('stream_attach', detail: reason, data: {
      'n': ++_attaches,
      'app': RideRecorderNotifier._appState(),
      'phase': _st.phase.name,
      if (!_ownStream) 'shared': true,
      if (_streamError != null) 'error': '$_streamError',
    });
  }

  /// Vypnutí polohy uprostřed jízdy → „GPS ztracen"; po zapnutí znovu.
  void _watchService() {
    if (_svcSub != null) return;
    try {
      _svcSub = Geolocator.getServiceStatusStream().listen((st) {
        if (!mounted || !_st.recording || _stopping || _st.isManualPaused) return;
        final lost = st == ServiceStatus.disabled;
        if (lost != _st.gpsLost) _st = _st.copyWith(gpsLost: lost);
        if (!lost) _attachStream('service_on');
      }, onError: (_) {});
    } catch (_) {/* platforma stav služby nehlásí */}
  }

  Future<void> _detachStream() async {
    final sub = _sub;
    _sub = null;
    _timer?.cancel();
    _timer = null;
    await sub?.cancel();
    await _svcSub?.cancel();
    _svcSub = null;
    RideKeepAlive.set(false);
  }

  void _onStreamError(Object e) {
    _streamError = e;
    if (mounted && _st.recording && !_st.gpsLost && !_st.isManualPaused) {
      _st = _st.copyWith(gpsLost: true);
    }
    final msg = '$e';
    if (msg == _lastErrLogged) return; // stejnou chybu stačí zapsat jednou
    _lastErrLogged = msg;
    rideLog('stream_error', detail: msg, data: {'app': RideRecorderNotifier._appState()});
  }

  void _onStreamDone() {
    _streamError ??= 'done';
    _sub = null;
    rideLog('stream_done', data: {'app': RideRecorderNotifier._appState()});
  }

  /// Návrat appky do popředí: tady (a jen tady) smí Android znovu spustit
  /// GPS službu. Ruční pauza: jen doposlat. Auto-pauza: ticho je normální
  /// (stojí) → znovu připojit až po chybě / 30 min ticha.
  void _onAppResumedImpl() {
    if (_stopping) return;
    if (!_st.recording) {
      // Ukončení, které server nevzal (offline) — teď je šance na signál.
      if (stopPending && canRetryStop) unawaited(stop());
      return;
    }
    final now = _nowEpoch();
    _engine?.noteForeground(now);
    // Vlastní cesta stojí ≥ 20 h (zapomenutý Stop po cestě?) → GPS vypnout
    // a zeptat se; další jízda se tak nikdy tiše nepřidá ke staré cestě.
    final idle = _st.isManualPaused ? null : _engine?.decideIdle(now);
    if (idle != null && idle.detach) {
      unawaited(_applyStep(idle));
      _maintenance();
      return;
    }
    if (!_st.isManualPaused) {
      final last = _lastFixAt ?? _attachedAt;
      final limit = _st.phase == RidePhase.autoPaused ? _kNoFixReattachPaused : _kNoFixReattach;
      final quiet = last == null || rideRecorderClock().difference(last) > limit;
      if (_sub == null || _streamError != null || quiet) {
        _attachStream(_sub == null
            ? 'resume_no_stream'
            : (_streamError != null ? 'resume_error' : 'resume_no_fix'));
      }
      if (_needsServerRide) _ensureServerRide();
    }
    flush();
    _maintenance();
  }

  /// Časovač (90 s): rozhodnutí detektoru (ticho = stání), odeslání dávky,
  /// dokončení startu bez sítě a pojistka pro stream bez fixu.
  void _tick() {
    if (!_st.recording) return;
    _engineTick();
    if (!_st.recording || _st.isManualPaused) return;
    if (_needsServerRide && !_starting) _ensureServerRide();
    final at = _attachedAt;
    // Stojící motorka v auto-pauze fixy neposílá (filtr 20 m) — to je
    // normální, ne mrtvý stream (kotva = stream už fix dal).
    final stillOk = _st.phase == RidePhase.autoPaused && _engine?.anchor != null;
    if (at != null && !stillOk && RideRecorderNotifier._isForeground() && _noFixRetries < 2 &&
        (_lastFixAt == null || _lastFixAt!.isBefore(at)) &&
        rideRecorderClock().difference(at) > const Duration(seconds: 60)) {
      _noFixRetries++;
      _attachStream('no_fix');
    }
    flush();
    _updateNotification();
  }

  /// Nový fix → detektor pauz → body do dávky. Pauzu bez fixů zapíše do
  /// diagnostiky.
  void _onPosition(Position pos) {
    if (!_st.recording || _st.isManualPaused) return;
    if (_st.gpsLost) _st = _st.copyWith(gpsLost: false);
    final now = rideRecorderClock();
    final prev = _lastFixAt ?? _attachedAt;
    if (prev != null && now.difference(prev) > _kGapLog) {
      final last = _engine?.lastEmitted;
      rideLog('fix_gap', data: {
        'sec': now.difference(prev).inSeconds,
        if (last != null) 'm': rideDistanceM(last[0], last[1], pos.latitude, pos.longitude).round(),
        'app': RideRecorderNotifier._appState(),
        'phase': _st.phase.name,
      });
    }
    _lastFixAt = now;
    _streamError = null;
    final wait = _clockWaitUntil;
    if (wait != null) {
      // Nový start: posun hodin ještě nevíme → fix podržet (nejvýš 20 s).
      if (now.isBefore(wait) && (_clockQueue?.length ?? 0) < 300) {
        (_clockQueue ??= []).add((pos, now));
        return;
      }
      _releaseClockQueue();
    }
    _feedFix(pos, now);
  }

  /// Fix → detektor pauz ([now] = čas příjmu, i u podrženého fixu).
  void _feedFix(Position pos, DateTime now) {
    if (!_st.recording || _st.isManualPaused) return;
    final f = rideFixFromPosition(pos, now: now, clockOffset: _clockOff);
    if (f == null) return;
    var e = _engine;
    if (e == null) {
      e = _newEngine(_st.bookingId == null)..startArmed();
      _engine = e;
    }
    _applyStep(e.onFix(f));
  }

  /// Posun hodin je známý (nebo se čekalo dost) → podržené fixy zpracovat.
  void _releaseClockQueue() {
    _clockWaitUntil = null;
    final q = _clockQueue;
    _clockQueue = null;
    if (q == null) return;
    for (final e in q) {
      _feedFix(e.$1, e.$2);
    }
  }
}
