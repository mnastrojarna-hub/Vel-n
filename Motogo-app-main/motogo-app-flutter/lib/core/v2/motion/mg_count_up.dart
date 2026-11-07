import 'package:flutter/widgets.dart';

import '../tokens/mg_type.dart';
import 'mg_motion.dart';
import 'mg_once_progress.dart';

/// Personal NON-price stat counting 0 → [value] over `MgMotion.countUp`
/// (700 ms, out) once per [sessionKey] (km ridden, rides, points; V2 §1.2,
/// V21 §2.5). NEVER for prices or totals — those use `bump`. Tabular
/// figures; reduced motion / second time: the final value at once.
class MgCountUp extends StatelessWidget {
  final num value;
  final String Function(num) format;
  final String? sessionKey;
  final TextStyle? style;
  final TextAlign? textAlign;

  const MgCountUp({
    super.key,
    required this.value,
    required this.format,
    this.sessionKey,
    this.style,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final s = MgType.tab(DefaultTextStyle.of(context).style.merge(style));
    return Semantics(
      label: format(value),
      excludeSemantics: true,
      child: MgOnceProgress(
        duration: MgMotion.countUp,
        sessionKey: sessionKey == null ? null : 'countUp:$sessionKey',
        builder: (_, t) {
          final v = t >= 1 ? value : (value is int ? (value * t).round() : value * t);
          return Text(format(v), style: s, textAlign: textAlign);
        },
      ),
    );
  }
}
