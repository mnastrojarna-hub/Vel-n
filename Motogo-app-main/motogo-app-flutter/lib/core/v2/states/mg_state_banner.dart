import 'package:flutter/material.dart';

import '../icons/mg_icon.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_space.dart';
import '../tokens/mg_type.dart';
import 'mg_tone.dart';
import '../widgets/mg_word_fit.dart';

/// T3 banner inside a screen (form blocks, calendar, docs, codes, stale
/// data): white or tone-tinted card r16, 32 px disc + icon 20, title 14/800,
/// text 12.5/600, inline actions. Never colour-only (icon + text).
class MgStateBanner extends StatelessWidget {
  final MgTone tone;
  final String title;
  final String? text;
  final List<Widget> actions;
  final String? icon;

  /// White card instead of the tone tint.
  final bool plain;
  final bool dark;

  const MgStateBanner({
    super.key,
    required this.tone,
    required this.title,
    this.text,
    this.actions = const [],
    this.icon,
    this.plain = false,
    this.dark = false,
  });

  (Color, Color) _bg() {
    if (dark) {
      return switch (tone) {
        MgTone.err => (MgColors.errDarkBg, MgColors.errDark),
        MgTone.warn || MgTone.pending => (MgColors.warnDarkBg, MgColors.warnDark),
        MgTone.ok => (MgColors.neonA(0.10), MgColors.neonA(0.35)),
        MgTone.sos => (MgColors.sos, MgColors.sos),
        MgTone.info => (MgColors.white(0.06), MgColors.white(0.12)),
      };
    }
    if (plain) return (MgColors.surface, MgColors.line);
    return switch (tone) {
      MgTone.err => (MgColors.errBg, MgColors.errBorder),
      MgTone.warn || MgTone.pending => (MgColors.warnBg, MgColors.warnBorder),
      MgTone.ok => (MgColors.tintOk, MgColors.tintOkBorder),
      MgTone.sos => (MgColors.sos, MgColors.sos),
      MgTone.info => (MgColors.well, MgColors.line),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (bg, border) = _bg();
    final s = mgToneStyle(tone, dark: dark);
    final onSos = tone == MgTone.sos;
    final titleColor = onSos || dark ? MgColors.onDark : MgColors.ink;
    final textColor = onSos ? MgColors.onDark : (dark ? MgColors.onDarkBody : MgColors.body2);
    return Semantics(
      container: true,
      liveRegion: tone == MgTone.err || tone == MgTone.warn,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(MgRadius.card),
          border: Border.all(color: border),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: onSos ? MgColors.white(0.18) : (plain ? s.disc : MgColors.white(dark ? 0.08 : 0.7)),
              shape: BoxShape.circle,
            ),
            child: Center(child: MgIcon(icon ?? s.iconName, size: 20, color: onSos ? MgColors.onDark : s.icon)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              MgWordFit(
                minScale: 0.8,
                child: Text(title, style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: titleColor, height: 1.3)),
              ),
              if (text != null) ...[
                const SizedBox(height: 2),
                MgWordFit(minScale: 0.85, child: Text(text!, style: MgType.small.copyWith(color: textColor))),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: MgSpace.s8),
                Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
