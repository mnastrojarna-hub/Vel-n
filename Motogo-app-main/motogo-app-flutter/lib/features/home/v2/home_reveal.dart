import 'package:flutter/widgets.dart';

import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';

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
