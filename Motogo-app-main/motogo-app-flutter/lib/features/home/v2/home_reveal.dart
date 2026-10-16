import 'package:flutter/widgets.dart';

import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';

/// `MgReveal` that decides ONCE per element whether it is the first build
/// of [sessionKey] in this app session — the widget tree keeps its shape
/// on rebuilds (a rebuilt `MgReveal(sessionKey:)` swaps `_Reveal` for the
/// bare child and remounts the whole subtree, which would e.g. reset the
/// funnel carousel page).
class HomeReveal extends StatefulWidget {
  final Widget child;
  final int index;
  final String sessionKey;
  const HomeReveal({super.key, required this.child, required this.sessionKey, this.index = 0});

  @override
  State<HomeReveal> createState() => _HomeRevealState();
}

class _HomeRevealState extends State<HomeReveal> {
  late final bool _play = MgMotion.firstTime('home-reveal:${widget.sessionKey}:${widget.index}');

  @override
  Widget build(BuildContext context) =>
      _play ? MgReveal(index: widget.index, child: widget.child) : KeyedSubtree(child: widget.child);
}

/// Text link with a TRAILING chevron ("Vše ›", "Detail rezervace ›"),
/// 44 px hit; `#0D6E0D` on light, neon text on dark.
class HomeTextLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool dark;
  const HomeTextLink({super.key, required this.label, required this.onTap, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final c = dark ? MgColors.neonText : MgColors.link;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: MgPress(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text(label, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: c))),
              const SizedBox(width: 2),
              MgIcon(MgIcons.chevronRight, size: 16, color: c),
            ]),
          ),
        ),
      ),
    );
  }
}
