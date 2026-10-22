import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/widgets/mg_nav_controls.dart' show MgBackTap;
import '../ride_recorder.dart';

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

/// "● REC" while a ride recording runs (display only, static red dot — the
/// navigation is never covered by the record bar).
class NavRecChipV2 extends ConsumerWidget {
  const NavRecChipV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rec = ref.watch(rideRecorderProvider);
    if (!rec.recording) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Semantics(
        label: t(context).tr('rideRecording'),
        excludeSemantics: true,
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: MgColors.nightA(0.85),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: MgColors.white(0.25)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: rec.gpsLost ? MgColors.warnDark : MgColors.sosDot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text('REC', style: MgType.meta.copyWith(fontWeight: FontWeight.w900, color: MgColors.onDark, letterSpacing: 0.6)),
          ]),
        ),
      ),
    );
  }
}
