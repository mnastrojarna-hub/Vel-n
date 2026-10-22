import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_ai_fab.dart';
import '../../../core/v2/chrome/mg_chrome_metrics.dart';
import '../../../core/v2/chrome/mg_dock.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../ride_actions.dart';
import '../ride_recorder.dart';
import 'rides/rec_live_bar_v2.dart';
import 'rides/rec_widgets_v2.dart';
import 'rides/ride_pause_actions_v2.dart';
import 'rides/ride_phase_v2.dart';

export 'rides/ride_pause_actions_v2.dart' show trasyConfirmStop, trasyConfirmStopRide;

/// Místa selection carried by the dock (priority ②): the SAME actions as
/// the old selection bar (`_navigate` / `_clearSel`). [pick] = the place
/// picker of the route editor ("Přidat do trasy").
class TrasySelection {
  final int count;
  final VoidCallback onContinue;
  final VoidCallback onClear;
  final bool pick;
  const TrasySelection({required this.count, required this.onContinue, required this.onClear, this.pick = false});
}

/// The Trasy tab's record dock (DESIGN_V22 §4.2 A): ① live recording bar
/// (phase glyph — red ping only while riding, phase + km / "od HH:MM",
/// ❚❚ / ▶ pause disc for every recording, "Ukončit" for a manual ride;
/// `RecLiveBarV2`) → ② Místa
/// selection ("VLASTNÍ VYJÍŽĎKA (n)" + ✕ + ⏺ disc) → ③ idle "ZAZNAMENAT
/// JÍZDU" + docked AI disc (the floating AI button is hidden on Trasy).
/// Start / stop go through `toggleManualRide` (same permission handling
/// and result messages as Moje zážitky). [onOpenRecorder] = tap on the
/// live bar (the recorder screen; null = not tappable).
class TrasyRecordDockV2 extends ConsumerWidget {
  final TrasySelection? selection;
  final VoidCallback? onOpenRecorder;
  final bool showRecord;

  const TrasyRecordDockV2({super.key, this.selection, this.onOpenRecorder, this.showRecord = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final rec = ref.watch(rideRecorderProvider);
    final live = showRecord && rec.recording;
    final sel = selection;
    final inShell = MgChromeScope.maybeOf(context)?.navVisible ?? false;

    Widget row;
    Widget? context0;
    Widget? trailing;
    if (sel != null) {
      row = _selectionRow(context, ref, sel, showRecord && !live);
      if (live) {
        context0 = _liveLine(tr, rec);
        trailing = Row(mainAxisSize: MainAxisSize.min, children: [
          RecPauseDiscV2(paused: rec.isManualPaused, onTap: () => rideTogglePauseV2(context, ref)),
          if (rec.canStop) ...[
            const SizedBox(width: 6),
            RecStopButtonV2(compact: true, onTap: () => trasyConfirmStopRide(context, ref)),
          ],
        ]);
      }
    } else if (live) {
      row = Row(children: [
        Expanded(
          child: RecLiveBarV2(
            rec: rec,
            onOpen: onOpenRecorder,
            onPause: () => rideTogglePauseV2(context, ref),
            onStop: () => trasyConfirmStopRide(context, ref),
          ),
        ),
        const SizedBox(width: 8),
        const MgAiDisc(size: 56),
      ]);
    } else {
      row = Row(children: [
        Expanded(
          child: MgFabAvoid(
            child: MgCta(
              label: tr.tr('v2RtRecShort'),
              loop: true,
              semanticLabel: tr.tr('v2RtRecA11y'),
              onTap: () => toggleManualRide(context, ref, running: false),
            ),
          ),
        ),
        const SizedBox(width: 8),
        const MgAiDisc(size: 56),
      ]);
    }
    return MgDock(
      safeArea: !inShell,
      contextLine: context0,
      trailing: trailing,
      child: AnimatedSwitcher(
        duration: MgMotion.of(context, const Duration(milliseconds: 300)),
        switchInCurve: MgMotion.out,
        transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
        child: KeyedSubtree(
          key: ValueKey(sel != null ? 'sel' : (live ? 'live' : 'idle')),
          child: row,
        ),
      ),
    );
  }

  Widget _liveLine(AppTranslations tr, RideRecorderState rec) {
    final ph = RecPhaseV2.of(tr, rec);
    return Row(children: [
      RecGlyphV2(tone: ph.tone, size: 16),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          '${ph.chip} · ${recBarLineV2(tr, rec, ph)}',
          maxLines: 2,
          style: MgType.tab(MgType.small.copyWith(
              fontWeight: FontWeight.w800, color: ph.tone == RecToneV2.warn ? MgColors.warnDark : MgColors.onDarkLead)),
        ),
      ),
    ]);
  }

  Widget _selectionRow(BuildContext context, WidgetRef ref, TrasySelection sel, bool recordDisc) {
    final tr = t(context);
    final label = tr.trArgs(sel.pick ? 'v2RtSelAdd' : 'v2RtSelTrip', {'n': sel.count});
    return Row(children: [
      if (recordDisc && !sel.pick) ...[
        _RecordDisc(onTap: () => toggleManualRide(context, ref, running: false)),
        const SizedBox(width: 8),
      ],
      _ClearDisc(onTap: sel.onClear),
      const SizedBox(width: 8),
      Expanded(
        child: MgFabAvoid(
          child: MgCta(label: label, arrow: !sel.pick, loop: true, onTap: sel.onContinue),
        ),
      ),
    ]);
  }
}

/// Selection mode: the record action collapsed into a 56 ink disc.
class _RecordDisc extends StatelessWidget {
  final VoidCallback onTap;
  const _RecordDisc({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = t(context).tr('v2RtRecA11y');
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        triggerMode: TooltipTriggerMode.longPress,
        excludeFromSemantics: true,
        child: MgPress(
          scale: 0.92,
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: MgColors.ink,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MgColors.white(0.25)),
            ),
            child: const Center(child: MgIcon(MgIcons.recordDot, size: 24, color: MgColors.neon)),
          ),
        ),
      ),
    );
  }
}

class _ClearDisc extends StatelessWidget {
  final VoidCallback onTap;
  const _ClearDisc({required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: t(context).tr('v2RtSelClear'),
        excludeSemantics: true,
        child: MgPress(
          scale: 0.92,
          onTap: onTap,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: MgColors.white(0.10),
              shape: BoxShape.circle,
              border: Border.all(color: MgColors.white(0.25)),
            ),
            child: const Center(child: MgIcon(MgIcons.close, size: 22, color: MgColors.onDark)),
          ),
        ),
      );
}
