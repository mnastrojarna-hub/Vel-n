import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_skeleton.dart';

/// Document card in the dark docs hero (board `.dcard`): illustration,
/// title, Ověřeno / Neověřeno chip and the action (Smazat / Skenovat) —
/// the same callbacks as today's status rows.
class DocCardV2 extends StatelessWidget {
  final String icon;
  final String title;
  final bool verified;
  final VoidCallback onReset;
  final VoidCallback? onScan;
  const DocCardV2({
    super.key,
    required this.icon,
    required this.title,
    required this.verified,
    required this.onReset,
    this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final card = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MgColors.white(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: verified ? MgColors.neonA(0.35) : MgColors.warnDark.withValues(alpha: 0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Illustration(icon: icon, ok: verified),
        const SizedBox(height: 8),
        Text(title, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark)),
        const SizedBox(height: 6),
        Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: verified ? MgColors.neonA(0.18) : MgColors.warnDark.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            MgIcon(verified ? MgIcons.check : MgIcons.warn,
                size: 14, color: verified ? MgColors.neonText : MgColors.warnDark),
            const SizedBox(width: 4),
            Flexible(
              child: Text(verified ? tr.tr('verified') : tr.tr('notVerified'),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: MgType.micro.copyWith(
                      fontWeight: FontWeight.w800, height: 1, color: verified ? MgColors.neonText : MgColors.warnDark)),
            ),
          ]),
        ),
        if (verified || onScan != null)
          Semantics(
            button: true,
            child: MgPress(
              onTap: verified ? onReset : onScan,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  MgIcon(verified ? MgIcons.trash : MgIcons.camera,
                      size: 16, color: verified ? MgColors.errDark : MgColors.neonText),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(verified ? tr.tr('deleteDoc') : tr.tr('scan'),
                        style: MgType.small.copyWith(
                            fontWeight: FontWeight.w800, color: verified ? MgColors.errDark : MgColors.neonText)),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
    return card;
  }
}

class _Illustration extends StatelessWidget {
  final String icon;
  final bool ok;
  const _Illustration({required this.icon, required this.ok});

  @override
  Widget build(BuildContext context) => Container(
        height: 64,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: const LinearGradient(colors: [MgColors.glow, Color(0xFF13301F)]),
        ),
        child: Stack(children: [
          Positioned(left: 12, top: 12, child: MgIcon(icon, size: 28, color: ok ? MgColors.neon : MgColors.warnDark)),
          for (final (l, t, r) in const [(48.0, 16.0, 12.0), (48.0, 30.0, 34.0), (12.0, 48.0, 48.0)])
            Positioned(
              left: l,
              top: t,
              right: r,
              child: Container(height: 6, decoration: BoxDecoration(color: MgColors.white(0.18), borderRadius: BorderRadius.circular(2))),
            ),
        ]),
      );
}

/// Skeleton pair of doc cards while the status loads.
class DocCardsSkeletonV2 extends StatelessWidget {
  const DocCardsSkeletonV2({super.key});

  @override
  Widget build(BuildContext context) => const Row(children: [
        Expanded(child: MgSkeleton(height: 150, radius: 14, dark: true)),
        SizedBox(width: 10),
        Expanded(child: MgSkeleton(height: 150, radius: 14, dark: true)),
      ]);
}

/// "Tipy pro focení" — the scan tips behind ⓘ (expands in place).
class DocTipsV2 extends StatefulWidget {
  const DocTipsV2({super.key});

  @override
  State<DocTipsV2> createState() => _DocTipsV2State();
}

class _DocTipsV2State extends State<DocTipsV2> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(
        button: true,
        expanded: _open,
        child: MgPress(
          onTap: () => setState(() => _open = !_open),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(children: [
              const MgIcon(MgIcons.info, size: 18, color: MgColors.neonText),
              const SizedBox(width: 6),
              Expanded(
                child: Text(tr.tr('v2DocTips'),
                    style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.neonText)),
              ),
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: MgMotion.of(context, MgMotion.pop),
                child: const MgIcon(MgIcons.chevronDown, size: 18, color: MgColors.neonText),
              ),
            ]),
          ),
        ),
      ),
      AnimatedSize(
        duration: MgMotion.of(context, MgMotion.sheet),
        alignment: Alignment.topCenter,
        child: _open
            ? Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(tr.tr('scanTips'), style: MgType.small.copyWith(color: MgColors.onDarkLead)),
              )
            : const SizedBox(width: double.infinity),
      ),
    ]);
  }
}
