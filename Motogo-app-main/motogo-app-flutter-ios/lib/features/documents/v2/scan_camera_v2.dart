import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_back_v2.dart';
import '../../../core/v2/widgets/mg_buttons.dart';

/// v2 scanner frame colours (Profil board): night scrim, faint frame,
/// neon corners — passed to the existing `DocumentFramePainter`.
const kScanScrimV2 = Color(0x8C0A1F14); // night @ .55
const kScanBorderV2 = Color(0x59FFFFFF); // white @ .35
const kScanCornerV2 = MgColors.neon;

/// Top chrome over the camera: photo-style ‹ (works during upload too),
/// centred step chip "Občanský průkaz · přední strana 1/4", neon segments.
class ScanTopV2 extends StatelessWidget {
  final VoidCallback onBack;
  final String step;
  final int index;
  final int total;
  const ScanTopV2({super.key, required this.onBack, required this.step, required this.index, required this.total});

  @override
  Widget build(BuildContext context) {
    final d = MgMotion.of(context, MgMotion.sticky);
    return Column(children: [
      Row(children: [
        MgV2Back(onTap: onBack, style: MgBackStyle.photo),
        const SizedBox(width: 10),
        Expanded(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: MgColors.nightA(0.6), borderRadius: BorderRadius.circular(999)),
              child: Text('$step ${index + 1}/$total',
                  textAlign: TextAlign.center,
                  style: MgType.tab(MgType.micro.copyWith(fontSize: 12, fontWeight: FontWeight.w800, color: MgColors.onDark))),
            ),
          ),
        ),
        const SizedBox(width: 54),
      ]),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Row(children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: AnimatedContainer(
                duration: d,
                curve: MgMotion.emphasized,
                height: 6,
                decoration: BoxDecoration(
                  color: i <= index ? MgColors.neon : MgColors.white(0.24),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ]),
      ),
    ]);
  }
}

/// Bottom chrome: guide pill, 76 px shutter (white disc, 4 px neon ring,
/// press .92 + selection haptic; spinner while capturing), "Přeskočit".
class ScanControlsV2 extends StatelessWidget {
  final String guide;
  final bool capturing;
  final VoidCallback onCapture;
  final VoidCallback onSkip;
  const ScanControlsV2({
    super.key,
    required this.guide,
    required this.capturing,
    required this.onCapture,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: MgColors.nightA(0.6), borderRadius: BorderRadius.circular(14)),
          child: Text(guide,
              textAlign: TextAlign.center, style: MgType.small.copyWith(fontSize: 13, fontWeight: FontWeight.w700, color: MgColors.onDark)),
        ),
      ),
      const SizedBox(height: 14),
      Semantics(
        button: true,
        label: tr.tr('v2UxAsmShutter'),
        excludeSemantics: true,
        child: MgPress(
          scale: 0.92,
          onTap: capturing ? null : onCapture,
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: MgColors.surface,
              border: Border.all(color: MgColors.neon, width: 4),
              boxShadow: [BoxShadow(color: MgColors.neonA(0.35), blurRadius: 18)],
            ),
            child: Center(
              child: capturing
                  ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: MgColors.link))
                  : const MgIcon(MgIcons.camera, size: 30, color: MgColors.ink),
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
      MgBtnText(label: tr.tr('v2UxAsmSkip'), icon: MgIcons.chevronRight, dark: true, onTap: onSkip),
    ]);
  }
}
