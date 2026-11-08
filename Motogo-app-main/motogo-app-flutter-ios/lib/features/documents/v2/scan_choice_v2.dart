import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_status_bar.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../../../core/v2/widgets/mg_skeleton.dart';

/// One document choice of the scanner (same `_selectIdType` action).
/// [sub] = what exactly gets photographed (scanChoiceSub); null = the plain
/// "{n} × skenovat" line.
typedef ScanChoice = ({String icon, String label, int steps, String? sub, VoidCallback onTap});

/// Night page of the scanner (choice, loading, verifying): dark gradient,
/// ‹ + "Skenování dokladů".
class ScanNightPageV2 extends StatelessWidget {
  final VoidCallback onBack;
  final Widget child;
  const ScanNightPageV2({super.key, required this.onBack, required this.child});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return MgStatusBar(
      dark: true,
      child: Material(
        color: MgColors.night,
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: MgGradients.dark),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, top + 8, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                MgV2Back(onTap: onBack, style: MgBackStyle.dark),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(t(context).tr('scanDocuments'),
                      maxLines: 2, style: MgType.h3.copyWith(color: MgColors.onDark)),
                ),
              ]),
              Expanded(child: child),
            ]),
          ),
        ),
      ),
    );
  }
}

/// v2 document choice (Profil board "Skenování dokladů"): title, glass rows
/// (dark icon tile, name, "4 × skenovat", neon chevron), trust chips.
/// [loading] = the plan of missing sides is loading → skeleton rows.
class ScanChoiceV2 extends StatelessWidget {
  final VoidCallback onBack;
  final List<ScanChoice> choices;
  final bool loading;

  /// Line under the title (what the bike handover needs); null = none.
  final String? note;
  const ScanChoiceV2({super.key, required this.onBack, required this.choices, this.loading = false, this.note});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return ScanNightPageV2(
      onBack: onBack,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(top: 24, bottom: MediaQuery.paddingOf(context).bottom + 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr.tr('v2UxAsmPickDoc'), style: MgType.h2.copyWith(color: MgColors.onDark)),
          if (note != null) ...[
            const SizedBox(height: 8),
            Text(note!, style: MgType.body.copyWith(color: MgColors.onDarkMeta)),
          ],
          const SizedBox(height: 16),
          if (loading)
            for (var i = 0; i < 3; i++) ...[
              const MgSkeletonRow(thumb: 44, dark: true, lines: 2),
              const SizedBox(height: 12),
            ]
          else
            for (final c in choices) ...[_Row(c: c), const SizedBox(height: 12)],
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Trust(icon: MgIcons.shield, text: tr.tr('secureRecognition')),
            _Trust(icon: MgIcons.lock, text: tr.tr('dataStoredLocally')),
            // The old screen's third badge (same literal, all languages).
            const _Trust(icon: MgIcons.checkCircle, text: 'EU GDPR compliant'),
          ]),
        ]),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final ScanChoice c;
  const _Row({required this.c});

  @override
  Widget build(BuildContext context) {
    final sub = c.sub ?? t(context).trArgs('v2UxAsmScanTimes', {'n': c.steps});
    return Semantics(
      button: true,
      label: '${c.label}, $sub',
      excludeSemantics: true,
      child: MgPress(
        onTap: c.onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: MgColors.white(0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MgColors.white(0.14)),
          ),
          child: Row(children: [
            MgIconTileDark(c.icon, size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.label, style: MgType.title.copyWith(color: MgColors.onDark)),
                const SizedBox(height: 2),
                Text(sub, style: MgType.small.copyWith(color: MgColors.onDarkMeta), maxLines: 3),
              ]),
            ),
            const MgIcon(MgIcons.chevronRight, size: 22, color: MgColors.neon),
          ]),
        ),
      ),
    );
  }
}

class _Trust extends StatelessWidget {
  final String icon;
  final String text;
  const _Trust({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: MgColors.white(0.08), borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          MgIcon(icon, size: 16, color: MgColors.neon),
          const SizedBox(width: 6),
          Flexible(child: Text(text, style: MgType.micro.copyWith(fontSize: 12, color: MgColors.onDarkLead))),
        ]),
      );
}

/// Verifying after the last side (old: ✅ + spinner): the pending ring is
/// the screen's one live indicator until the flow moves on by itself.
class ScanVerifyingV2 extends StatelessWidget {
  final VoidCallback onBack;
  const ScanVerifyingV2({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return ScanNightPageV2(
      onBack: onBack,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const MgToneDisc(tone: MgTone.pending, size: 88, dark: true),
          const SizedBox(height: 20),
          Semantics(
            liveRegion: true,
            child: Text(tr.tr('scanComplete'),
                textAlign: TextAlign.center, style: MgType.h2.copyWith(color: MgColors.onDark)),
          ),
          const SizedBox(height: 8),
          Text(tr.tr('v2UxAsmVerifying'), textAlign: TextAlign.center, style: MgType.body.copyWith(color: MgColors.onDarkLead)),
          const SizedBox(height: 60),
        ]),
      ),
    );
  }
}
