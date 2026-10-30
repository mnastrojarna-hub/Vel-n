part of 'ride_recorder.dart';

/// Pauzy (ruční / auto / pojistky), relace přes restart, živé součty,
/// jednorázové hlášky a text notifikace GPS služby.
extension _RideRecPause on RideRecorderNotifier {
  RidePauseEngine _newEngine(bool own) =>
      RidePauseEngine(cfg: _flag.toConfig(), own: own, autoPauseOn: _flag.enabled);

  /// Detektor pro nový start; obnova výpůjčky po zabití appky naváže na
  /// uloženou relaci (stejná jízda, stejná výpůjčka).
  void _initEngine(String? bookingId, bool manual) {
    final e = _newEngine(bookingId == null);
    final s = _restoredSession;
    _restoredSession = null;
    if (s != null && s.booking == bookingId && s.ride == _st.rideId &&
        s.phase != RidePhase.manualPaused) {
      e.restore(phase: s.phase, reason: s.reason, since: s.since, anchor: s.anchor,
          last: s.last, start: s.start);
      _sessFrom = null;
    } else {
      e.startArmed();
      _resetLive();
      _clockOff = 0;
      // Body od teď patří k téhle jízdě, i když ji server založí až za
      // hodiny (start bez dat). 3 min rezerva na fix z cache při připojení.
      _sessFrom = rideRecorderClock().millisecondsSinceEpoch / 1000 - 180;
      // Posun hodin řekne až server → první fixy chvíli podržet.
      _clockQueue = null;
      _clockWaitUntil = rideRecorderClock().add(_kClockWait);
      _proto = 'legacy';
      _st = _st.copyWith(liveKm: 0, liveMovingSec: 0, liveStages: 1, tripStartedAt: rideRecorderClock());
    }
    _engine = e;
    _st = _st.copyWith(autoPauseOn: _flag.enabled);
  }

  /// Obnova po restartu appky (SPEC §7.2).
  Future<void> _restoreSession(String? id, bool manual, RideSessionMeta? s) async {
    if (s != null) {
      _clockOff = s.off;
      _proto = s.proto;
      _srvKm = s.liveKm;
      _srvMov = s.liveMov;
      _srvStages = s.liveStages;
      _localStages = s.liveStages;
      _lastSentPt = s.last;
      _st = _st.copyWith(
        bookingId: s.booking,
        liveKm: s.liveKm,
        liveMovingSec: s.liveMov,
        liveStages: s.liveStages,
        notice: s.noticeKey,
        noticeArgs: s.noticeArgs,
        tripStartedAt: s.start == null ? null : rideEpochToLocal(s.start![2] - s.off),
        autoPauseOn: _flag.enabled,
      );
    }
    if (id == null) return;
    if (s != null && s.phase == RidePhase.manualPaused) {
      // Ruční pauza (i výpůjčka): cesta běží, GPS zůstává VYPNUTÉ. Hlídač
      // nic nespustí (recording = true); konec výpůjčky ji ukončí.
      _engine = _newEngine(s.booking == null)
        ..restore(phase: RidePhase.manualPaused, reason: s.reason, since: s.since,
            anchor: s.anchor, last: s.last, start: s.start);
      _st = _st.copyWith(recording: true);
      _syncPhase(log: false);
      // Body neodeslané před pauzou (offline) doposlat hned po startu
      // appky — jinak by čekaly na Pokračovat / přechod do pozadí.
      unawaited(flush());
      return;
    }
    // RUČNÍ jízdu po restartu nikdo jiný neobnoví (hlídač řeší jen výpůjčky).
    if (manual && await RideRecorderNotifier.hasLocationPermission()) {
      final e = _newEngine(s?.booking == null);
      if (s != null) {
        e.restore(phase: s.phase, reason: s.reason, since: s.since, anchor: s.anchor,
            last: s.last, start: s.start);
      } else {
        e.restore(phase: RidePhase.autoPaused); // starší build bez relace
      }
      _engine = e;
      // Vlastní cesta stojí od včerejška a víc (zapomenutý Stop?) → GPS jen
      // na ~1 min (jede-li jezdec právě teď, rozhodne rozjezd), pak vypnout
      // a zeptat se „Pokračovat v cestě / Ukončit a uložit".
      final idle = e.decideIdle(_nowEpoch());
      await _ensurePreciseOnIos();
      _attachStream('restore');
      _st = _st.copyWith(recording: true);
      _syncPhase(log: false);
      if (!idle.isEmpty) unawaited(_applyStep(idle));
      return;
    }
    if (!manual && s != null) _restoredSession = s; // výpůjčka: hlídač → _start
  }

  /// Výstup detektoru → dávka, logy, fáze, odpojení GPS.
  Future<void> _applyStep(RideEngineStep st) {
    if (st.emit.isNotEmpty) {
      for (final p in st.emit) {
        final prev = _lastEmitTs;
        if (prev != null && p.length > 3 && p[3] < 0 && rideIsStageBoundary(prev, p[2])) {
          _localStages++;
        }
        _lastEmitTs = p[2];
      }
      _buffer.addAll(st.emit);
      if (st.maxKmh > _maxSpeedKmh) _maxSpeedKmh = st.maxKmh;
      _st = _st.copyWith(points: _st.points + st.emit.length);
      _persistSoon(st.emit.length);
      _updateLive();
      final first = !_sentFirst && !_needsServerRide && _st.rideId != null;
      if (first) _sentFirst = true;
      if (first || _buffer.length >= _kFlushPoints) flush();
    }
    for (final l in st.logs) {
      rideLog(l.action, detail: l.detail, data: {...l.data, 'app': RideRecorderNotifier._appState()});
    }
    if (st.homeNotice) _notifyHome();
    if (st.phaseChanged) _syncPhase();
    if (st.idle) {
      // Jezdec appku právě otevřel → hláška (notifikace jen, když už appku
      // zase zavřel).
      final since = _st.pausedSince;
      _setNotice('rpTripIdleAsk', {'date': rideShortDate(since ?? rideRecorderClock())});
    }
    _syncPendTimer();
    if (_notifText == null) _updateNotification(force: true);
    if (st.detach) return _detachForPause(notify: !st.idle || !RideRecorderNotifier._isForeground());
    return Future<void>.value();
  }

  /// Fáze detektoru → stav pro UI, relace, notifikace, diagnostika.
  void _syncPhase({bool log = true}) {
    final e = _engine;
    if (e == null) return;
    final from = _st.phase;
    final fromR = _st.pauseReason;
    final since = e.pausedSince;
    _st = _st.copyWith(clearPause: true).copyWith(
          phase: e.phase,
          pauseReason: e.reason,
          pausedSince: since == null ? null : rideEpochToLocal(since - _clockOff),
        );
    if (log && (from != e.phase || fromR != e.reason)) unawaited(_logPhase(from));
    if (_homeNotified && e.phase == RidePhase.riding) {
      _homeNotified = false; // rozjel se → upozornění „u startu" pryč
      unawaited(RideKeepAlive.cancelIdle());
    }
    _saveSession();
    _updateNotification(force: true);
  }

  /// Vlastní cesta stojí u startu (doma?) — upozornit (Android notifikace),
  /// GPS ale běží dál a po rozjezdu se nahrává samo.
  void _notifyHome() {
    final tr = AppTranslations.of(_lang());
    final title = rideTrOpt(tr, 'rpNotifHomeTitle');
    final text = rideTrOpt(tr, 'rpNotifHomeText');
    if (title == null || text == null) return;
    _homeNotified = true;
    unawaited(RideKeepAlive.notifyIdle(title, text));
  }

  /// Dávku uložit do zařízení nejvýš jednou za 30 s / 20 bodů (týden
  /// offline = MB JSONu; přepis při každém fixu by žral baterii).
  void _persistSoon(int added) {
    _bufDirty += added;
    final at = _persistAt;
    if (_bufDirty >= _kFlushPoints || at == null ||
        rideRecorderClock().difference(at) >= _kPersistEvery) {
      unawaited(_persistBuffer());
    }
  }

  Future<void> _logPhase(RidePhase from) async {
    final bat = await RideKeepAlive.battery();
    rideLog('phase', data: {
      'from': from.name,
      'to': _st.phase.name,
      if (_st.pauseReason != null) 'reason': _st.pauseReason!.name,
      if (bat != null) 'battery': bat,
      'app': RideRecorderNotifier._appState(),
    });
  }

  /// Ruční pauza / pojistka: doposlat, vypnout GPS (služba na popředí
  /// skončí, modrý indikátor na iOS zmizí), uložit relaci.
  Future<void> _detachForPause({bool notify = true}) async {
    final r = _engine?.reason;
    _cancelPendTimer();
    // GPS vypnout HNED (ani viselé spojení ho nesmí držet zapnuté),
    // dávku doposlat potom.
    await _detachStream();
    if (_st.gpsLost) _st = _st.copyWith(gpsLost: false);
    _saveSession();
    unawaited(_persistBuffer());
    unawaited(flush());
    if (notify && (r == RidePauseReason.home || r == RidePauseReason.long)) {
      final tr = AppTranslations.of(_lang());
      final title = rideTrOpt(tr, 'rpNotifIdleTitle');
      final text = rideTrOpt(tr, 'rpNotifIdleText');
      if (title != null && text != null) await RideKeepAlive.notifyIdle(title, text);
    }
  }

  Future<void> _pauseImpl() async {
    if (!_st.recording || _st.isManualPaused || _stopping) return;
    var e = _engine;
    if (e == null) {
      e = _newEngine(_st.bookingId == null)..startArmed();
      _engine = e;
    }
    await _applyStep(e.pauseManual(_nowEpoch()));
  }

  Future<RideStartResult> _resumeImpl() async {
    if (!_st.recording) return RideStartResult.failed;
    if (!_st.isManualPaused) return RideStartResult.ok;
    final why = await _canUseGps();
    if (why != null) return why;
    if (!await _ensurePreciseOnIos()) return RideStartResult.imprecise;
    if (!_st.isManualPaused) return RideStartResult.ok; // mezitím vyřešeno
    var e = _engine;
    if (e == null) {
      e = _newEngine(_st.bookingId == null)..restore(phase: RidePhase.manualPaused);
      _engine = e;
    }
    _noFixRetries = 0;
    _attachStream('resume_manual');
    unawaited(RideKeepAlive.cancelIdle());
    _homeNotified = false;
    await _applyStep(e.resumeManual(_nowEpoch()));
    if (_needsServerRide) _ensureServerRide();
    unawaited(_refreshFlag());
    return RideStartResult.ok;
  }

  Future<void> _discardImpl() async {
    if (_st.rideId == null && !_st.recording) return;
    // Hlídač by výpůjčku hned rozjel znovu do mazané jízdy — chvíli počkat.
    _suppressAutoUntil = rideRecorderClock().add(const Duration(seconds: 30));
    rideLog('ride_discard', data: {'ride': _st.rideId, 'phase': _st.phase.name});
    await _forgetRide();
    unawaited(RideKeepAlive.cancelIdle());
  }

  void _consumeNoticeImpl() {
    if (_st.notice == null) return;
    _st = _st.copyWith(clearNotice: true);
    _saveSession();
  }

  void _setNotice(String key, [Map<String, String>? args]) {
    _st = _st.copyWith(notice: key, noticeArgs: args);
    _saveSession();
  }

  Future<void> _finishOwnForRentalImpl(String bookingId) async {
    if (!_st.recording || !_st.manual || _st.bookingId == bookingId ||
        !_st.isPaused || _stopping || !canRetryStop) {
      return;
    }
    final from = _st.tripStartedAt ?? rideRecorderClock();
    final kept = await stop();
    if (_st.recording || _st.rideId != null) return; // neuloženo → zkusí se znovu
    rideLog('own_saved_for_rental', data: {'kept': kept, 'booking': bookingId});
    await ensureRecording(bookingId);
    if (kept == true) _setNotice('rpOwnSavedForRental', {'date': rideShortDate(from)});
  }

  void _saveSession() {
    final id = _st.rideId;
    if (id == null) return;
    final e = _engine;
    unawaited(RideSessionMeta(
      ride: id,
      booking: _st.bookingId,
      manual: _st.manual,
      proto: _proto,
      phase: e?.phase ?? _st.phase,
      reason: e?.reason ?? _st.pauseReason,
      since: e?.pausedSince,
      anchor: e?.anchor,
      last: e?.lastEmitted,
      start: e?.tripStart,
      off: _clockOff,
      liveKm: _st.liveKm,
      liveMov: _st.liveMovingSec,
      liveStages: _st.liveStages,
      liveAt: rideRecorderClock().millisecondsSinceEpoch / 1000,
      noticeKey: _st.notice,
      noticeArgs: _st.noticeArgs,
    ).save());
  }

  /// Živé km / čas v sedle = součet serveru + neodeslaná dávka.
  void _updateLive() {
    final d = rideLiveDelta(_lastSentPt, _buffer);
    _st = _st.copyWith(
      liveKm: _srvKm + d.km,
      liveMovingSec: _srvMov + d.movingSec,
      liveStages: _srvStages > 0 ? _srvStages : _localStages,
    );
  }

  void _resetLive() {
    _srvKm = 0;
    _srvMov = 0;
    _srvStages = 0;
    _localStages = 1;
    _lastSentPt = null;
    _lastEmitTs = null;
  }

  void _engineTick() {
    final e = _engine;
    if (e == null || !_st.recording) return;
    final st = e.onTick(_nowEpoch(), liveKm: _st.liveKm, stages: _st.liveStages);
    if (!st.isEmpty) _applyStep(st);
  }

  /// V pomalém úseku rozhodovat častěji (30 s) — stání se pozná bez fixů.
  void _syncPendTimer() {
    final pend = _engine?.isPending == true && _st.recording && !_st.isManualPaused;
    if (pend && _pendTimer == null) {
      _pendTimer = Timer.periodic(const Duration(seconds: 30), (_) => _engineTick());
    } else if (!pend) {
      _cancelPendTimer();
    }
  }

  void _cancelPendTimer() {
    _pendTimer?.cancel();
    _pendTimer = null;
  }

  /// Android: text trvalé notifikace podle stavu (při změně fáze hned,
  /// za jízdy nejvýš jednou za 5 min). Chybí-li překlad, zůstane statický.
  void _updateNotification({bool force = false}) {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (!_st.recording || _st.isManualPaused || !_ownStream || _sub == null) return;
    final now = rideRecorderClock();
    if (_notifText == null && _notifTry != null &&
        now.difference(_notifTry!) < const Duration(seconds: 30)) {
      return;
    }
    final tr = AppTranslations.of(_lang());
    String? title, text;
    if (_st.isArmed) {
      title = rideTrOpt(tr, 'rpNotifArmedTitle');
      text = rideTrOpt(tr, 'rpNotifArmed');
    } else if (_st.phase == RidePhase.autoPaused) {
      title = rideTrOpt(tr, 'rpNotifPausedTitle');
      text = rideTrOpt(tr, 'rpNotifPaused', {'time': rideClock(_st.pausedSince ?? now)});
    } else {
      title = rideTrOpt(tr, 'rpNotifRidingTitle');
      text = rideTrOpt(tr, 'rpNotifRiding', {
        'km': rideLiveKm(_st.liveKm, tr.lang),
        'time': rideLiveDuration(_st.liveMovingSec),
      });
    }
    if (title == null || text == null) return;
    final key = '$title\n$text';
    if (key == _notifText) return;
    if (!force && _notifText != null && _notifAt != null &&
        now.difference(_notifAt!) < const Duration(minutes: 5)) {
      return;
    }
    _notifTry = now;
    RideKeepAlive.notify(title, text).then((ok) {
      if (!ok) return;
      _notifText = key;
      _notifAt = rideRecorderClock();
    });
  }
}
