import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_shadows.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';

/// Express layout of the booking form (Booking board "Máme to připravené",
/// DESIGN_V2 §8, CB-11): display parts only — the sections they open are
/// the form's own widgets, every value comes from the draft / breakdown.

/// Half-width pill button (board "Kód nebo poukaz" / "Poznámka"): white,
/// 1 px line, icon + label 13/800, 48 tall.
class BookingChipButtonV2 extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;
  const BookingChipButtonV2({super.key, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: MgPress(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: MgColors.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: MgColors.line),
              boxShadow: MgShadows.card,
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              MgIcon(icon, size: 18, color: MgColors.link),
              const SizedBox(width: 8),
              Flexible(
                child: MgWordFit(
                  minScale: 0.75,
                  child: Text(label, style: MgType.small.copyWith(fontSize: 13, fontWeight: FontWeight.w800, color: MgColors.ink)),
                ),
              ),
            ]),
          ),
        ),
      );
}

/// Row of the two express pills: "Kód nebo poukaz" ([onPromo] = the promo
/// section's own dialog) and the note pill passed in by the form view.
class BookingExpressChipsV2 extends StatelessWidget {
  final VoidCallback onPromo;
  final Widget? note;
  const BookingExpressChipsV2({super.key, required this.onPromo, this.note});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: [
          Expanded(child: BookingChipButtonV2(icon: MgIcons.tag, label: t(context).tr('v2UxCbPromoChip'), onTap: onPromo)),
          if (note != null) ...[const SizedBox(width: MgSpace.s8), Expanded(child: note!)],
        ]),
      );
}
