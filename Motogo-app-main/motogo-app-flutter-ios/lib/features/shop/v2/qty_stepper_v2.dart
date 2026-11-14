import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';

/// Quantity stepper of the v2 shop (Profil board): well pill, 44 px "−" /
/// "+" targets (press + selection haptic), the count tabular 15/800. The
/// buttons call the caller's EXISTING quantity actions; [onMinus] null =
/// the old minimum (nothing happens), drawn dimmed.
class QtyStepperV2 extends StatelessWidget {
  final int qty;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  const QtyStepperV2({super.key, required this.qty, required this.onMinus, required this.onPlus});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    Widget btn(Widget glyph, VoidCallback? onTap, String label) => Semantics(
          button: true,
          enabled: onTap != null,
          label: label,
          excludeSemantics: true,
          onTap: onTap,
          child: MgPress(
            scale: 0.92,
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(child: Opacity(opacity: onTap == null ? 0.35 : 1, child: glyph)),
            ),
          ),
        );
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: MgColors.well,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: MgColors.line),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn(Text('−', style: MgType.section.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink, height: 1)), onMinus,
            tr.tr('v2UxPsLess')),
        Semantics(
          liveRegion: true,
          label: '${tr.tr('quantityLabel')} $qty',
          excludeSemantics: true,
          child: SizedBox(
            width: 28,
            child: Text('$qty',
                textAlign: TextAlign.center, style: MgType.tab(MgType.title.copyWith(color: MgColors.ink))),
          ),
        ),
        btn(const MgIcon(MgIcons.plus, size: 18, color: MgColors.ink), onPlus, tr.tr('v2UxPsMore')),
      ]),
    );
  }
}
