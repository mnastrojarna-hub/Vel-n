import '../../core/i18n/i18n_provider.dart';
import 'ride_live_stats.dart';
import 'ride_recorder.dart';

/// Texty stavu záznamu jízdy pro UI (starý vzhled i v2) — LOGIC_API §1.3.
/// Čisté funkce nad [RideRecorderState]: jaká věta, odkdy, kolik ujeto,
/// jaký štítek. Žádná logika záznamu tady není.

/// Auto-pauza: jezdec stojí / jde pěšky, GPS běží a po rozjezdu se nahrává
/// samo — nic se nemačká (ne „připraveno", ne ruční pauza, ne bez polohy).
bool rideIsAutoPaused(RideRecorderState s) => s.isPaused && !s.isArmed && !s.isManualPaused && !s.gpsLost;

/// Štítek stavu (`rpChipRec` / `rpChipArmed` / `rpChipAuto` / `rpChipPaused`
/// / `rpChipNoGps`); null = nenahrává se.
String? rideChipKey(RideRecorderState s) {
  if (!s.recording) return null;
  // Bez polohy se nenahrává nic — nesmí tvrdit „Nahrávám" (banner nad tím
  // říká, že záznam stojí).
  if (s.gpsLost) return 'rpChipNoGps';
  if (s.isArmed) return 'rpChipArmed';
  if (rideIsAutoPaused(s)) return 'rpChipAuto';
  if (s.isPaused) return 'rpChipPaused';
  return 'rpChipRec';
}

/// „6. 10. 2026 20:14" (místní čas).
String rideShortDateTime(DateTime d) => '${rideShortDate(d)} ${rideClock(d)}';

/// Hlavní věta o stavu záznamu; null = nenahrává se.
String? ridePhaseText(RideRecorderState s, AppTranslations tr) {
  if (!s.recording) return null;
  if (s.gpsLost) return tr.tr('rpPhaseGpsLost');
  if (s.needsDecision) {
    if (s.pauseReason == RidePauseReason.home) return tr.tr('rpPhaseHome');
    final since = s.pausedSince;
    return since == null
        ? tr.tr('rpPhaseManual')
        : tr.trArgs('rpPhaseLong', {'date': rideShortDateTime(since)});
  }
  if (s.isManualPaused) return tr.tr('rpPhaseManual');
  if (s.isArmed) return tr.tr('rpPhaseArmed');
  if (s.phase == RidePhase.autoPaused) return tr.tr('rpPhaseAuto');
  return tr.tr('rpPhaseRiding');
}

/// „od 20:14" — jen u pozastavené cesty (ne u „připraveno" a dlouhé pauzy,
/// ta má datum přímo ve větě).
String? rideSinceText(RideRecorderState s, AppTranslations tr) {
  final since = s.pausedSince;
  if (!s.isPaused || s.isArmed || since == null) return null;
  if (s.needsDecision && s.pauseReason == RidePauseReason.long) return null;
  return tr.trArgs('rpSince', {'time': rideClock(since)});
}

/// Průměr z času v sedle — až po 5 min jízdy (dřív by vycházely nesmysly).
double? rideLiveAvgKmh(RideRecorderState s) {
  if (s.liveMovingSec < 300 || s.liveKm <= 0) return null;
  final v = s.liveKm / (s.liveMovingSec / 3600);
  return v.isFinite && v < 200 ? v : null;
}

/// „12,3 km · 1 h 20 min v sedle · 2. den · Ø 62 km/h"; null = zatím nic
/// neujeto (čerstvě spuštěná cesta čeká na rozjezd).
String? rideLiveText(RideRecorderState s, AppTranslations tr) {
  if (!s.recording || (s.liveKm < 0.05 && s.liveMovingSec < 60)) return null;
  final parts = <String>[
    tr.trArgs('rpLiveLine', {
      'km': rideLiveKm(s.liveKm, tr.lang),
      'time': rideLiveDuration(s.liveMovingSec),
    }),
    if (s.liveStages >= 2) tr.trArgs('rpDayN', {'n': s.liveStages}),
  ];
  final avg = rideLiveAvgKmh(s);
  if (avg != null) parts.add('Ø ${avg.toStringAsFixed(0)} km\u2060/\u2060h');
  return parts.map(rideNoBreakUnits).join(' · ');
}

/// Číslo a jednotka zůstanou na jednom řádku („1235 km", „26 h", „Ø 47",
/// „7. den") — pevná mezera místo obyčejné; mezi částmi se zalomit smí.
String rideNoBreakUnits(String s) =>
    s.replaceAllMapped(RegExp(r'(\d\.?|Ø) (?=\S)'), (m) => '${m[1]}\u00A0');

/// Vysvětlení pod stavem: pojistka (doma / dlouhá pauza) → otázka
/// Pokračovat / Ukončit; ruční pauza → jak pokračovat; jinak jak funguje
/// automatická pauza. [now] jen pro testy.
String rideHintText(RideRecorderState s, AppTranslations tr, {DateTime? now}) {
  if (s.needsDecision) {
    final since = s.pausedSince;
    final h = since == null ? 1 : (now ?? DateTime.now()).difference(since).inHours;
    final args = {'h': h < 1 ? 1 : h};
    return s.pauseReason == RidePauseReason.home
        ? tr.trArgs('rpHintHome', args)
        : tr.trArgs('rpHintLong', args);
  }
  return tr.tr(s.isManualPaused ? 'rpHintManual' : 'rpHintAuto');
}

/// Krátký štítek do navigace: „REC 12,3" / „Připraveno" / „Auto-pauza" /
/// „Pauza" / „Bez GPS". „REC" jen tehdy, když se opravdu nahrává.
String rideNavChipText(RideRecorderState s, AppTranslations tr) {
  if (s.gpsLost) return tr.tr('rpChipNoGps');
  if (s.isArmed) return tr.tr('rpNavArmed');
  if (rideIsAutoPaused(s)) return tr.tr('rpChipAuto');
  if (s.isPaused) return tr.tr('rpNavPaused');
  return s.liveKm >= 0.1 ? 'REC ${rideLiveKm(s.liveKm, tr.lang)}' : 'REC';
}
