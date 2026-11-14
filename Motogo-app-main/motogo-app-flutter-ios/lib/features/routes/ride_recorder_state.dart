import 'ride_session.dart';

/// Stav záznamu jízdy pro UI (starý vzhled i v2) — SPEC §5.2.
/// `recording` = „cesta běží" ve VŠECH fázích (i pozastavená); hlídač
/// výpůjčky proto pauzu nikdy „neopraví" novým startem.
class RideRecorderState {
  final bool enabled; // přepínač „zaznamenávat jízdy"
  final bool recording;
  final String? rideId;
  final String? bookingId;
  final int points; // body poslané + čekající v dávce (jen diagnostika)
  /// Ruční záznam (vlastní motorka, bez výpůjčky) — spustil ho jezdec
  /// tlačítkem v „Mých zážitcích" a ukončí ho zase jen on.
  final bool manual;

  /// Poloha se během záznamu ztratila (vypnutá poloha / odebrané oprávnění) —
  /// záznam stojí; UI to řekne (dřív se tiše přestalo nahrávat).
  final bool gpsLost;

  /// Fáze (platí jen při `recording`): nahrává / auto-pauza / ruční pauza.
  final RidePhase phase;
  /// Proč stojí (null během jízdy).
  final RidePauseReason? pauseReason;
  /// Od kdy stojí (místní čas kotvy — kde motorka zastavila / kdy „připraveno").
  final DateTime? pausedSince;
  /// Ujeto v cestě: součet serveru z poslední dávky + neodeslaná dávka.
  final double liveKm;
  /// Čas v sedle (s), stejně jako [liveKm].
  final int liveMovingSec;
  /// Etapy (dny) cesty — ze serveru (≥ 1), jinak odhad z pauz.
  final int liveStages;
  final DateTime? tripStartedAt;
  /// Jednorázová hláška (i18n klíč) — ukáže ji hlídač, pak `consumeNotice()`.
  final String? notice;
  final Map<String, String>? noticeArgs;
  /// Flag `ride_autopause` tak, jak platí pro tuhle cestu.
  final bool autoPauseOn;

  const RideRecorderState({
    this.enabled = true,
    this.recording = false,
    this.rideId,
    this.bookingId,
    this.points = 0,
    this.manual = false,
    this.gpsLost = false,
    this.phase = RidePhase.riding,
    this.pauseReason,
    this.pausedSince,
    this.liveKm = 0,
    this.liveMovingSec = 0,
    this.liveStages = 1,
    this.tripStartedAt,
    this.notice,
    this.noticeArgs,
    this.autoPauseOn = true,
  });

  /// Cesta běží, ale nic se nenahrává (auto i ruční pauza, „připraveno").
  bool get isPaused => recording && phase != RidePhase.riding;
  /// Připraveno — nahrávat se začne po rozjezdu.
  bool get isArmed =>
      recording && phase == RidePhase.autoPaused && pauseReason == RidePauseReason.start;
  bool get isManualPaused => recording && phase == RidePhase.manualPaused;
  /// GPS vypnula pojistka (doma / dlouhá pauza) — UI nabídne Pokračovat / Ukončit.
  /// Jen ruční záznam: výpůjčka Ukončit nemá — po pojistce vypadá jako ruční
  /// pauza (Pokračovat) a otevření appky ji zapne samo.
  bool get needsDecision =>
      isManualPaused &&
      manual &&
      (pauseReason == RidePauseReason.home || pauseReason == RidePauseReason.long);
  /// Ukončit smí jezdec jen ruční (vlastní) záznam; výpůjčka končí vrácením.
  bool get canStop => recording && manual;
  bool get isRidingLive => recording && phase == RidePhase.riding && !gpsLost;

  RideRecorderState copyWith({
    bool? enabled,
    bool? recording,
    String? rideId,
    String? bookingId,
    int? points,
    bool? manual,
    bool? gpsLost,
    RidePhase? phase,
    RidePauseReason? pauseReason,
    DateTime? pausedSince,
    bool clearPause = false,
    double? liveKm,
    int? liveMovingSec,
    int? liveStages,
    DateTime? tripStartedAt,
    String? notice,
    Map<String, String>? noticeArgs,
    bool clearNotice = false,
    bool? autoPauseOn,
    bool clearBooking = false,
    bool clearRide = false,
  }) {
    final cp = clearPause || clearRide;
    final cn = clearNotice || clearRide;
    return RideRecorderState(
      enabled: enabled ?? this.enabled,
      recording: recording ?? this.recording,
      rideId: clearRide ? null : (rideId ?? this.rideId),
      bookingId: clearRide || clearBooking ? null : (bookingId ?? this.bookingId),
      points: points ?? this.points,
      manual: clearRide ? false : (manual ?? this.manual),
      gpsLost: clearRide ? false : (gpsLost ?? this.gpsLost),
      phase: clearRide ? RidePhase.riding : (phase ?? this.phase),
      pauseReason: cp ? null : (pauseReason ?? this.pauseReason),
      pausedSince: cp ? null : (pausedSince ?? this.pausedSince),
      liveKm: clearRide ? 0 : (liveKm ?? this.liveKm),
      liveMovingSec: clearRide ? 0 : (liveMovingSec ?? this.liveMovingSec),
      liveStages: clearRide ? 1 : (liveStages ?? this.liveStages),
      tripStartedAt: clearRide ? null : (tripStartedAt ?? this.tripStartedAt),
      notice: cn ? null : (notice ?? this.notice),
      noticeArgs: cn ? null : (noticeArgs ?? this.noticeArgs),
      autoPauseOn: autoPauseOn ?? this.autoPauseOn,
    );
  }
}

/// Proč se ruční záznam (nebo „Pokračovat") nerozjel — každý důvod má
/// vlastní hlášku a nápravu.
enum RideStartResult { ok, notSignedIn, locationOff, noPermission, imprecise, failed }
