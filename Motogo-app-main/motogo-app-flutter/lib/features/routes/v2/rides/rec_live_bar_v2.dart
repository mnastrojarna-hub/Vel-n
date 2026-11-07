import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_word_fit.dart';
import '../../ride_recorder.dart' show RideRecorderState;
import 'rec_widgets_v2.dart';
import 'ride_phase_v2.dart';

/// The dock's live recording bar (DESIGN_V22 §4.2 A + SPEC §9.2): phase
/// glyph, PHASE title + live line (km · v sedle / od HH:MM), the 44 px
/// pause / resume disc (every recording) and "■ Ukončit" (manual ride).
/// The red edge + ping only while really riding; paused is neutral.
/// Tap on the text = the recorder screen ([onOpen], null = not tappable).
class RecLiveBarV2 extends StatelessWidget {
  final RideRecorderState rec;
  final VoidCallback? onOpen;
  final VoidCallback onPause;
  final VoidCallback onStop;
  const RecLiveBarV2({super.key, required this.rec, required this.onOpen, required this.onPause, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final ph = RecPhaseV2.of(tr, rec);
    final sub = recBarLineV2(tr, rec, ph);
    final edge = switch (ph.tone) {
      RecToneV2.rec => MgColors.sosDot.withValues(alpha: 0.55),
      RecToneV2.warn => MgColors.warnDark.withValues(alpha: 0.6),
      RecToneV2.armed => MgColors.neonA(0.45),
      RecToneV2.paused => MgColors.white(0.28),
    };
    return LayoutBuilder(builder: (context, c) {
      // Vedle textu: ❚❚ (50) + ■ jen ikonou (50, popisek v sémantice).
      // Když na stav nezbude aspoň ~120 px (úzký telefon, velké písmo),
      // ovládání jde do druhého řádku a text má celou šířku.
      final ts = MediaQuery.textScalerOf(context).scale(1);
      final avail = c.maxWidth - 44 - 50 - (rec.canStop ? 50 : 0);
      final stacked = avail < 120 * ts;
      // „Ukončit" s popiskem v druhém řádku, nebo vedle textu na lištách od
      // 300 dp při běžném písmu (jinak jen 44px ikona, popisek v sémantice).
      final stopLabel = rec.canStop && (stacked || (c.maxWidth >= 300 && ts <= 1.05));
      final text = Semantics(
        button: onOpen != null,
        liveRegion: true,
        label: '${ph.chip}, $sub',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpen,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 6, stacked ? 2 : 8),
            child: Row(children: [
              RecGlyphV2(tone: ph.tone),
              const SizedBox(width: 8),
              Expanded(
                // Titul vždy celý na jeden řádek (zmenší se), řádek pod
                // ním se zalomí jen mezi slovy.
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  MgWordFit(
                    minScale: 0.6,
                    child: Text(ph.chip.toUpperCase(),
                        maxLines: 1,
                        softWrap: false,
                        style: MgType.ctaCompact.copyWith(color: MgColors.onDark, letterSpacing: 0.5)),
                  ),
                  const SizedBox(height: 2),
                  MgWordFit(
                    minScale: 0.75,
                    child: Text(sub,
                        style: MgType.tab(MgType.small.copyWith(
                            fontWeight: FontWeight.w700,
                            color: ph.tone == RecToneV2.warn ? MgColors.warnDark : MgColors.onDarkLead))),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      );
      final controls = <Widget>[
        RecPauseDiscV2(paused: rec.isManualPaused, onTap: onPause),
        const SizedBox(width: 6),
        if (rec.canStop) ...[
          RecStopButtonV2(onTap: onStop, iconOnly: !stopLabel),
          const SizedBox(width: 6),
        ],
      ];
      return Container(
        constraints: const BoxConstraints(minHeight: 56),
        decoration: BoxDecoration(
          color: MgColors.white(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: edge, width: 1.5),
        ),
        child: stacked
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                text,
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(mainAxisAlignment: MainAxisAlignment.end, children: controls),
                ),
              ])
            : Row(children: [Expanded(child: text), ...controls]),
      );
    });
  }
}

/// Second line of a live bar / row (the day and Ø are on the recorder
/// screen): riding → "12,3 km · 45 min v sedle";
/// paused → "od 20:14 · 12,3 km"; armed → the mode (ruční / výpůjčka);
/// GPS lost → "Slabý nebo žádný GPS signál".
String recBarLineV2(AppTranslations tr, RideRecorderState rec, RecPhaseV2 ph) {
  final mode = tr.tr(rec.manual ? 'v2RtRecManual' : 'v2RtRecAuto');
  return switch (ph.tone) {
    // Než přibude první kilometr: jen režim (vlastní / z výpůjčky).
    RecToneV2.rec => rec.liveKm <= 0 && rec.liveMovingSec <= 0 ? mode : recLiveBitsV2(tr, rec, avg: false).take(2).join(' · '),
    RecToneV2.paused => [if (ph.since != null) ph.since!, recLiveBitsV2(tr, rec, avg: false).first].join(' · '),
    RecToneV2.armed => mode,
    RecToneV2.warn => tr.tr('v2RtRecGps'),
  };
}
