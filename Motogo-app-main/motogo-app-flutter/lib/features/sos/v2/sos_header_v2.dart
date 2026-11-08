import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/widgets/error_feedback.dart' show callMotoGo, kMotoGoPhoneLabel;
import '../../../core/v2/chrome/mg_dock.dart';
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/chrome/mg_status_bar.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/rank/mg_logo_ring.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';

/// Meaning of an SOS header / row tile (never rank).
enum SosTint { red, amber, ok, green, neutral }

(Color, Color) sosTintColors(SosTint t, {bool solid = false}) => switch (t) {
      SosTint.red => solid ? (MgColors.sos, MgColors.onDark) : (MgColors.errBg, MgColors.err),
      SosTint.amber => solid ? (const Color(0xFFFFC857), MgColors.onNeon) : (MgColors.warnBg, MgColors.warn),
      SosTint.ok => solid ? (MgColors.neon, MgColors.onNeon) : (MgColors.tintOk, MgColors.link),
      SosTint.green => solid ? (MgColors.neonLo, MgColors.onNeon) : (MgColors.tintOk, MgColors.link),
      SosTint.neutral => solid ? (MgColors.white(0.14), MgColors.onDark) : (MgColors.well, MgColors.ink),
    };

/// Static red "SOS" pill of the SOS header (a marker, not a button).
class SosPillMark extends StatelessWidget {
  const SosPillMark({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: MgColors.sos,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: MgColors.white(0.18)),
          ),
          child: Text('SOS',
              style: MgType.micro.copyWith(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.8, color: MgColors.onDark)),
        ),
      );
}

/// Dark compact SOS header (SOS board): ‹, red SOS pill, the customer's
/// logo ring (the ONLY rank on SOS screens), then a tinted tile + eyebrow
/// (red dot) + 22/800 title + sub. Plain dark — no rank aura. [center] =
/// a done hero (tone disc + centred texts) instead of the tile row.
class SosHeaderV2 extends StatelessWidget {
  final VoidCallback onBack;
  final String? icon;
  final SosTint tint;
  final String? eyebrow;
  final String title;
  final String? sub;
  final Widget? center;
  const SosHeaderV2({
    super.key,
    required this.onBack,
    this.icon,
    this.tint = SosTint.red,
    this.eyebrow,
    required this.title,
    this.sub,
    this.center,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final (bg, fg) = sosTintColors(tint, solid: true);
    final texts = Column(
      crossAxisAlignment: center != null ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        if (eyebrow != null)
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (center == null) ...[
              Container(width: 7, height: 7, decoration: const BoxDecoration(color: MgColors.sosDot, shape: BoxShape.circle)),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(eyebrow!.toUpperCase(),
                  maxLines: 2,
                  textAlign: center != null ? TextAlign.center : TextAlign.start,
                  style: MgType.meta.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: center != null ? MgColors.neon : MgColors.onDarkMeta)),
            ),
          ]),
        if (eyebrow != null) const SizedBox(height: 4),
        Semantics(
          header: true,
          child: MgWordFit(
            minScale: 0.7,
            alignment: center != null ? Alignment.center : AlignmentDirectional.centerStart,
            child: Text(title,
                textAlign: center != null ? TextAlign.center : TextAlign.start,
                style: MgType.h2.copyWith(color: MgColors.onDark)),
          ),
        ),
        if (sub != null) ...[
          const SizedBox(height: 4),
          Text(sub!,
              textAlign: center != null ? TextAlign.center : TextAlign.start,
              style: MgType.body.copyWith(color: MgColors.onDarkLead)),
        ],
      ],
    );
    return MgStatusBar(
      dark: true,
      extendAbove: MgStatusBar.bounce,
      child: Container(
        decoration: const BoxDecoration(
          gradient: MgGradients.dark,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(16, top + 8, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            MgV2Back(onTap: onBack, style: MgBackStyle.dark),
            const SizedBox(width: 12),
            const SosPillMark(),
            const Spacer(),
            const MgLogoRing(size: 52),
          ]),
          const SizedBox(height: 16),
          if (center != null) ...[
            Center(child: center!),
            const SizedBox(height: 14),
            texts,
          ] else
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (icon != null) ...[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
                  child: Center(child: MgIcon(icon!, size: 24, color: fg)),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(child: texts),
            ]),
        ]),
      ),
    );
  }
}

/// Nonstop-line dock (SOS board "Spodní lišta", V22 §2.4): replaces the nav
/// on every SOS screen — the whole call pill dials the existing nonstop
/// line (`callMotoGo`); the AI agent stays the SOS start's own row, as on
/// the old screens (no AI disc on every SOS page). [cta] (e.g.
/// the replacement confirm) and [contextLine] sit above the call row.
class SosDockV2 extends StatelessWidget {
  final Widget? cta;
  final Widget? contextLine;
  final String? callEyebrow;
  const SosDockV2({super.key, this.cta, this.contextLine, this.callEyebrow});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final eb = callEyebrow ?? tr.tr('nonstopLine');
    return MgDock(
      contextLine: contextLine,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (cta != null) ...[cta!, const SizedBox(height: 10)],
        Row(children: [
          Expanded(
            child: Semantics(
              button: true,
              label: '$eb, $kMotoGoPhoneLabel',
              excludeSemantics: true,
              child: MgPress(
                onTap: callMotoGo,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
                  decoration: BoxDecoration(
                    color: MgColors.white(0.06),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: MgColors.neonA(0.32)),
                  ),
                  child: Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(color: MgColors.neon, shape: BoxShape.circle),
                      child: const Center(child: MgIcon(MgIcons.phone, size: 20, color: MgColors.onNeon)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        MgWordFit(
                          minScale: 0.7,
                          child: Text(eb, maxLines: 2, style: MgType.meta.copyWith(color: MgColors.onDarkSecondary)),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(kMotoGoPhoneLabel,
                              style: MgType.tab(MgType.title.copyWith(letterSpacing: 0.3, color: MgColors.onDark))),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// Canvas page of an SOS screen: header, sections 16 px apart, the
/// nonstop dock and a pinned ‹ (same back) once the header scrolls away.
class SosPageV2 extends StatelessWidget {
  final Widget header;
  final List<Widget> sections;
  final VoidCallback onBack;
  final Widget? dock;
  const SosPageV2({super.key, required this.header, required this.sections, required this.onBack, this.dock});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MgColors.canvas,
      child: MgPage(
        header: header,
        overlapHero: false,
        overscrollColor: MgColors.night,
        pinnedBack: onBack,
        sectionPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        sections: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            sections[i],
          ],
        ],
        dock: dock ?? const SosDockV2(),
      ),
    );
  }
}
