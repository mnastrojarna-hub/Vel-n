import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_shadows.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_emoji_map.dart';
import '../../../../core/v2/widgets/mg_word_fit.dart';

/// Navigation HUD (board TrasaDetail "Navigace · jízda"): white card r20 +
/// line + shadow, progress 5 px `#37CF63` on well, speed 40/900 tabular +
/// "km/h", 2 × 2 stats (flag / clock / alarm / mountain) 17/900 + label
/// 11.5/700 meta; arrived = flag + "Jsi v cíli" 20/900. Values are the old
/// HUD's (ETA from routing, arrival clock, altitude). No motion.
class NavHudV2 extends StatelessWidget {
  final bool arrived;
  final double fraction;
  final double speedKmh;
  final String remaining;
  final String eta;
  final String arrival;
  final String altitude;
  const NavHudV2({
    super.key,
    required this.arrived,
    required this.fraction,
    required this.speedKmh,
    required this.remaining,
    required this.eta,
    required this.arrival,
    required this.altitude,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    Widget stat(String icon, String v, String label) => Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              MgIcon(icon, size: 16, color: MgColors.link),
              const SizedBox(width: 5),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(v, maxLines: 1, style: MgType.tab(MgType.section.copyWith(fontWeight: FontWeight.w900, color: MgColors.ink))),
                ),
              ),
            ]),
            const SizedBox(height: 2),
            MgWordFit(alignment: Alignment.center, child: Text(label, textAlign: TextAlign.center, style: MgType.meta.copyWith(color: MgColors.meta))),
          ]),
        );
    return Container(
      margin: EdgeInsets.fromLTRB(12, 0, 12, MediaQuery.paddingOf(context).bottom + 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: MgColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MgColors.line),
        boxShadow: MgShadows.card,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 5,
            backgroundColor: MgColors.well,
            valueColor: const AlwaysStoppedAnimation(MgColors.neonLo),
          ),
        ),
        const SizedBox(height: 12),
        if (arrived)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const MgIcon(MgIcons.flag, size: 24, color: MgColors.link),
                const SizedBox(width: 10),
                Flexible(
                  child: MgWordFit(
                    child: Text(mgNavNoEmoji(tr.tr('routeNavArrived')),
                        style: MgType.h3.copyWith(fontWeight: FontWeight.w900, color: MgColors.link)),
                  ),
                ),
              ]),
            ),
          )
        else
          Row(children: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${speedKmh.round()}',
                    style: MgType.tab(MgType.display.copyWith(fontSize: 40, color: MgColors.ink))),
                Text('km/h', style: MgType.meta.copyWith(color: MgColors.meta)),
              ]),
            ),
            Container(width: 1, height: 56, color: MgColors.line),
            Expanded(
              child: Column(children: [
                Row(children: [
                  stat(MgIcons.flag, remaining, tr.tr('routeNavRemaining')),
                  stat(MgIcons.clock, eta, tr.tr('routeNavEta')),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  stat(MgIcons.bell, arrival, tr.tr('routeNavArrival')),
                  stat(MgIcons.up, altitude, tr.tr('routeNavAltitude')),
                ]),
              ]),
            ),
          ]),
      ]),
    );
  }
}

/// Removes the trailing emoji of an old key ("Jsi v cíli 🏁").
String mgNavNoEmoji(String s) => mgStripEmoji(s).trim();

/// "Příští: Klášter Rajhrad · 3,2 km  3/5" — white pill, pin, 13/800,
/// counter in a well pill; tap = the stops sheet (old onTap).
class NavNextStopPillV2 extends StatelessWidget {
  final String text;
  final String? progress;
  final VoidCallback? onTap;
  const NavNextStopPillV2({super.key, required this.text, this.progress, this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        label: progress == null ? text : '$text, $progress',
        excludeSemantics: true,
        child: MgPress(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            decoration: BoxDecoration(
              color: MgColors.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: MgColors.line),
              boxShadow: MgShadows.icon,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const MgIcon(MgIcons.pin, size: 16, color: MgColors.link),
              const SizedBox(width: 6),
              Flexible(
                child: Text(text,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: MgType.tab(MgType.small.copyWith(fontSize: 13, fontWeight: FontWeight.w800, color: MgColors.ink))),
              ),
              if (progress != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: MgColors.tintOk, borderRadius: BorderRadius.circular(999)),
                  child: Text(progress!, style: MgType.tab(MgType.meta.copyWith(fontWeight: FontWeight.w800, color: MgColors.onTintOk))),
                ),
              ],
            ]),
          ),
        ),
      );
}

/// Round map control of the navigation (white 44 + line + shadow): zoom
/// +/−, compass (red needle, rotated) and recenter (ink disc with a neon
/// glyph while following, else white) — the old callbacks.
class NavMapButtonV2 extends StatelessWidget {
  final String icon;
  final VoidCallback onTap;
  final String label;
  final bool ink;
  final double rotation;
  final Color? iconColor;

  /// Drawn "−" (the icon set has no minus glyph).
  final bool minus;
  const NavMapButtonV2({
    super.key,
    required this.icon,
    required this.onTap,
    required this.label,
    this.ink = false,
    this.rotation = 0,
    this.iconColor,
    this.minus = false,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: MgPress(
          scale: 0.92,
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: ink ? MgColors.ink : MgColors.surface,
              shape: BoxShape.circle,
              border: ink ? null : Border.all(color: MgColors.line),
              boxShadow: MgShadows.icon,
            ),
            alignment: Alignment.center,
            child: minus
                ? Container(width: 14, height: 2, decoration: BoxDecoration(color: MgColors.ink, borderRadius: BorderRadius.circular(1)))
                : Transform.rotate(
                    angle: rotation,
                    child: MgIcon(icon, size: 22, color: iconColor ?? (ink ? MgColors.neon : MgColors.ink)),
                  ),
          ),
        ),
      );
}

/// Light icon disc used inside the nav cards (★ rate, ☰ stops, ✕ close).
Widget navDiscV2(String icon, String label, VoidCallback? onTap, {Color? color, bool close = false}) => close
    ? MgIconButton(icon: icon, onTap: onTap, semanticLabel: label, style: MgIconButtonStyle.light)
    : Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: MgPress(
          scale: 0.92,
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: MgColors.well, borderRadius: BorderRadius.circular(12), border: Border.all(color: MgColors.line)),
            alignment: Alignment.center,
            child: MgIcon(icon, size: 20, color: color ?? MgColors.ink),
          ),
        ),
      );
