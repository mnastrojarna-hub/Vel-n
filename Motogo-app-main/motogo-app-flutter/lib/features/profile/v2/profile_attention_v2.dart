import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/router.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../documents/docs_gate_provider.dart';
import '../../messages/messages_provider.dart' show adminUnreadCountProvider;
import '../../sos/sos_provider.dart' show hasActiveRentalProvider;
import 'profile_v2_parts.dart';

enum _AttKind { sos, docs, unread }

/// Attention strip under the header (V21 §1.2): white chips with tone
/// icons, priority SOS (only during a rental) → documents missing → unread
/// messages; max 2 chips + "+n". Hidden when nothing applies.
class ProfileAttentionV2 extends ConsumerWidget {
  const ProfileAttentionV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final sos = ref.watch(hasActiveRentalProvider);
    final docs = ref.watch(docsFabStatusProvider).valueOrNull;
    final unread = ref.watch(adminUnreadCountProvider);
    final items = <_AttKind>[
      if (sos) _AttKind.sos,
      if (docs != null && !docs.isComplete) _AttKind.docs,
      if (unread > 0) _AttKind.unread,
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    final shown = items.take(2).toList();
    final more = items.length - shown.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < shown.length; i++)
          MgEnter(
            delay: Duration(milliseconds: 80 * i),
            child: switch (shown[i]) {
              _AttKind.sos => MgFabAvoid(
                  kind: MgAvoidKind.sos,
                  child: _Chip(
                    label: tr.sosTitle,
                    icon: MgIcons.sos,
                    discBg: MgColors.sos,
                    discFg: MgColors.onDark,
                    border: MgColors.errBorder,
                    fg: MgColors.err,
                    onTap: () => context.push(Routes.sos),
                  ),
                ),
              _AttKind.docs => _Chip(
                  label: tr.tr('docsNotVerified'),
                  icon: MgIcons.idCard,
                  discBg: MgColors.warnBg,
                  discFg: MgColors.warn,
                  discBorder: MgColors.warnBorder,
                  onTap: () => context.push(Routes.docs),
                ),
              _AttKind.unread => _Chip(
                  label: pfPlural(tr, 'v2PfUnread', unread),
                  icon: MgIcons.chat,
                  discBg: MgColors.panel,
                  discFg: MgColors.neon,
                  onTap: () => context.push(Routes.messages),
                ),
            },
          ),
        if (more > 0)
          Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: MgColors.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: MgColors.line),
            ),
            child: Center(
              widthFactor: 1,
              child: Text('+$more', style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.lead))),
            ),
          ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final String icon;
  final Color discBg;
  final Color discFg;
  final Color? discBorder;
  final Color border;
  final Color fg;
  final VoidCallback onTap;
  const _Chip({
    required this.label,
    required this.icon,
    required this.discBg,
    required this.discFg,
    required this.onTap,
    this.discBorder,
    this.border = MgColors.line,
    this.fg = MgColors.ink,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: MgPress(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
          decoration: BoxDecoration(
            color: MgColors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
            boxShadow: MgShadows.icon,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: discBg,
                shape: BoxShape.circle,
                border: discBorder == null ? null : Border.all(color: discBorder!),
              ),
              child: Center(child: MgIcon(icon, size: 20, color: discFg)),
            ),
            const SizedBox(width: 10),
            Flexible(child: Text(label, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: fg))),
          ]),
        ),
      ),
    );
  }
}
