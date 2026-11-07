import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/states/mg_state_screen.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_chips.dart';
import '../../../core/v2/widgets/mg_emoji_map.dart' show mgStripEmoji;

/// Splits the scanner's field summary ("Jméno: Jan\nČíslo: 123") into
/// label / value tiles; other lines stay plain notes. Display only.
(List<(String, String)>, List<String>) scanFieldsOf(String text) {
  final fields = <(String, String)>[];
  final notes = <String>[];
  for (final raw in text.split('\n')) {
    final l = mgStripEmoji(raw).trim();
    if (l.isEmpty) continue;
    final i = l.indexOf(': ');
    if (i > 0 && i < 32) {
      fields.add((l.substring(0, i), l.substring(i + 2)));
    } else {
      notes.add(l);
    }
  }
  return (fields, notes);
}

/// Light T2 panel over the camera (the camera keeps running behind it):
/// enters with `MgEnter`, no drag-dismiss (a decision is required).
class ScanPanelV2 extends StatelessWidget {
  final Widget child;
  const ScanPanelV2({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Stack(children: [
      Positioned.fill(child: ColoredBox(color: MgColors.nightA(0.55))),
      Align(
        alignment: Alignment.bottomCenter,
        child: MgEnter(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: (mq.size.height - mq.padding.top) * 0.86),
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: MgColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                boxShadow: MgShadows.sheet,
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 20, 16, mq.padding.bottom + 16),
                child: child,
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Result of one side: success (✓ + recognised fields as 2-column well
/// tiles, "Pokračovat →") or error (reason, guidance steps, attempts chip,
/// "Zkusit znovu", "Přeskočit"). Same callbacks as the old overlay.
class ScanResultV2 extends StatelessWidget {
  final bool ok;
  final String side;
  final String message;
  final String guidance;
  final int remaining;
  final VoidCallback onContinue;
  final VoidCallback onRetry;
  final VoidCallback onSkip;
  const ScanResultV2({
    super.key,
    required this.ok,
    required this.side,
    required this.message,
    required this.guidance,
    required this.remaining,
    required this.onContinue,
    required this.onRetry,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final (fields, notes) = ok ? scanFieldsOf(message) : (const <(String, String)>[], const <String>[]);
    final steps = [for (final l in guidance.split('\n')) if (mgStripEmoji(l).trim().isNotEmpty) mgStripEmoji(l).trim()];
    return ScanPanelV2(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          MgToneDisc(tone: ok ? MgTone.ok : MgTone.warn, size: 56),
          if (!ok && remaining > 0) ...[
            const SizedBox(width: 12),
            Flexible(
              child: MgMeaningChip(label: tr.trArgs('scanAttemptsLeft', {'n': remaining}), tone: MgTone.warn),
            ),
          ],
        ]),
        const SizedBox(height: 14),
        Semantics(
          liveRegion: true,
          header: true,
          child: Text(tr.tr(ok ? 'v2UxAsmScanOk' : 'v2UxAsmScanFail'), style: MgType.h3.copyWith(color: MgColors.ink)),
        ),
        const SizedBox(height: 4),
        Text(side, style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.meta)),
        const SizedBox(height: 12),
        if (ok) ...[
          if (fields.isNotEmpty) _Tiles(fields: fields),
          for (final n in notes) ...[
            const SizedBox(height: 8),
            Text(n, style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: fields.isEmpty ? MgColors.body2 : MgColors.warn)),
          ],
          const SizedBox(height: 18),
          MgBtnInk(label: tr.tr('continueBtn'), icon: MgIcons.arrowRight, onTap: onContinue),
        ] else ...[
          Text(mgStripEmoji(message), style: MgType.body.copyWith(color: MgColors.body2)),
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 12),
            MgStateSteps(steps: steps.take(3).toList(), compact: true),
          ],
          const SizedBox(height: 18),
          MgBtnInk(label: tr.tr('retry'), icon: MgIcons.camera, onTap: onRetry),
          const SizedBox(height: 4),
          Center(child: MgBtnText(label: tr.tr('v2UxAsmSkip'), onTap: onSkip)),
        ],
      ]),
    );
  }
}

class _Tiles extends StatelessWidget {
  final List<(String, String)> fields;
  const _Tiles({required this.fields});

  @override
  Widget build(BuildContext context) {
    Widget tile((String, String) f) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: MgColors.well, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(f.$1, style: MgType.meta.copyWith(color: MgColors.meta)),
            const SizedBox(height: 2),
            Text(f.$2, style: MgType.small.copyWith(fontSize: 14, fontWeight: FontWeight.w800, color: MgColors.ink)),
          ]),
        );
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 8) / 2;
      final one = w < 130;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final f in fields) SizedBox(width: one ? c.maxWidth : w, child: tile(f)),
      ]);
    });
  }
}

/// After the last allowed attempt (old "📞 Pomůžeme vám osobně"): call /
/// write (existing tel: / mailto:), try once more, close the scanner.
class ScanHelpV2 extends StatelessWidget {
  final int attempts;
  final String side;
  final String guidance;
  final String phone;
  final VoidCallback onCall;
  final VoidCallback onWrite;
  final VoidCallback onTryAgain;
  final VoidCallback onClose;
  const ScanHelpV2({
    super.key,
    required this.attempts,
    required this.side,
    required this.guidance,
    required this.phone,
    required this.onCall,
    required this.onWrite,
    required this.onTryAgain,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final steps = [for (final l in guidance.split('\n')) if (mgStripEmoji(l).trim().isNotEmpty) mgStripEmoji(l).trim()];
    return ScanPanelV2(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Align(alignment: Alignment.centerLeft, child: MgToneDisc(tone: MgTone.info, size: 56, icon: MgIcons.user)),
        const SizedBox(height: 14),
        Semantics(
          liveRegion: true,
          header: true,
          child: Text(tr.tr('v2UxAsmHelpTitle'), style: MgType.h3.copyWith(color: MgColors.ink)),
        ),
        const SizedBox(height: 4),
        Text(side, style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.meta)),
        const SizedBox(height: 8),
        Text(tr.trArgs('v2UxAsmHelpText', {'n': attempts}), style: MgType.body.copyWith(color: MgColors.body2)),
        if (steps.isNotEmpty) ...[
          const SizedBox(height: 12),
          MgStateSteps(steps: steps.take(3).toList(), compact: true),
        ],
        const SizedBox(height: 18),
        MgBtnInk(label: '${tr.tr('callLabel')} $phone', icon: MgIcons.phone, onTap: onCall),
        const SizedBox(height: 8),
        MgBtnGhostLight(label: tr.tr('scanWriteBtn'), icon: MgIcons.mail, onTap: onWrite),
        const SizedBox(height: 4),
        Wrap(alignment: WrapAlignment.spaceEvenly, children: [
          MgBtnText(label: tr.tr('scanTryAgainAnyway'), onTap: onTryAgain),
          MgBtnText(label: tr.tr('scanCloseScanner'), onTap: onClose),
        ]),
      ]),
    );
  }
}

/// Camera cannot start (Profil board 11.7): light T1 — warn camera disc,
/// why (the scanner's own message), the gallery hint as the fix step;
/// "Otevřít nastavení" only when settings can fix it, "Zkusit znovu", ‹.
class ScanCameraErrorV2 extends StatelessWidget {
  final String message;
  final VoidCallback? onSettings;
  final VoidCallback onRetry;
  final VoidCallback onBack;
  const ScanCameraErrorV2({
    super.key,
    required this.message,
    required this.onSettings,
    required this.onRetry,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return MgStateScreen(
      tone: MgTone.warn,
      icon: MgIcons.camera,
      title: tr.tr('v2UxAsmCamTitle'),
      why: message,
      stepsTitle: tr.tr('v2UxAsmHowToFix'),
      steps: [tr.tr('eoScanUseGallery')],
      onClose: onBack,
      closeIsBack: true,
      primary: onSettings != null
          ? MgStateAction(tr.tr('eoOpenSettings'), onSettings, icon: MgIcons.gear)
          : MgStateAction(tr.tr('eoRetry'), onRetry),
      secondary: onSettings != null ? MgStateAction(tr.tr('eoRetry'), onRetry) : MgStateAction(tr.tr('eoBack'), onBack),
    );
  }
}
