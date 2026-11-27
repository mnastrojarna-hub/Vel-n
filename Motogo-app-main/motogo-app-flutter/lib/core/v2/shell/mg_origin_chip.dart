import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../i18n/i18n_provider.dart';
import '../icons/mg_icon.dart';
import '../motion/mg_anim.dart';
import '../tokens/mg_colors.dart';
import '../tokens/mg_type.dart';
import 'shell_nav_map.dart';

/// Cross-tab back chip (DESIGN_V22 §6.2 exception): "‹ Domů / Pobočka" in
/// the dark header of tab [tab] while the tab was opened by a jump with
/// context (Home funnel → Motorky / Kalkulačka, Pobočka → REZERVOVAT ZDE,
/// Home → Všechny trasy). Gone after any tab switch. 44 px tall, on dark.
class MgOriginChip extends ConsumerWidget {
  final int tab;

  /// Space below the chip when it is shown.
  final double gap;
  const MgOriginChip({super.key, required this.tab, this.gap = 10});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final origin = ref.watch(v2TabOriginProvider);
    if (origin == null || origin.tab != tab) return const SizedBox.shrink();
    final tr = t(context);
    final label = tr.tr(origin.labelKey);
    void go() {
      HapticFeedback.selectionClick();
      ref.read(v2TabOriginProvider.notifier).state = null;
      GoRouter.maybeOf(context)?.go(origin.route);
    }

    return Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Semantics(
          button: true,
          label: '${tr.back}: $label',
          excludeSemantics: true,
          onTap: go,
          child: MgPress(
            onTap: go,
            child: Container(
              height: 44,
              padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 14, 0),
              decoration: BoxDecoration(
                color: MgColors.white(0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: MgColors.white(0.25)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const MgIcon(MgIcons.chevronLeft, size: 20, color: MgColors.onDark),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The jump's hint under the title of tab [tab]'s dark header ("Vyber si
/// motorku" after Rezervace → "Nová rezervace", owner 2026-11-27): one neon
/// line, not a control, gone with the chip (any tab switch). Nothing when
/// the jump carries no hint.
class MgOriginHint extends ConsumerWidget {
  final int tab;
  const MgOriginHint({super.key, required this.tab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final origin = ref.watch(v2TabOriginProvider);
    final key = origin?.hintKey;
    if (origin == null || origin.tab != tab || key == null) return const SizedBox.shrink();
    return Padding(
      key: const ValueKey('mg-origin-hint'),
      padding: const EdgeInsets.only(top: 6),
      child: Semantics(
        liveRegion: true,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const MgIcon(MgIcons.chevronDown, size: 16, color: MgColors.neonText),
          const SizedBox(width: 4),
          Flexible(
            child: Text(t(context).tr(key),
                style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.neonText, height: 1.2)),
          ),
        ]),
      ),
    );
  }
}
