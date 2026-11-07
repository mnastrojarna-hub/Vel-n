import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../routes/ride_actions.dart';
import '../../routes/ride_recorder.dart';
import '../../routes/v2/rides/rec_live_bar_v2.dart' show recBarLineV2;
import '../../routes/v2/rides/rec_widgets_v2.dart';
import '../../routes/v2/rides/recorder_screen_v2.dart' show openRideRecorderV2;
import '../../routes/v2/rides/ride_pause_actions_v2.dart';
import '../../routes/v2/rides/ride_phase_v2.dart';
import 'home_fit.dart';
import 'home_reveal.dart';

/// "Zaznamenat jízdu" — row 1 of the Moje zážitky band (DESIGN_V22 §4.2 B).
/// Idle: tap STARTS the manual recording at once (the existing
/// `toggleManualRide`, PM-4 — same permission handling and result messages
/// as Moje zážitky). Recording (SPEC §9.2): title / line by phase
/// (Nahrávám · km · v sedle / Pozastaveno · od HH:MM / Čeká na rozjezd),
/// the 44 px ❚❚ / ▶ disc for every recording (own AND rental) and
/// "Ukončit" (confirm, then the same stop) for a manual ride; a rental
/// ends with the return. Ping only while really riding.
class HomeRecordRowV2 extends ConsumerWidget {
  const HomeRecordRowV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final rec = ref.watch(rideRecorderProvider);
    final manual = rec.recording && rec.manual;
    final auto = rec.recording && !rec.manual;
    final live = rec.recording;
    final ph = RecPhaseV2.of(tr, rec);
    final riding = live && ph.tone == RecToneV2.rec;

    Future<void> stop() async {
      final ok = await trasyConfirmStop(context, paused: rec.isPaused);
      if (ok && context.mounted) await toggleManualRide(context, ref, running: true);
    }

    final title = !live
        ? tr.tr('v2HomeRecTitle')
        : (riding ? (auto ? tr.tr('v2HomeRecAuto') : tr.tr('rideRecording')) : ph.chip);
    final sub = !live
        ? tr.tr('v2HomeRecSub')
        : (rec.gpsLost ? tr.tr('eoRideGpsLost') : (ph.tone == RecToneV2.armed ? ph.title : recBarLineV2(tr, rec, ph)));
    final accent = switch (live ? ph.tone : null) {
      RecToneV2.rec => MgColors.err,
      RecToneV2.warn => MgColors.warn,
      RecToneV2.armed => MgColors.neonLo,
      RecToneV2.paused => MgColors.ink,
      null => MgColors.line,
    };

    Widget icon(double size) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: MgColors.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MgColors.neonA(0.18)),
          ),
          child: Center(
            child: live
                ? RecGlyphV2(tone: ph.tone, size: size * 0.45)
                : MgIcon(MgIcons.recordDot, size: size >= 44 ? 24 : 20, color: MgColors.neon),
          ),
        );

    final titleW = MgWordFit(
      minScale: 0.7,
      child: Text(title, style: MgType.title.copyWith(color: riding ? MgColors.err : MgColors.ink)),
    );
    // Celý popis vždy (bez „…" a bez limitu řádků), slova se nedělí.
    final subW = MgWordFit(
      minScale: 0.85,
      child: Text(sub, style: MgType.tab(MgType.small.copyWith(color: rec.gpsLost && live ? MgColors.warn : MgColors.meta))),
    );
    final chevron = live ? null : const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.lead);

    // Idle = start; během záznamu otevře obrazovku záznamu (stav, GPS,
    // ukončení) — stejná, jakou otevírá lišta v Trasách / Mých zážitcích.
    // Úzký telefon: menší ikona a popis pod ní přes celou šířku řádku,
    // ať se „Fahrtaufzeichnung" ani „місцезнаходження" nikdy nerozdělí.
    // Úzké rozvržení jen když se slovo titulku / popisu nevejde ani zmenšené
    // vedle 44px dlaždice (měřením, SH-24 — dřív pevně < 300 dp).
    bool needsNarrow(BuildContext context, double w) {
      final textW = w - 16 - 44 - 12 - (chevron != null ? 28 : 0);
      bool fits(String text, TextStyle style, double min) => homeWordsFitIn(context, text, style, textW / min);
      return textW <= 0 ||
          !fits(title, MgType.title, 0.7) ||
          !fits(sub, MgType.tab(MgType.small), 0.85);
    }

    // Úzké rozvržení: titulek vedle 36px dlaždice jen když se tam jeho
    // nejdelší slovo vejde aspoň zmenšené (týž styl a minScale jako při
    // kreslení); jinak titulek pod dlaždici přes celou šířku řádku
    // („Enregistrement" na 320 dp se dřív dělilo).
    bool titleBesideTile(BuildContext context, double w) {
      final tw = w - 16 - 36 - 10 - (chevron != null ? 24 : 0);
      return tw > 0 && homeWordsFitIn(context, title, MgType.title, tw / 0.7);
    }

    Widget main(bool narrow, {bool titleBelow = false}) => Semantics(
          button: true,
          label: '$title. $sub',
          excludeSemantics: true,
          child: MgPress(
            scale: 0.98,
            onTap: live ? () => openRideRecorderV2(context) : () => toggleManualRide(context, ref, running: false),
            child: Container(
              color: Colors.transparent,
              padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
              child: narrow
                  ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        icon(36),
                        if (!titleBelow) ...[const SizedBox(width: 10), Expanded(child: titleW)] else const Spacer(),
                        if (chevron != null) ...[const SizedBox(width: 4), chevron],
                      ]),
                      if (titleBelow) ...[const SizedBox(height: 8), titleW],
                      SizedBox(height: titleBelow ? 3 : 6),
                      subW,
                    ])
                  : Row(children: [
                      icon(44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          titleW,
                          const SizedBox(height: 3),
                          subW,
                        ]),
                      ),
                      if (chevron != null) ...[const SizedBox(width: 8), chevron],
                    ]),
            ),
          ),
        );

    return HomeReveal(
      index: 1,
      sessionKey: 'home-exp',
      child: AnimatedContainer(
        duration: MgMotion.of(context, MgMotion.color),
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.only(right: 10),
        constraints: const BoxConstraints(minHeight: 76),
        decoration: BoxDecoration(
          color: live ? MgColors.surface : MgColors.well,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent, width: live ? 1.5 : 1),
          boxShadow: riding ? [BoxShadow(color: MgColors.err.withValues(alpha: 0.1), spreadRadius: 3)] : null,
        ),
        // Úzký telefon: „Ukončit" jen jako 44px ikona (popisek v sémantice),
        // ať má stav záznamu místo a slova se nedělí.
        child: LayoutBuilder(builder: (context, c) {
          // Velké písmo = „užší" řádek: popis pod ikonou přes celou šířku.
          final ts = MediaQuery.textScalerOf(context).scale(1);
          final iconOnly = c.maxWidth < 360 * ts;
          return Row(children: [
            Expanded(
              child: LayoutBuilder(builder: (context, m) {
                final narrow = needsNarrow(context, m.maxWidth);
                return main(narrow, titleBelow: narrow && !titleBesideTile(context, m.maxWidth));
              }),
            ),
            if (live) RecPauseDiscV2(paused: rec.isManualPaused, dark: false, onTap: () => rideTogglePauseV2(context, ref)),
            if (manual) ...[
              const SizedBox(width: 6),
              if (iconOnly)
                RecStopButtonV2(onTap: stop, iconOnly: true, outlined: true)
              else
                Semantics(
                  button: true,
                  label: tr.tr('rideManualStop'),
                  excludeSemantics: true,
                  child: MgPress(
                    onTap: stop,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: MgColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: MgColors.err, width: 1.5),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const MgIcon(MgIcons.stopFilled, size: 16, color: MgColors.err),
                        const SizedBox(width: 6),
                        Text(tr.tr('v2HomeRecStop'), style: MgType.ctaCompact.copyWith(letterSpacing: 0, color: MgColors.err)),
                      ]),
                    ),
                  ),
                ),
            ],
          ]);
        }),
      ),
    );
  }
}
