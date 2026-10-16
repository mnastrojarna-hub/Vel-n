import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_anim_loops.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_dialog.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../routes/ride_actions.dart';
import '../../routes/ride_recorder.dart';
import '../../routes/v2/rides/recorder_screen_v2.dart' show openRideRecorderV2;
import 'home_reveal.dart';

/// "Zaznamenat jízdu" — row 1 of the Moje zážitky band (DESIGN_V22 §4.2 B).
/// Idle: tap STARTS the manual recording at once (the existing
/// `toggleManualRide`, PM-4 — same permission handling and result messages
/// as Moje zážitky). Manual recording: live row + "Ukončit" (confirm, then
/// the same stop). Automatic (rental) recording: live row without stop —
/// it ends with the rental.
class HomeRecordRowV2 extends ConsumerWidget {
  const HomeRecordRowV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final rec = ref.watch(rideRecorderProvider);
    final manual = rec.recording && rec.manual;
    final auto = rec.recording && !rec.manual;
    final live = rec.recording;

    Future<void> stop() async {
      final ok = await showMgConfirm(
        context,
        title: tr.tr('v2HomeRecStopQ'),
        body: tr.tr('v2HomeRecStopBody'),
        safeLabel: tr.tr('v2HomeRecContinue'),
        actionLabel: tr.tr('v2HomeRecStopSave'),
      );
      if (ok == true && context.mounted) await toggleManualRide(context, ref, running: true);
    }

    final title = auto ? tr.tr('v2HomeRecAuto') : (manual ? tr.tr('rideRecording') : tr.tr('v2HomeRecTitle'));
    final sub = rec.gpsLost && live
        ? tr.tr('eoRideGpsLost')
        : (manual ? tr.tr('rideManualRunning') : (auto ? tr.tr('rideRecordHint') : tr.tr('v2HomeRecSub')));

    final icon = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: MgColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MgColors.neonA(0.18)),
      ),
      child: Center(
        child: live
            ? const MgPing(size: 12, color: MgColors.sosDot)
            : const MgIcon(MgIcons.recordDot, size: 24, color: MgColors.neon),
      ),
    );

    // Idle = start; během záznamu otevře obrazovku záznamu (stav, GPS,
    // ukončení) — stejná, jakou otevírá lišta v Trasách / Mých zážitcích.
    final main = Semantics(
      button: true,
      label: '$title. $sub',
      excludeSemantics: true,
      child: MgPress(
        scale: 0.98,
        onTap: live ? () => openRideRecorderV2(context) : () => toggleManualRide(context, ref, running: false),
        child: Container(
          color: Colors.transparent,
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
          child: Row(children: [
            icon,
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                MgWordFit(
                  minScale: 0.75,
                  child: Text(title,
                      style: MgType.title.copyWith(color: live ? MgColors.err : MgColors.ink)),
                ),
                const SizedBox(height: 3),
                // Celý popis (bez „…"): smí na 4 řádky, slova se nedělí.
                MgWordFit(
                  minScale: 0.85,
                  child: Text(sub,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: MgType.small.copyWith(color: rec.gpsLost && live ? MgColors.warn : MgColors.meta)),
                ),
              ]),
            ),
            if (!manual) ...[
              const SizedBox(width: 8),
              const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.lead),
            ],
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
          border: Border.all(color: live ? MgColors.err : MgColors.line, width: live ? 1.5 : 1),
          boxShadow: live ? [BoxShadow(color: MgColors.err.withValues(alpha: 0.1), spreadRadius: 3)] : null,
        ),
        // Úzký telefon: „Ukončit" jen jako 44px ikona (popisek v sémantice),
        // ať má stav záznamu místo a slova se nedělí.
        child: LayoutBuilder(builder: (context, c) {
          final iconOnly = c.maxWidth < 330;
          return Row(children: [
            Expanded(child: main),
            if (manual)
              Semantics(
                button: true,
                label: tr.tr('rideManualStop'),
                excludeSemantics: true,
                child: MgPress(
                  onTap: stop,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                    padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : 14),
                    decoration: BoxDecoration(
                      color: MgColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: MgColors.err, width: 1.5),
                    ),
                    child: iconOnly
                        ? const Center(widthFactor: 1, child: MgIcon(MgIcons.stopFilled, size: 16, color: MgColors.err))
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            const MgIcon(MgIcons.stopFilled, size: 16, color: MgColors.err),
                            const SizedBox(width: 6),
                            Text(tr.tr('v2HomeRecStop'), style: MgType.ctaCompact.copyWith(letterSpacing: 0, color: MgColors.err)),
                          ]),
                  ),
                ),
              ),
          ]);
        }),
      ),
    );
  }
}
