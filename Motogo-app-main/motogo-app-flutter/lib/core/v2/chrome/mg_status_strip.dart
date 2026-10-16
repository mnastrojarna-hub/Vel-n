import 'package:flutter/material.dart';

import '../../i18n/i18n_provider.dart';
import '../icons/mg_icon.dart';
import '../motion/mg_anim.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_shadows.dart';
import '../tokens/mg_type.dart';

/// What a status strip is about (icon disc colour; meaning, never rank).
enum MgStripKind { sos, pay, verifying, docs, route, cart }

/// T4 global strip (night glass r14, icon disc 36 / icon 20, title 14/800 +
/// optional sub, chevron, ✕ 44 only when today's FAB has one). The v2 face
/// of the shell FABs: same visibility rules, same onTap / onDismiss
/// closures (they stay in `shell_fabs.dart`).
class MgStatusStrip extends StatelessWidget {
  final MgStripKind kind;
  final String title;
  final String? sub;
  final VoidCallback onTap;
  final VoidCallback? onDismiss;
  final String? dismissLabel;

  const MgStatusStrip({
    super.key,
    required this.kind,
    required this.title,
    required this.onTap,
    this.sub,
    this.onDismiss,
    this.dismissLabel,
  });

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, String icon, Gradient? g) = switch (kind) {
      MgStripKind.sos => (MgColors.sos, MgColors.onDark, MgIcons.alert, null),
      MgStripKind.pay => (MgColors.neon, MgColors.onNeon, MgIcons.card, MgGradients.neon),
      MgStripKind.verifying => (MgColors.warnDark, MgColors.onNeon, MgIcons.clock, null),
      MgStripKind.docs => (MgColors.warnBorder, const Color(0xFF3A2400), MgIcons.docs, null),
      MgStripKind.route => (const Color(0x00000000), MgColors.neon, MgIcons.navigate, null),
      MgStripKind.cart => (MgColors.white(0.10), MgColors.onDark, MgIcons.cart, null),
    };
    final disc = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: g == null ? bg : null,
        gradient: g,
        shape: BoxShape.circle,
        border: kind == MgStripKind.route ? Border.all(color: MgColors.neon, width: 1.5) : null,
      ),
      child: Center(child: MgIcon(icon, size: 20, color: fg)),
    );
    final main = Semantics(
      button: true,
      label: sub == null ? title : '$title, $sub',
      excludeSemantics: true,
      onTap: onTap,
      child: MgPress(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(children: [
              disc,
              const SizedBox(width: 12),
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MgType.body.copyWith(fontWeight: FontWeight.w800, height: 1.25, color: MgColors.onDark)),
                  if (sub != null)
                    Text(sub!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MgType.tab(MgType.small.copyWith(height: 1.25, color: MgColors.onDarkSecondary))),
                ]),
              ),
              const MgIcon(MgIcons.chevronRight, size: 20, color: MgColors.neonText),
            ]),
          ),
        ),
      ),
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(
        color: MgColors.night.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MgColors.neonA(0.3)),
        boxShadow: [BoxShadow(color: MgColors.black(0.28), blurRadius: 18, spreadRadius: -6, offset: const Offset(0, 8))],
      ),
      child: Row(children: [
        Expanded(child: main),
        if (onDismiss != null)
          Semantics(
            button: true,
            label: dismissLabel ?? t(context).tr('close'),
            excludeSemantics: true,
            onTap: onDismiss,
            child: MgPress(
              scale: 0.92,
              onTap: onDismiss,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: MgColors.white(0.10), shape: BoxShape.circle),
                    child: const Center(child: MgIcon(MgIcons.close, size: 18, color: MgColors.onDark)),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
