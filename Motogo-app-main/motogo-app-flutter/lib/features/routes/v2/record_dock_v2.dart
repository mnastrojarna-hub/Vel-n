import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_ai_fab.dart';
import '../../../core/v2/chrome/mg_chrome_metrics.dart';
import '../../../core/v2/chrome/mg_dock.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_anim_loops.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_dialog.dart';
import '../ride_actions.dart';
import '../ride_recorder.dart';

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

/// Asks "Ukončit záznam?" (presentation only), then the existing stop
/// (`toggleManualRide(running: true)`, PM-4 — same result messages).
Future<void> trasyConfirmStopRide(BuildContext context, WidgetRef ref) async {
  final tr = t(context);
  final ok = await showMgConfirm(
    context,
    title: tr.tr('v2RtRecStopQ'),
    body: tr.tr('v2RtRecStopBody'),
    safeLabel: tr.tr('v2RtRecContinue'),
    actionLabel: tr.tr('v2RtRecStopSave'),
  );
  if (ok == true && context.mounted) await toggleManualRide(context, ref, running: true);
}

/// The Trasy tab's record dock (DESIGN_V22 §4.2 A): ① live recording bar
/// (red ping dot, mode line, "Ukončit" for a manual ride) → ② Místa
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
        if (rec.manual) trailing = _StopButton(compact: true, onTap: () => trasyConfirmStopRide(context, ref));
      }
    } else if (live) {
      row = Row(children: [
        Expanded(child: _LiveBar(rec: rec, onTap: onOpenRecorder, onStop: () => trasyConfirmStopRide(context, ref))),
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

  Widget _liveLine(AppTranslations tr, RideRecorderState rec) => Row(children: [
        _Dot(gpsLost: rec.gpsLost),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '${tr.tr('rideRecording')} · ${tr.tr(rec.gpsLost ? 'v2RtRecGps' : (rec.manual ? 'v2RtRecManual' : 'v2RtRecAuto'))}',
            maxLines: 2,
            style: MgType.small.copyWith(
                fontWeight: FontWeight.w800, color: rec.gpsLost ? MgColors.warnDark : MgColors.onDarkLead),
          ),
        ),
      ]);

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

class _Dot extends StatelessWidget {
  final bool gpsLost;
  const _Dot({required this.gpsLost});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 18,
        height: 18,
        child: Center(
          child: MgPing(
            size: 10,
            color: gpsLost ? MgColors.warnDark : MgColors.sosDot,
            active: !gpsLost && !MgMotion.reduced(context),
          ),
        ),
      );
}

class _LiveBar extends StatelessWidget {
  final RideRecorderState rec;
  final VoidCallback? onTap;
  final VoidCallback onStop;
  const _LiveBar({required this.rec, required this.onTap, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final mode = tr.tr(rec.gpsLost ? 'v2RtRecGps' : (rec.manual ? 'v2RtRecManual' : 'v2RtRecAuto'));
    final edge = rec.gpsLost ? MgColors.warnDark.withValues(alpha: 0.6) : MgColors.sosDot.withValues(alpha: 0.55);
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      decoration: BoxDecoration(
        color: MgColors.white(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: edge, width: 1.5),
      ),
      child: Row(children: [
        Expanded(
          child: Semantics(
            button: onTap != null,
            liveRegion: true,
            label: '${tr.tr('rideRecording')}, $mode',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(children: [
                  _Dot(gpsLost: rec.gpsLost),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(tr.tr('rideRecording').toUpperCase(),
                          style: MgType.ctaCompact.copyWith(color: MgColors.onDark, letterSpacing: 0.5)),
                      const SizedBox(height: 2),
                      Text(mode,
                          maxLines: 2,
                          style: MgType.small.copyWith(
                              fontWeight: FontWeight.w700,
                              color: rec.gpsLost ? MgColors.warnDark : MgColors.onDarkLead)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
        if (rec.manual) Padding(padding: const EdgeInsets.only(right: 6), child: _StopButton(onTap: onStop)),
      ]),
    );
  }
}

class _StopButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool compact;
  const _StopButton({required this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Semantics(
      button: true,
      label: tr.tr('rideManualStop'),
      excludeSemantics: true,
      child: MgPress(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: compact ? 36 : 44, minWidth: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: MgColors.surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: MgColors.black(0.4), blurRadius: 14, offset: const Offset(0, 6), spreadRadius: -8)],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const MgIcon(MgIcons.stopFilled, size: 14, color: MgColors.err),
            const SizedBox(width: 6),
            Text(tr.tr('v2RtRecStop'), style: MgType.ctaCompact.copyWith(color: MgColors.err, letterSpacing: 0)),
          ]),
        ),
      ),
    );
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
