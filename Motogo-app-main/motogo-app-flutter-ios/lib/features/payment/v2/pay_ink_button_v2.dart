import 'package:flutter/material.dart';

import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';

/// The card sheet's ink pay button as the Booking board draws it:
/// "Zaplatit **10 189 Kč** →" with the amount in neon (V22 wallet sheet).
/// Same body as `MgBtnInk` (ink fill, r button, min 56, press .97, busy =
/// spinner inside, disabled 45 %, one button semantics node with the plain
/// label); falls back to `MgBtnInk` when [amount] is not in [label].
class PayInkButtonV2 extends StatelessWidget {
  final String label;
  final String? amount;
  final VoidCallback? onTap;
  final bool busy;

  const PayInkButtonV2({super.key, required this.label, required this.amount, required this.onTap, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final a = amount;
    final at = a == null || a.isEmpty ? -1 : label.indexOf(a);
    if (at < 0) return MgBtnInk(label: label, onTap: onTap, busy: busy);
    final enabled = onTap != null && !busy;
    final style = MgType.button.copyWith(color: MgColors.onDark);
    Widget content = MgWordFit(
      alignment: Alignment.center,
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: label.substring(0, at)),
          TextSpan(text: a, style: MgType.tab(style.copyWith(color: MgColors.neon))),
          TextSpan(text: label.substring(at + a!.length)),
        ]),
        textAlign: TextAlign.center,
        softWrap: true,
        style: style,
      ),
    );
    if (busy) {
      content = Stack(alignment: Alignment.center, children: [
        Opacity(opacity: 0, child: content),
        const SizedBox(
            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: MgColors.onDark)),
      ]);
    }
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: MgPress(
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: onTap == null ? 0.45 : 1,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: MgSize.button),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: MgColors.ink, borderRadius: BorderRadius.circular(MgRadius.button)),
            alignment: Alignment.center,
            child: content,
          ),
        ),
      ),
    );
  }
}
