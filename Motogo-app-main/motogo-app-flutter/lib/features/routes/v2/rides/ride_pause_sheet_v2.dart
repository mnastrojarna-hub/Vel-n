import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_cta.dart';
import '../../../../core/v2/widgets/mg_sheet.dart';
import '../../../../core/v2/widgets/mg_surfaces.dart';
import '../../../../core/v2/widgets/mg_word_fit.dart';
import '../../ride_recorder.dart';
import 'rec_widgets_v2.dart';
import 'ride_pause_actions_v2.dart';
import 'ride_phase_v2.dart';

/// Recording controls during navigation (tap on the nav chip, SPEC §9.2):
/// phase + since, live numbers, what is happening, ❚❚ Pozastavit / ▶
/// Pokračovat (every recording), Ukončit (manual ride — confirm first) or,
/// after a guard pause, Pokračovat v cestě / Ukončit a uložit.
Future<void> showRidePauseSheetV2(BuildContext context) => showMgSheet<void>(
      context,
      title: t(context).tr('rideRecordTitle'),
      builder: (_) => const RidePauseSheetBodyV2(),
    );

class RidePauseSheetBodyV2 extends ConsumerWidget {
  const RidePauseSheetBodyV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final rec = ref.watch(rideRecorderProvider);
    if (!rec.recording) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(tr.tr('v2RpSheetEnded'), style: MgType.body.copyWith(color: MgColors.body2)),
      );
    }
    final ph = RecPhaseV2.of(tr, rec);
    Future<void> stop() async {
      final paused = ref.read(rideRecorderProvider).isPaused;
      if (!await trasyConfirmStop(context, paused: paused) || !context.mounted) return;
      final nav = Navigator.of(context);
      await trasyStopNowV2(context, ref);
      if (nav.mounted) nav.maybePop();
    }

    final buttons = <Widget>[
      if (rec.needsDecision) ...[
        MgCta(label: tr.tr('v2RpResumeTripCta'), size: MgCtaSize.sm48, onTap: () => rideTogglePauseV2(context, ref)),
        const SizedBox(height: 8),
        MgBtnGhostLight(label: tr.tr('v2RpEndSave'), icon: MgIcons.stopFilled, onTap: stop),
      ] else ...[
        MgBtnInk(
          label: tr.tr(rec.isManualPaused ? 'v2RpResume' : 'v2RpPause'),
          icon: rec.isManualPaused ? MgIcons.playFilled : MgIcons.pause,
          neonLabel: true,
          onTap: () => rideTogglePauseV2(context, ref),
        ),
        if (rec.canStop) ...[
          const SizedBox(height: 8),
          MgBtnDestructive(label: tr.tr('rideManualStop'), onTap: stop),
        ],
      ],
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Semantics(
        liveRegion: true,
        container: true,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: MgColors.well, shape: BoxShape.circle, border: Border.all(color: MgColors.line)),
            child: Center(child: RecGlyphV2(tone: ph.tone, dark: false, size: 22)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              MgWordFit(minScale: 0.7, child: Text(ph.status, maxLines: 2, style: MgType.title.copyWith(color: MgColors.ink))),
              const SizedBox(height: 2),
              Text(ph.title, style: MgType.small.copyWith(color: MgColors.body2)),
              if (ph.since != null)
                Text(ph.since!, style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink))),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final b in recLiveBitsV2(tr, rec))
          Container(
            constraints: const BoxConstraints(minHeight: 30),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: MgColors.well, borderRadius: BorderRadius.circular(999), border: Border.all(color: MgColors.line)),
            child: Text(b, style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink))),
          ),
      ]),
      const SizedBox(height: 12),
      MgWell(
        padding: const EdgeInsets.all(12),
        child: Text(recHintV2(tr, rec), style: MgType.small.copyWith(color: MgColors.body2)),
      ),
      if (!rec.manual) ...[
        const SizedBox(height: 8),
        Text(tr.tr('v2RpRentalEnds'), style: MgType.small.copyWith(color: MgColors.meta)),
      ],
      const SizedBox(height: 16),
      ...buttons,
    ]);
  }
}
