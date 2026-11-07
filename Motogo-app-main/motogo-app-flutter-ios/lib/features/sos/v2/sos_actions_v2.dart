import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_animated_size.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_choice_card.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import 'sos_header_v2.dart';
import 'sos_widgets_v2.dart';

/// SOS action pieces (SOS board): never rank-coloured — dark ink on light,
/// red for SOS, brand neon only inside the night dock.

/// A button while its existing request runs: spinner + "Odesílám na
/// centrálu…" in the same 52 px slot (no layout jump, never looks frozen).
class SosBusyButtonV2 extends StatelessWidget {
  final bool red;
  final String? label;
  const SosBusyButtonV2({super.key, this.red = false, this.label});

  @override
  Widget build(BuildContext context) {
    final fg = red ? MgColors.onDark : MgColors.neon;
    return Semantics(
      liveRegion: true,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(color: red ? MgColors.sos : MgColors.ink, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg)),
          const SizedBox(width: 10),
          Flexible(
            child: Text(label ?? t(context).tr('v2UxAsmSending'),
                maxLines: 2, textAlign: TextAlign.center, style: MgType.button.copyWith(color: fg)),
          ),
        ]),
      ),
    );
  }
}

/// Brand neon CTA for the night SOS dock (board `.sos-cta`): neon gradient,
/// dark label; [busy] shows a spinner inside.
class SosNeonButtonV2 extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool busy;
  final String? icon;
  const SosNeonButtonV2({super.key, required this.label, required this.onTap, this.busy = false, this.icon});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null && !busy,
      label: label,
      excludeSemantics: true,
      child: MgPress(
        onTap: busy ? null : onTap,
        child: Opacity(
          opacity: onTap == null ? 0.5 : 1,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: MgGradients.neon,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(color: MgColors.neonA(0.4), blurRadius: 22, offset: const Offset(0, 8), spreadRadius: -10)],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (busy)
                const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: MgColors.onNeon))
              else ...[
                if (icon != null) ...[MgIcon(icon!, size: 20, color: MgColors.onNeon), const SizedBox(width: 8)],
                Flexible(
                  child: MgWordFit(
                    minScale: 0.75,
                    alignment: Alignment.center,
                    child: Text(label.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: MgType.button.copyWith(fontSize: 15, letterSpacing: 0.4, color: MgColors.onNeon)),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Two choice cards (fault / secured) side by side, stacked when narrow.
/// Before a choice a hint says it unlocks the next step.
class SosChoicePairV2 extends StatelessWidget {
  final String eyebrow;
  final bool? value;
  final ValueChanged<bool> onChanged;
  final (bool v, String icon, String title, String? sub) a;
  final (bool v, String icon, String title, String? sub) b;
  final String? hint;
  const SosChoicePairV2({
    super.key,
    required this.eyebrow,
    required this.value,
    required this.onChanged,
    required this.a,
    required this.b,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    Widget card((bool, String, String, String?) c) => MgChoiceCard(
          icon: c.$2,
          title: c.$3,
          sub: c.$4,
          selected: value == c.$1,
          onTap: () => onChanged(c.$1),
        );
    return Semantics(
      container: true,
      label: eyebrow,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SosEyebrowV2(eyebrow),
        LayoutBuilder(
          builder: (context, c) => c.maxWidth < 440
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [card(a), const SizedBox(height: 10), card(b)])
              : IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: card(a)),
                    const SizedBox(width: 10),
                    Expanded(child: card(b)),
                  ]),
                ),
        ),
        MgAnimatedSize(
          duration: MgMotion.of(context, MgMotion.sticky),
          curve: MgMotion.emphasized,
          alignment: Alignment.topCenter,
          child: value != null || hint == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const MgIcon(MgIcons.info, size: 18, color: MgColors.meta),
                    const SizedBox(width: 8),
                    Expanded(child: Text(hint!, style: MgType.small.copyWith(color: MgColors.meta))),
                  ]),
                ),
        ),
      ]),
    );
  }
}

/// "NÁHRADNÍ MOTORKA – ZDARMA" (ink) + caption, and the tow row card.
/// [pending] = which of the two runs ('repl' / 'tow'), the other dims.
class SosReplaceTowV2 extends StatelessWidget {
  final String? pending;
  final String caption;
  final VoidCallback onReplacement;
  final VoidCallback onTow;
  const SosReplaceTowV2({
    super.key,
    required this.pending,
    required this.caption,
    required this.onReplacement,
    required this.onTow,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (pending == 'repl')
        const SosBusyButtonV2()
      else
        Opacity(
          opacity: pending == null ? 1 : 0.5,
          child: MgBtnInk(
            label: tr.tr('replacementFree').toUpperCase(),
            icon: MgIcons.bike,
            onTap: pending == null ? onReplacement : null,
          ),
        ),
      const SizedBox(height: 6),
      Text(caption, textAlign: TextAlign.center, style: MgType.small.copyWith(color: MgColors.meta)),
      const SizedBox(height: 12),
      SosRowV2(
        icon: MgIcons.truck,
        tint: SosTint.neutral,
        title: tr.tr('endRideTow'),
        sub: tr.tr('endRideTowDesc'),
        busy: pending == 'tow',
        busyLabel: tr.tr('v2UxAsmSending'),
        dim: pending == 'repl',
        onTap: onTow,
      ),
    ]);
  }
}

/// "SDÍLET POLOHU ASISTENTŮM" card with a ghost button (no neon on white).
class SosShareCardV2 extends StatelessWidget {
  final VoidCallback onShare;
  const SosShareCardV2({super.key, required this.onShare});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return SosCardV2(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SosEyebrowV2(tr.tr('shareLocationAssistants')),
        MgBtnGhostLight(label: tr.tr('shareGps'), icon: MgIcons.pin, onTap: onShare),
      ]),
    );
  }
}

/// Splits a numbered multi-line text ("1. …\n2. …") into step lines.
List<String> sosSteps(String text) => [
      for (final l in text.split(RegExp(r'\\n|\n')))
        if (l.trim().isNotEmpty) l.trim().replaceFirst(RegExp(r'^\d+\.\s*'), ''),
    ];
