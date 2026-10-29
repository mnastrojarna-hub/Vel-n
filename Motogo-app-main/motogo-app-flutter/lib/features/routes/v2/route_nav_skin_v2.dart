import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/widgets/mg_nav_controls.dart' show MgBackTap;
import '../ride_recorder.dart';
import 'rides/ride_pause_sheet_v2.dart';
import 'rides/ride_phase_v2.dart';

/// Navigation top-bar controls in the v2 look (no decorative motion on the
/// navigation screen): back = photo-style disc (keeps the ride running —
/// the screen's own callback), end = white disc with a red ✕ (the
/// existing "Ukončit trasu?" dialog).
class NavCircleV2 extends StatelessWidget {
  final bool end;
  final VoidCallback onTap;
  const NavCircleV2({super.key, required this.end, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (!end) return MgV2Back(onTap: onTap, style: MgBackStyle.photo);
    return MgBackTap(
      onTap: onTap,
      close: true,
      label: t(context).tr('routeEndBtn'),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: MgColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: MgColors.line),
          boxShadow: MgShadows.photoControl,
        ),
        child: const Center(child: MgIcon(MgIcons.close, size: 22, color: MgColors.err, stroke: 2.4)),
      ),
    );
  }
}

/// "☑ 2/5" — reached / all stops (opens the existing stops sheet).
class NavStopsChipV2 extends StatelessWidget {
  final String text;
  const NavStopsChipV2(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: MgColors.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: MgShadows.photoControl,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const MgIcon(MgIcons.list, size: 18, color: MgColors.link),
          const SizedBox(width: 6),
          Text(text, style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink))),
        ]),
      );
}

/// "● REC" / "● PŘIPRAVENO" / "❚❚ AUTO-PAUZA" / "❚❚ PAUZA" / "● BEZ GPS"
/// while a ride recording runs (SPEC §9.2, fix:ui-v2:r1): no
/// decorative motion on the navigation screen (static dot); tap (44 px) =
/// the v2 recording sheet (phase, numbers, pause / resume, stop).
class NavRecChipV2 extends ConsumerWidget {
  const NavRecChipV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rec = ref.watch(rideRecorderProvider);
    if (!rec.recording) return const SizedBox.shrink();
    final tr = t(context);
    final ph = RecPhaseV2.of(tr, rec);
    // REC jen když se opravdu nahrává; PŘIPRAVENO / AUTO-PAUZA / PAUZA /
    // BEZ GPS — jezdec pozná, jestli má něco udělat.
    final label = recNavLabelV2(tr, ph);
    final dot = switch (ph.tone) {
      RecToneV2.warn => MgColors.warnDark,
      RecToneV2.rec => MgColors.sosDot,
      RecToneV2.armed => MgColors.neon,
      RecToneV2.paused => null,
    };
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Semantics(
        button: true,
        label: '${ph.chip}. ${tr.tr('v2RpNavA11y')}',
        excludeSemantics: true,
        child: MgPress(
          scale: 0.94,
          onTap: () => showRidePauseSheetV2(context),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Center(
              widthFactor: 1,
              child: Container(
                constraints: const BoxConstraints(minHeight: 32),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: MgColors.nightA(0.85),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: MgColors.white(0.25)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (dot != null)
                    Container(width: 9, height: 9, decoration: BoxDecoration(color: dot, shape: BoxShape.circle))
                  else
                    const MgIcon(MgIcons.pause, size: 12, color: MgColors.onDark, stroke: 2.8),
                  const SizedBox(width: 6),
                  Text(label, style: MgType.meta.copyWith(fontWeight: FontWeight.w900, color: MgColors.onDark, letterSpacing: 0.6)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
