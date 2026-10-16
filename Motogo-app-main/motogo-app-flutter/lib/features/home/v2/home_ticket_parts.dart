import 'package:flutter/material.dart';

import '../../../core/router.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/chrome/mg_nav_helpers.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/widgets/net_image.dart';

/// Bike photo (cover) or a dark placeholder with the bike glyph — never
/// throws, never shows a broken image.
class HomePhoto extends StatelessWidget {
  final String? url;
  final int thumbWidth;

  /// Bike glyph on the placeholder (off for route covers under a sketch).
  final bool glyph;
  const HomePhoto({super.key, this.url, this.thumbWidth = 800, this.glyph = true});

  @override
  Widget build(BuildContext context) {
    final ph = DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topRight,
          radius: 1.4,
          colors: [MgColors.glow, MgColors.panel, MgColors.night],
          stops: [0, 0.55, 1],
        ),
      ),
      child: glyph ? Center(child: MgIcon(MgIcons.moto, size: 44, color: MgColors.neonA(0.33))) : null,
    );
    final u = url?.trim() ?? '';
    if (u.isEmpty) return SizedBox.expand(child: ph);
    return SizedBox.expand(
      child: MgImage(u, thumbWidth: thumbWidth, fit: BoxFit.cover, placeholder: ph, error: ph),
    );
  }
}

/// Glass pill on a photo (eyebrow / status).
enum TkPillTone { neon, sos, pending, ok, warn, plain }

class TkPill extends StatelessWidget {
  final String text;
  final TkPillTone tone;
  final String? icon;
  const TkPill(this.text, {super.key, this.tone = TkPillTone.neon, this.icon});

  @override
  Widget build(BuildContext context) {
    final (bg, border, fg) = switch (tone) {
      TkPillTone.neon => (MgColors.nightA(0.8), MgColors.neonA(0.42), MgColors.neonText),
      TkPillTone.sos => (MgColors.nightA(0.8), MgColors.errDark.withValues(alpha: 0.6), MgColors.errDark),
      TkPillTone.pending => (MgColors.nightA(0.8), MgColors.warnDark.withValues(alpha: 0.6), MgColors.warnDark),
      TkPillTone.ok => (MgColors.nightA(0.8), MgColors.neonA(0.45), MgColors.neonText),
      TkPillTone.warn => (MgColors.warnBg, MgColors.warnBorder, MgColors.warn),
      TkPillTone.plain => (MgColors.nightA(0.8), MgColors.white(0.16), MgColors.onDark),
    };
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[MgIcon(icon!, size: 12, color: fg, stroke: 3), const SizedBox(width: 6)],
        Flexible(
          child: Text(text.toUpperCase(),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
              style: MgType.eyebrow.copyWith(height: 1, color: fg)),
        ),
      ]),
    );
  }
}

/// Node of the "Tým pro tebe" checklist.
enum TkNode { done, current, warn, info }

class TkCheckRow extends StatelessWidget {
  final TkNode node;
  final String text;
  final String? sub;
  final bool last;
  final Widget? trailing;
  const TkCheckRow({super.key, required this.node, required this.text, this.sub, this.last = false, this.trailing});

  @override
  Widget build(BuildContext context) {
    final Widget disc = switch (node) {
      TkNode.done => MgPop(
          playOnMount: true,
          child: Container(
            width: 18,
            height: 18,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [MgColors.neonHi, MgColors.neonLo]),
            ),
            child: const Center(child: MgIcon(MgIcons.check, size: 12, color: MgColors.onNeon, stroke: 3.4)),
          ),
        ),
      TkNode.current => Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: MgColors.panel,
            border: Border.all(color: MgColors.neon, width: 2),
          ),
          child: Center(
            child: Container(
                width: 8, height: 8, decoration: const BoxDecoration(color: MgColors.neon, shape: BoxShape.circle)),
          ),
        ),
      TkNode.warn => Container(
          width: 18,
          height: 18,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: MgColors.warnBorder),
          child: Center(
            child: Text('!', style: MgType.micro.copyWith(fontWeight: FontWeight.w900, height: 1, color: MgColors.onNeon)),
          ),
        ),
      TkNode.info => Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: MgColors.panel,
            border: Border.all(color: MgColors.neonA(0.55), width: 1.5),
          ),
        ),
    };
    final color = node == TkNode.warn ? MgColors.warnDark : MgColors.onDarkBody;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 18,
          child: Column(children: [
            const SizedBox(height: 2),
            disc,
            if (!last)
              Expanded(
                child: Container(
                  width: 2,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: node == TkNode.done
                        ? const LinearGradient(
                            begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [MgColors.neonLo, MgColors.neon])
                        : null,
                    color: node == TkNode.done ? null : MgColors.borderDark,
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 2, bottom: last ? 0 : 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(text, style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: color)),
              if (sub != null) ...[
                const SizedBox(height: 2),
                Text(sub!, style: MgType.meta.copyWith(color: MgColors.onDarkSecondary)),
              ],
            ]),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ]),
    );
  }
}

/// "Platbu ověřujeme" block (S2 while the payment is verified): pending
/// tone, no pay action — the existing status action is passed in.
class TkPendingBlock extends StatelessWidget {
  final String title;
  final String text;
  final Widget? action;
  const TkPendingBlock({super.key, required this.title, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MgColors.warnDarkBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MgColors.warnDark.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const MgToneDisc(tone: MgTone.pending, size: 48, dark: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: MgType.title.copyWith(color: MgColors.warnDark)),
              const SizedBox(height: 4),
              Text(text, style: MgType.small.copyWith(color: MgColors.onDarkBody)),
            ]),
          ),
        ]),
        if (action != null) ...[const SizedBox(height: 12), action!],
      ]),
    );
  }
}

/// Red SOS circle 48 next to the ticket CTA (S8 / S9, only during a rental).
class TkSosCircle extends StatelessWidget {
  final String label;
  const TkSosCircle({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return MgFabAvoid(
      kind: MgAvoidKind.sos,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: MgPress(
          onTap: () => mgPushOrGo(context, Routes.sos),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: MgColors.sos,
              border: Border.all(color: MgColors.white(0.2)),
              boxShadow: [BoxShadow(color: MgColors.sos.withValues(alpha: 0.8), blurRadius: 22, offset: const Offset(0, 8), spreadRadius: -8)],
            ),
            child: Center(
              child: Text('SOS',
                  style: MgType.ctaCompact.copyWith(letterSpacing: 0.5, color: MgColors.onDark)),
            ),
          ),
        ),
      ),
    );
  }
}
