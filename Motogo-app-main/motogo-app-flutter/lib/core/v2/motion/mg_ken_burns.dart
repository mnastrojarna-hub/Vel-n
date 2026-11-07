import 'package:flutter/material.dart';

import 'mg_anim.dart';
import 'mg_motion.dart';

/// Ken Burns on a hero photo (design M2, V2 §1.2): ONE shot of 8 s easeOut
/// from [scaleTo] to 1, never infinite. With [sessionKey] it plays only the
/// first time that key is shown in this app session (later: static). Reduced
/// motion: static.
class MgKenBurns extends StatefulWidget {
  final Widget child;
  final String? sessionKey;
  final double scaleTo;
  const MgKenBurns({super.key, required this.child, this.sessionKey, this.scaleTo = 1.06});

  @override
  State<MgKenBurns> createState() => _MgKenBurnsState();
}

class _MgKenBurnsState extends State<MgKenBurns> {
  late final bool _play = widget.sessionKey == null || MgMotion.firstTime('kenBurns:${widget.sessionKey}');

  @override
  Widget build(BuildContext context) {
    if (!_play || MgMotion.reduced(context)) return widget.child;
    final from = widget.scaleTo;
    return MgProgressOnce(
      duration: MgMotion.kenBurns,
      curve: Curves.easeOut,
      builder: (_, t) => Transform.scale(scale: from - (from - 1) * t, child: widget.child),
    );
  }
}
