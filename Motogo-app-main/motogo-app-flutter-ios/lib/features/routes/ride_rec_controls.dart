import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/theme.dart';
import '../../core/widgets/moto_fx.dart';
import 'ride_pause_actions.dart';
import 'ride_rec_phase.dart';
import 'ride_recorder.dart';

/// Ovládání záznamu jízdy ve starém vzhledu (SPEC §9.1): štítek stavu,
/// tlačítka Pozastavit / Pokračovat / Ukončit a karta v „Mých zážitcích".
/// Nic se tu neanimuje — pozastavený stav je statický ❚❚ (reduced motion).

/// Barvy a znak podle stavu: nahrává (červená) / čeká na rozjezd (jantar) /
/// pozastaveno (šedá).
({Color bg, Color fg, String glyph}) rideRecTone(RideRecorderState s) {
  if (s.isArmed) return (bg: MotoGoColors.amberBg, fg: MotoGoColors.amber, glyph: '⏳');
  if (s.isPaused) return (bg: MotoGoColors.g100, fg: MotoGoColors.g600, glyph: '❚❚');
  return (bg: MotoGoColors.redBg, fg: MotoGoColors.red, glyph: '⏺');
}

/// Štítek „⏺ Nahrávám" / „⏳ Čeká na rozjezd" / „❚❚ Pozastaveno".
class RideRecChip extends ConsumerWidget {
  const RideRecChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rec = ref.watch(rideRecorderProvider);
    final key = rideChipKey(rec);
    if (key == null) return const SizedBox.shrink();
    final tone = rideRecTone(rec);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(MotoGoRadius.pill)),
      child: Text('${tone.glyph} ${t(context).tr(key)}',
          style: TextStyle(
              fontSize: MotoGoTypo.sizeSm,
              fontWeight: MotoGoTypo.w800,
              color: tone.fg,
              decoration: TextDecoration.none)),
    );
  }
}

/// Tlačítka záznamu: [Pozastavit] / [Pokračovat] (vlastní i výpůjčka),
/// [Ukončit] jen u vlastní jízdy; po pojistce (doma / dlouhá pauza)
/// [Pokračovat v cestě] [Ukončit a uložit]. Cíle ≥ 44 px.
class RideRecButtons extends StatelessWidget {
  const RideRecButtons({
    super.key,
    required this.rec,
    required this.onToggle,
    required this.onStop,
    this.busy = false,
  });

  final RideRecorderState rec;
  final VoidCallback onToggle;
  final VoidCallback onStop;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final paused = rec.isManualPaused;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      RideRecButton(
        icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
        label: tr.tr(rec.needsDecision ? 'rpResumeTrip' : (paused ? 'rpResume' : 'rpPause')),
        semantics: tr.tr(paused ? 'rpA11yResume' : 'rpA11yPause'),
        primary: paused,
        onTap: busy ? null : onToggle,
      ),
      if (rec.canStop)
        RideRecButton(
          icon: Icons.stop_rounded,
          label: tr.tr(rec.needsDecision ? 'rpEndSave' : 'rideManualStop'),
          danger: true,
          onTap: busy ? null : onStop,
        ),
    ]);
  }
}

class RideRecButton extends StatelessWidget {
  const RideRecButton({
    super.key,
    required this.icon,
    required this.label,
    this.semantics,
    this.primary = false,
    this.danger = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? semantics;
  final bool primary;
  final bool danger;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = danger ? MotoGoColors.red : MotoGoColors.black;
    final bg = primary ? MotoGoColors.green : (danger ? Colors.white : MotoGoColors.g100);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semantics ?? label,
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: PressableScale(
          pressedScale: 0.96,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(MotoGoRadius.pill),
              border: Border.all(color: danger ? MotoGoColors.red : bg, width: 1.4),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    style: TextStyle(
                        fontSize: MotoGoTypo.sizeLg,
                        fontWeight: MotoGoTypo.w800,
                        color: fg,
                        decoration: TextDecoration.none)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Stav záznamu (věta + odkdy / kolik) — karta, sheet v navigaci.
class RideRecStatus extends StatelessWidget {
  const RideRecStatus({super.key, required this.rec});
  final RideRecorderState rec;

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final tone = rideRecTone(rec);
    final sub = [rideSinceText(rec, tr), rideLiveText(rec, tr)].whereType<String>().join(' · ');
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: tone.bg, shape: BoxShape.circle),
        child: Text(tone.glyph, style: TextStyle(fontSize: 15, color: tone.fg, fontWeight: MotoGoTypo.w900)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Semantics(
          liveRegion: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ridePhaseText(rec, tr) ?? '',
                style: const TextStyle(
                    fontSize: MotoGoTypo.sizeXl,
                    fontWeight: MotoGoTypo.w900,
                    color: MotoGoColors.black,
                    decoration: TextDecoration.none)),
            if (sub.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(sub,
                  style: const TextStyle(
                      fontSize: MotoGoTypo.sizeMd,
                      fontWeight: MotoGoTypo.w700,
                      color: MotoGoColors.g500,
                      height: 1.35,
                      decoration: TextDecoration.none)),
            ],
          ]),
        ),
      ),
    ]);
  }
}

/// Jantarový box s otázkou po pojistce (doma / dlouhá pauza).
class RideRecDecisionNote extends StatelessWidget {
  const RideRecDecisionNote({super.key, required this.rec});
  final RideRecorderState rec;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: MotoGoColors.amberBg,
          border: Border.all(color: MotoGoColors.amberBorder),
          borderRadius: BorderRadius.circular(MotoGoRadius.xl),
        ),
        child: Text('🔋 ${rideHintText(rec, t(context))}',
            style: const TextStyle(
                fontSize: MotoGoTypo.sizeBase,
                fontWeight: MotoGoTypo.w700,
                color: Color(0xFF78350F),
                height: 1.35,
                decoration: TextDecoration.none)),
      );
}

/// Karta záznamu v „Mých zážitcích": bez záznamu dnešní „Zaznamenat vlastní
/// jízdu"; během záznamu (vlastní i výpůjčka) stav + Pozastavit/Pokračovat
/// (+ Ukončit u vlastní jízdy) a rozbalovací vysvětlení auto-pauzy.
class RideRecControlsCard extends ConsumerStatefulWidget {
  const RideRecControlsCard({super.key, required this.onStartStop});

  /// Start / ukončení ruční jízdy — strom si dodá vlastní akci.
  final Future<void> Function(bool running) onStartStop;

  @override
  ConsumerState<RideRecControlsCard> createState() => _RideRecControlsCardState();
}

class _RideRecControlsCardState extends ConsumerState<RideRecControlsCard> {
  bool _busy = false;
  bool _how = false;

  Future<void> _run(Future<void> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rec = ref.watch(rideRecorderProvider);
    if (!rec.recording) return _idle(context);
    final tr = t(context);
    final tone = rideRecTone(rec);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(MotoGoRadius.card),
          border: Border.all(color: tone.fg.withValues(alpha: 0.6), width: 1.6),
          boxShadow: MotoGoShadows.cardSmall,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          RideRecStatus(rec: rec),
          if (rec.needsDecision) ...[const SizedBox(height: 10), RideRecDecisionNote(rec: rec)],
          const SizedBox(height: 12),
          RideRecButtons(
            rec: rec,
            busy: _busy,
            onToggle: () => _run(() => rideTogglePause(context, ref)),
            onStop: () => _run(() => widget.onStartStop(true)),
          ),
          if (!rec.manual) ...[
            const SizedBox(height: 8),
            Text(tr.tr('rpRentalEndsHint'), style: _hintStyle),
          ],
          if (!rec.needsDecision) _explainer(context, rec),
          if (rec.needsDecision) const SizedBox(height: 8),
        ]),
      ),
    );
  }

  static const _hintStyle = TextStyle(
      fontSize: MotoGoTypo.sizeMd,
      fontWeight: MotoGoTypo.w600,
      color: MotoGoColors.g500,
      height: 1.35,
      decoration: TextDecoration.none);

  Widget _explainer(BuildContext context, RideRecorderState rec) {
    final tr = t(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Semantics(
        button: true,
        expanded: _how,
        child: InkWell(
          onTap: () => setState(() => _how = !_how),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 17, color: MotoGoColors.greenDarker),
              const SizedBox(width: 6),
              Expanded(
                child: Text(tr.tr('rpHowTitle'),
                    style: const TextStyle(
                        fontSize: MotoGoTypo.sizeBase,
                        fontWeight: MotoGoTypo.w800,
                        color: MotoGoColors.greenDarker,
                        decoration: TextDecoration.none)),
              ),
              Icon(_how ? Icons.expand_less : Icons.expand_more, size: 20, color: MotoGoColors.g400),
            ]),
          ),
        ),
      ),
      if (_how)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(rideHintText(rec, tr), style: _hintStyle),
        ),
    ]);
  }

  /// Dnešní karta „Zaznamenat vlastní jízdu" (beze změny vzhledu).
  Widget _idle(BuildContext context) {
    final tr = t(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PressableScale(
        pressedScale: 0.97,
        onTap: () => _run(() => widget.onStartStop(false)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(MotoGoRadius.card),
            border: Border.all(color: MotoGoColors.greenDark, width: 1.6),
            boxShadow: MotoGoShadows.cardSmall,
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(color: MotoGoColors.greenPale, shape: BoxShape.circle),
              child: const Icon(Icons.fiber_manual_record, size: 20, color: MotoGoColors.greenDark),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr.tr('rideManualStart'),
                    style: const TextStyle(
                        fontSize: MotoGoTypo.sizeXl,
                        fontWeight: MotoGoTypo.w900,
                        color: MotoGoColors.black,
                        decoration: TextDecoration.none)),
                const SizedBox(height: 2),
                Text(tr.tr('rideManualHint'), style: _hintStyle),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
