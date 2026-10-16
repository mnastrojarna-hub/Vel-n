import 'package:flutter/material.dart';

import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_icon_tile.dart';
import '../branches_widgets.dart' show plainText, richText;

/// Branch badge (OBSLUŽNÁ / SAMOOBSLUŽNÁ POBOČKA) — dark pill, neon text on
/// light; glass on dark.
class BranchBadgeV2 extends StatelessWidget {
  final String? html;
  final bool dark;
  const BranchBadgeV2({super.key, required this.html, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final text = plainText(html ?? '').toUpperCase();
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: dark ? MgColors.neonA(0.14) : MgColors.panel,
        borderRadius: BorderRadius.circular(999),
        border: dark ? Border.all(color: MgColors.neonA(0.4)) : null,
      ),
      child: Text(text, style: MgType.eyebrow.copyWith(color: dark ? MgColors.neonText : MgColors.neon)),
    );
  }
}

/// Icon + CMS rich text line (address, hours, gear).
class BranchLineV2 extends StatelessWidget {
  final String icon;
  final String? html;
  final bool dark;
  const BranchLineV2({super.key, required this.icon, required this.html, this.dark = false});

  @override
  Widget build(BuildContext context) {
    if ((html ?? '').trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: MgIcon(icon, size: 18, color: dark ? MgColors.neonText : MgColors.link),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: richText(html, MgType.body.copyWith(color: dark ? MgColors.onDarkLead : MgColors.body2)),
        ),
      ]),
    );
  }
}

/// White collapsible card (collapsed by default, as today's
/// `CollapsibleSection` on the branch detail): icon tile, title, chevron.
class BranchCollapsibleV2 extends StatefulWidget {
  final String icon;
  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;
  const BranchCollapsibleV2({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    this.initiallyExpanded = false,
  });

  @override
  State<BranchCollapsibleV2> createState() => _BranchCollapsibleV2State();
}

class _BranchCollapsibleV2State extends State<BranchCollapsibleV2> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MgColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MgColors.line),
        boxShadow: MgShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(
            button: true,
            expanded: _open,
            child: InkWell(
              onTap: () => setState(() => _open = !_open),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    MgIconTileLight(widget.icon),
                    const SizedBox(width: 12),
                    Expanded(child: Text(widget.title, style: MgType.title.copyWith(color: MgColors.ink))),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: MgMotion.of(context, MgMotion.pop),
                      child: const MgIcon(MgIcons.chevronDown, size: 20, color: MgColors.meta),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: MgMotion.of(context, MgMotion.sheet),
            alignment: Alignment.topCenter,
            child: _open
                ? MgEnter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: widget.children),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ]),
      ),
    );
  }
}
