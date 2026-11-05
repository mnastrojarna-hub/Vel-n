import 'package:flutter/material.dart';

import '../chrome/mg_dock.dart';
import '../motion/mg_anim.dart';
import '../rank/rank_hero.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_shadows.dart';
import '../tokens/mg_space.dart';
import '../tokens/mg_type.dart';
import '../widgets/mg_back_v2.dart';
import '../widgets/mg_buttons.dart';
import '../widgets/mg_cta.dart';
import 'mg_state_parts.dart';
import 'mg_support_row.dart';
import 'mg_tech_details.dart';
import 'mg_tone.dart';

export 'mg_state_parts.dart';
export 'mg_tone.dart' show MgTone;

/// T1 result screen (DESIGN_V22 §5.2): end of a flow — success, pending,
/// expired, crash fallback, unknown link. Success / pending = dark rank
/// hero (tone disc 88, title 22/800 white) + white summary card overlapping
/// −24 + dark dock with the rank CTA; warn / error / info = canvas, tone
/// disc 72, ink title, white dock with `btnInk` + `btnText`. Texts and
/// actions are the caller's EXISTING ones; nothing here decides anything.
class MgStateScreen extends StatelessWidget {
  final MgTone tone;
  final String title;
  final String? why;
  final Widget? summary;
  final String? stepsTitle;
  final List<String> steps;
  final String? tech;
  final bool support;
  final VoidCallback? onWrite;
  final MgStateAction? primary;
  final MgStateAction? secondary;

  /// ✕ / ‹ in the top-left corner (same callback as the old screen's).
  final VoidCallback? onClose;
  final bool closeIsBack;
  final String? icon;
  final List<Widget> children;

  /// The primary rank CTA loops (success / pending only).
  final bool loop;

  const MgStateScreen({
    super.key,
    required this.tone,
    required this.title,
    this.why,
    this.summary,
    this.stepsTitle,
    this.steps = const [],
    this.tech,
    this.support = true,
    this.onWrite,
    this.primary,
    this.secondary,
    this.onClose,
    this.closeIsBack = false,
    this.icon,
    this.children = const [],
    this.loop = true,
  });

  bool get _darkHero => tone == MgTone.ok || tone == MgTone.pending;

  @override
  Widget build(BuildContext context) {
    final dark = _darkHero;
    final head = dark ? _heroHeader(context) : _lightHeader(context);
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      head,
      if (summary != null)
        Transform.translate(
          offset: Offset(0, dark ? -24 : 0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: MgSpace.gutter),
            child: MgEnter(
              child: Container(
                padding: const EdgeInsets.all(MgSpace.card),
                decoration: BoxDecoration(
                  color: MgColors.surface,
                  borderRadius: BorderRadius.circular(MgRadius.card),
                  border: Border.all(color: MgColors.line),
                  boxShadow: MgShadows.card,
                ),
                child: summary,
              ),
            ),
          ),
        ),
      Padding(
        padding: EdgeInsets.fromLTRB(MgSpace.gutter, summary != null && dark ? 0 : MgSpace.s16, MgSpace.gutter, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final c in children) ...[c, const SizedBox(height: MgSpace.s16)],
          if (steps.isNotEmpty) ...[MgStateSteps(title: stepsTitle, steps: steps), const SizedBox(height: MgSpace.s16)],
          if (tech != null) ...[MgTechDetails(details: tech!), const SizedBox(height: MgSpace.s8)],
          if (support) ...[MgSupportRow(onWrite: onWrite), const SizedBox(height: MgSpace.s16)],
        ]),
      ),
    ]);
    final dock = _dock();
    return Material(
      color: MgColors.canvas,
      child: Column(children: [
        Expanded(child: SingleChildScrollView(child: body)),
        if (dock != null) dock,
      ]),
    );
  }

  Widget _close(BuildContext context, bool dark) => onClose == null
      ? const SizedBox(height: 44)
      : MgV2Back(
          onTap: onClose,
          close: !closeIsBack,
          style: dark ? MgBackStyle.dark : MgBackStyle.light,
        );

  Widget _heroHeader(BuildContext context) {
    return MgRankHero(
      ambientKey: 'state',
      padding: EdgeInsets.fromLTRB(16, 8, 16, summary != null ? 48 : 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(alignment: Alignment.centerLeft, child: _close(context, true)),
        const SizedBox(height: 12),
        Center(child: MgToneDisc(tone: tone, size: 88, dark: true, icon: icon)),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(title, textAlign: TextAlign.center, style: MgType.h2.copyWith(color: MgColors.onDark)),
        ),
        if (why != null) ...[
          const SizedBox(height: 8),
          Text(why!, textAlign: TextAlign.center, style: MgType.body.copyWith(color: MgColors.onDarkLead)),
        ],
      ]),
    );
  }

  Widget _lightHeader(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, top + 8, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(alignment: Alignment.centerLeft, child: _close(context, false)),
        const SizedBox(height: 24),
        Center(child: MgToneDisc(tone: tone, size: 72, icon: icon)),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(title, textAlign: TextAlign.center, style: MgType.h2.copyWith(color: MgColors.ink)),
        ),
        if (why != null) ...[
          const SizedBox(height: 8),
          Text(why!, textAlign: TextAlign.center, style: MgType.body.copyWith(color: MgColors.body2)),
        ],
      ]),
    );
  }

  Widget? _dock() {
    if (primary == null && secondary == null) return null;
    final p = primary;
    final s = secondary;
    if (_darkHero) {
      return MgDock(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (p != null) MgCta(label: p.label, onTap: p.onTap, busy: p.busy, loop: loop, size: MgCtaSize.md56),
          if (s != null) Center(child: MgBtnText(label: s.label, onTap: s.onTap, dark: true, icon: s.icon)),
        ]),
      );
    }
    Widget primaryBtn(MgStateAction a) {
      if (a.sos) return MgBtnSos(label: a.label, onTap: a.onTap);
      if (a.destructive) return MgBtnDestructive(label: a.label, onTap: a.onTap, busy: a.busy);
      return MgBtnInk(label: a.label, onTap: a.onTap, busy: a.busy, icon: a.icon);
    }

    return MgDock(
      light: true,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (p != null) primaryBtn(p),
        if (s != null) Center(child: MgBtnText(label: s.label, onTap: s.onTap, icon: s.icon)),
      ]),
    );
  }
}
