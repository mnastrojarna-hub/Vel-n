import 'package:flutter/material.dart';

import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_surfaces.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import 'sos_header_v2.dart';

/// Light pieces of the SOS board (cards, option rows, step guide, notes) —
/// meaning colours only, never rank; no emoji.

/// White SOS card r16 (1 px line).
class SosCardV2 extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const SosCardV2({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: MgColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MgColors.line),
          boxShadow: MgShadows.card,
        ),
        child: child,
      );
}

/// Green caps eyebrow on light (ZAVINĚNÍ, SDÍLET POLOHU ASISTENTŮM …).
class SosEyebrowV2 extends StatelessWidget {
  final String text;
  const SosEyebrowV2(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text.toUpperCase(),
            style: MgType.meta.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.6, color: MgColors.link)),
      );
}

/// Option row: tinted 44 tile + 15/800 title + 12.5/600 sub + chevron.
/// [busy] = the existing request of this row runs (spinner + [busyLabel]
/// instead of the sub, never a frozen-looking row); [dim] = another row
/// runs.
class SosRowV2 extends StatelessWidget {
  final String icon;
  final SosTint tint;
  final String title;
  final String? sub;
  final VoidCallback? onTap;
  final bool busy;
  final String? busyLabel;
  final bool dim;
  const SosRowV2({
    super.key,
    required this.icon,
    required this.tint,
    required this.title,
    this.sub,
    this.onTap,
    this.busy = false,
    this.busyLabel,
    this.dim = false,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = sosTintColors(tint);
    final s = busy ? busyLabel : sub;
    return Opacity(
      opacity: dim ? 0.5 : 1,
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: s == null ? title : '$title, $s',
        excludeSemantics: true,
        child: MgPress(
          onTap: busy || dim ? null : onTap,
          child: SosCardV2(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
                child: Center(child: MgIcon(icon, size: 22, color: fg)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  MgWordFit(minScale: 0.7, child: Text(title, style: MgType.title.copyWith(color: MgColors.ink))),
                  if (s != null) ...[
                    const SizedBox(height: 2),
                    Text(s, style: MgType.small.copyWith(color: busy ? MgColors.link : MgColors.meta)),
                  ],
                ]),
              ),
              const SizedBox(width: 8),
              busy
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: MgColors.link))
                  : const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.meta),
            ]),
          ),
        ),
      ),
    );
  }
}

/// One step of the dark "postup" card; [action] sits under its text.
class SosStepV2 {
  final String title;
  final String? text;
  final String? icon;
  final Widget? action;
  const SosStepV2(this.title, {this.text, this.icon, this.action});
}

/// The board's dark step guide (MgDarkHero without aura): optional title
/// row, numbered 34 px neon discs joined by a line, 14/600 texts.
class SosGuideV2 extends StatelessWidget {
  final String? title;
  final List<SosStepV2> steps;
  const SosGuideV2({super.key, this.title, required this.steps});

  @override
  Widget build(BuildContext context) {
    return MgDarkHero(
      rankAura: false,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null) ...[
          Row(children: [
            const MgIcon(MgIcons.doc, size: 20, color: MgColors.neon),
            const SizedBox(width: 8),
            Expanded(child: Text(title!, style: MgType.title.copyWith(fontSize: 16, color: MgColors.onDark))),
          ]),
          const SizedBox(height: 12),
        ],
        for (var i = 0; i < steps.length; i++) _row(i, steps[i], i == steps.length - 1),
      ]),
    );
  }

  Widget _row(int i, SosStepV2 s, bool last) {
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 34,
          child: Column(children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: MgColors.neon, shape: BoxShape.circle),
              child: Text('${i + 1}', style: MgType.tab(MgType.title.copyWith(fontWeight: FontWeight.w900, color: MgColors.onNeon))),
            ),
            if (!last) Expanded(child: Container(width: 2, color: MgColors.neonA(0.35))),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (s.icon != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: MgIcon(s.icon!, size: 18, color: MgColors.neon),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: MgWordFit(
                    minScale: 0.7,
                    child: Text(s.title,
                        style: (s.text != null ? MgType.title : MgType.body).copyWith(color: MgColors.onDarkBody)),
                  ),
                ),
              ]),
              if (s.text != null) ...[
                const SizedBox(height: 4),
                Text(s.text!, style: MgType.body.copyWith(color: MgColors.onDarkLead)),
              ],
              if (s.action != null) ...[const SizedBox(height: 10), s.action!],
            ]),
          ),
        ),
      ]),
    );
  }
}

/// T3 note box: warn (amber) or ok (tint) with ✓ / ✕ lines.
class SosNoteV2 extends StatelessWidget {
  final String title;
  final String icon;
  final bool ok;
  final List<(bool yes, String text)> lines;
  const SosNoteV2({super.key, required this.title, required this.icon, this.ok = false, this.lines = const []});

  @override
  Widget build(BuildContext context) {
    final fg = ok ? MgColors.onTintOk : MgColors.warn;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ok ? MgColors.tintOk : MgColors.warnBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ok ? MgColors.tintOkBorder : MgColors.warnBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          MgIcon(icon, size: 20, color: fg),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: MgType.title.copyWith(fontSize: 14, color: fg))),
        ]),
        for (final l in lines) ...[
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            MgIcon(l.$1 ? MgIcons.check : MgIcons.close, size: 18, color: l.$1 ? MgColors.link : MgColors.err),
            const SizedBox(width: 10),
            Expanded(child: Text(l.$2, style: MgType.small.copyWith(color: MgColors.ink))),
          ]),
        ],
      ]),
    );
  }
}
