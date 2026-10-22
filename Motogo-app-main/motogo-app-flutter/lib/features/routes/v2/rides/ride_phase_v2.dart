import '../../../../core/i18n/i18n_provider.dart';
import '../../ride_live_stats.dart';
import '../../ride_recorder.dart';

/// Tone of a live recording surface: riding (red ping), paused (neutral,
/// static ❚❚), armed (neon, waiting to ride), warn (GPS lost).
enum RecToneV2 { rec, paused, armed, warn }

/// What every v2 recording surface (dock bar, recorder card, Domů row,
/// Moje row, nav chip, pause sheet) says about the recorder — one mapping
/// of SPEC §5.2 so the looks never disagree:
///   riding → NAHRÁVÁM · armed → ČEKÁM NA ROZJEZD · auto / manual pause →
///   POZASTAVENO (+ od HH:MM) · guard home / long → ZPĚT NA STARTU / GPS
///   VYPNUTÉ · GPS lost → the existing "Poloha je vypnutá" state.
class RecPhaseV2 {
  const RecPhaseV2({
    required this.status,
    required this.chip,
    required this.title,
    required this.tone,
    this.since,
  });

  /// Upper-case status of the big card (NAHRÁVÁM / POZASTAVENO …).
  final String status;

  /// Short label (bar title, chips, badges): Nahrávám / Pozastaveno / Čeká na rozjezd.
  final String chip;

  /// One sentence of what is happening ("Stojíš — záznam se sám pozastavil").
  final String title;
  final RecToneV2 tone;

  /// "od 20:14" (or "od 6. 10. 20:14" when not today) while paused.
  final String? since;

  /// Ping / pulse allowed (riding, GPS fine). Everything else is static.
  bool get riding => tone == RecToneV2.rec;
  bool get paused => tone == RecToneV2.paused;

  static RecPhaseV2 of(AppTranslations tr, RideRecorderState rec, {DateTime? now}) {
    final s = rec.pausedSince;
    final since = s == null ? null : tr.trArgs('v2RpSince', {'time': recSinceV2(s, now: now)});
    if (rec.gpsLost) {
      return RecPhaseV2(
          status: tr.tr('rideRecording').toUpperCase(), chip: tr.tr('rideRecording'), title: tr.tr('v2RtRecGps'), tone: RecToneV2.warn);
    }
    if (rec.isArmed) {
      return RecPhaseV2(
          status: tr.tr('v2RpStatusArmed'), chip: tr.tr('v2RpChipArmed'), title: tr.tr('v2RpPhaseArmed'), tone: RecToneV2.armed);
    }
    if (rec.needsDecision) {
      final home = rec.pauseReason == RidePauseReason.home;
      return RecPhaseV2(
        status: tr.tr(home ? 'v2RpStatusHome' : 'v2RpStatusLong'),
        chip: tr.tr('v2RpChipPaused'),
        title: tr.tr(home ? 'v2RpPhaseHome' : 'v2RpPhaseLong'),
        tone: RecToneV2.paused,
        since: since,
      );
    }
    if (rec.isManualPaused) {
      return RecPhaseV2(
          status: tr.tr('v2RpStatusPaused'), chip: tr.tr('v2RpChipPaused'), title: tr.tr('v2RpPhaseManual'), tone: RecToneV2.paused, since: since);
    }
    if (rec.isPaused) {
      return RecPhaseV2(
          status: tr.tr('v2RpStatusPaused'), chip: tr.tr('v2RpChipPaused'), title: tr.tr('v2RpPhaseAuto'), tone: RecToneV2.paused, since: since);
    }
    return RecPhaseV2(
        status: tr.tr('v2RpStatusRec'), chip: tr.tr('rideRecording'), title: tr.tr('v2RpPhaseRiding'), tone: RecToneV2.rec);
  }
}

/// "20:14" today, "6. 10. 20:14" on another day (local time).
String recSinceV2(DateTime t, {DateTime? now}) {
  final l = t.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  final today = l.year == n.year && l.month == n.month && l.day == n.day;
  return today ? rideClock(l) : '${l.day}. ${l.month}. ${rideClock(l)}';
}

/// Live numbers of the running trip as separate bits (chips / one line):
/// km · time in the saddle · Ø (after ≥ 5 min riding) · "2. den" (≥ 2).
List<String> recLiveBitsV2(AppTranslations tr, RideRecorderState rec, {bool avg = true}) {
  final out = <String>[
    '${rideLiveKm(rec.liveKm, tr.lang)} km',
    tr.trArgs('v2RpChipRiding', {'time': rideLiveDuration(rec.liveMovingSec)}),
  ];
  if (avg) {
    final a = recAvgV2(rec);
    if (a != null) out.add(tr.trArgs('v2RpChipAvg', {'v': a}));
  }
  if (rec.liveStages >= 2) out.add(tr.trArgs('v2RpChipDay', {'n': rec.liveStages}));
  return out;
}

/// "12,3 km · 45 min v sedle · 2. den" — the compact live line.
String recLiveLineV2(AppTranslations tr, RideRecorderState rec) => recLiveBitsV2(tr, rec, avg: false).join(' · ');

/// Average speed in the saddle (whole km/h) once there is ≥ 5 min of riding.
String? recAvgV2(RideRecorderState rec) {
  if (rec.liveMovingSec < 300 || rec.liveKm <= 0) return null;
  final v = rec.liveKm / (rec.liveMovingSec / 3600);
  return v.isFinite && v < 200 ? v.toStringAsFixed(0) : null;
}

/// What the rider should know in this state (why it is paused, what to do).
String recHintV2(AppTranslations tr, RideRecorderState rec, {DateTime? now}) {
  if (rec.needsDecision) {
    final s = rec.pausedSince;
    return tr.trArgs('v2RpHintGuard', {'since': s == null ? '—' : recSinceV2(s, now: now)});
  }
  if (rec.isManualPaused) return tr.tr('v2RpHintManual');
  if (rec.isArmed) return tr.tr('v2RpHintArmed');
  return tr.tr('v2RpHintAuto');
}

/// Days label "3 dny" (plural form by language, `v2RpDays*`).
String recDaysV2(AppTranslations tr, int n) => tr.trArgs('v2RpDays${ridePluralForm(n, tr.lang)}', {'n': n});

/// Rides label "4 jízdy" (`v2RpRides*`).
String recRidesV2(AppTranslations tr, int n) => tr.trArgs('v2RpRides${ridePluralForm(n, tr.lang)}', {'n': n});
