import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_app_bar.dart';
import '../../../core/v2/chrome/mg_dock.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';

/// Focused community form (Navrhnout trasu / Přidat místo): dark compact
/// header with back (= the screen's PopScope via `maybePop`, so the
/// existing "Zahodit rozdělané?" guard stays in charge), light content,
/// dark dock "ODESLAT KE SCHVÁLENÍ" with the same submit / busy state.
class SubmitScaffoldV2 extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final bool busy;
  final String busyLabel;
  final VoidCallback onSubmit;

  const SubmitScaffoldV2({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    required this.busy,
    required this.busyLabel,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Scaffold(
      backgroundColor: MgColors.canvas,
      body: Column(children: [
        MgAppBar(title: title, subtitle: subtitle, onBack: () => Navigator.of(context).maybePop()),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: children,
          ),
        ),
      ]),
      bottomNavigationBar: MgDock(
        contextLine: busy
            ? Semantics(liveRegion: true, child: Text(busyLabel, style: MgType.small.copyWith(color: MgColors.onDarkLead)))
            : null,
        child: MgFabAvoid(
          child: MgCta(label: tr.tr('poiSubmitSend'), busy: busy, onTap: busy ? null : onSubmit),
        ),
      ),
    );
  }
}

/// "Návrh zkontroluje náš tým…" — the moderation note on light.
class SubmitNoteV2 extends StatelessWidget {
  final String text;
  const SubmitNoteV2(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MgColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MgColors.line),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const MgIconTileLight(MgIcons.shield),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: MgType.small.copyWith(color: MgColors.body2, fontWeight: FontWeight.w700))),
        ]),
      );
}

/// White card holding a map (rounded, line border).
class SubmitMapCardV2 extends StatelessWidget {
  final Widget map;
  final double height;
  final Widget? overlay;
  const SubmitMapCardV2({super.key, required this.map, this.height = 240, this.overlay});

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: MgColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MgColors.line),
          boxShadow: MgShadows.card,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(children: [
            Positioned.fill(child: map),
            if (overlay != null) Positioned(left: 8, right: 8, bottom: 8, child: Center(child: overlay)),
          ]),
        ),
      );
}

/// Link block of "Navrhnout trasu": label + ⓘ help, input, "Načíst body
/// z odkazu" and the result / error line — the screen's controller, flags
/// and `_loadLink` as is.
class SubmitLinkV2 extends StatelessWidget {
  final String label;
  final bool showHelp;
  final VoidCallback onToggleHelp;
  final String helpTitle;
  final List<String> helpLines;
  final Widget input;
  final bool decoding;
  final String loadLabel;
  final VoidCallback? onLoad;
  final String? okLine;
  final String? errLine;

  const SubmitLinkV2({
    super.key,
    required this.label,
    required this.showHelp,
    required this.onToggleHelp,
    required this.helpTitle,
    required this.helpLines,
    required this.input,
    required this.decoding,
    required this.loadLabel,
    required this.onLoad,
    required this.okLine,
    required this.errLine,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 14),
      decoration: BoxDecoration(
        color: MgColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MgColors.line),
        boxShadow: MgShadows.card,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(label.toUpperCase(), style: MgType.eyebrow.copyWith(color: MgColors.lead))),
          MgIconButton(
            icon: MgIcons.info,
            onTap: onToggleHelp,
            style: MgIconButtonStyle.light,
            semanticLabel: helpTitle,
            size: 40,
          ),
        ]),
        if (showHelp)
          Container(
            margin: const EdgeInsets.only(top: 6, right: 6, bottom: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: MgColors.well, borderRadius: BorderRadius.circular(12), border: Border.all(color: MgColors.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(helpTitle, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
              const SizedBox(height: 4),
              for (final l in helpLines) Text('•  $l', style: MgType.small.copyWith(color: MgColors.body2)),
            ]),
          ),
        const SizedBox(height: 8),
        Padding(padding: const EdgeInsets.only(right: 6), child: input),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: MgBtnInk(label: loadLabel, icon: MgIcons.external, busy: decoding, onTap: onLoad, height: 48),
        ),
        if (okLine != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              const MgIcon(MgIcons.check, size: 16, color: MgColors.link),
              const SizedBox(width: 6),
              Expanded(child: Text(okLine!, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.link))),
            ]),
          ),
        if (errLine != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const MgIcon(MgIcons.warn, size: 16, color: MgColors.err),
              const SizedBox(width: 6),
              Expanded(child: Text(errLine!, style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.err))),
            ]),
          ),
      ]),
    );
  }
}
