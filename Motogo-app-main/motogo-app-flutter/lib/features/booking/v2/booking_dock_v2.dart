import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_dock.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import 'booking_v2_parts.dart';

/// Sticky pay dock of the v2 booking form (board `.rk-sticky`): one context
/// line — the first blocker in amber ([blocker], same meaning as the
/// form's `canProceed` rule) or "Tvoje cena · n dny" over the price — a trailing link that
/// scrolls to the reason / the receipt, the docked AI disc (the floating
/// button is hidden on /booking) and the 60 px rank CTA with the OLD label
/// `proceedToPayment` and the form's OWN action ([onProceed]); locked
/// (still, no loop) exactly when the old button was disabled.
///
/// The price never clips (scales down instead), the blocker gets up to 3
/// lines, and when the text beside the trailing link would be narrower
/// than its longest word (narrow phone / large text) the link turns into
/// a 44 px chevron button with the same label for screen readers.
class BookingDockV2 extends StatelessWidget {
  final bool canProceed;
  final String? blocker;
  final String? context2;
  final String? price;
  final VoidCallback onProceed;
  final VoidCallback? onTrailing;
  final String? trailingLabel;

  const BookingDockV2({
    super.key,
    required this.canProceed,
    required this.blocker,
    required this.context2,
    required this.price,
    required this.onProceed,
    this.onTrailing,
    this.trailingLabel,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) => _build(context, c.maxWidth));

  Widget _build(BuildContext context, double width) {
    final tr = t(context);
    final blockerStyle = MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.warnDark);
    final ctxStyle = MgType.small.copyWith(fontWeight: FontWeight.w700);
    final priceStyle = MgType.tab(MgType.section.copyWith(fontWeight: FontWeight.w900, color: MgColors.neon));
    final linkStyle = MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.neonText);
    final line = blocker != null
        ? MgEnter(
            trigger: blocker,
            child: Row(children: [
              MgIcon(MgIcons.warn, size: 16, color: MgColors.warnDark),
              const SizedBox(width: 6),
              Flexible(child: MgWordFit(child: Text(blocker!, maxLines: 3, style: blockerStyle))),
            ]),
          )
        : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            MgWordFit(child: Text(context2 ?? '', maxLines: 2, style: const TextStyle(color: MgColors.onDarkLead))),
            if (price != null)
              MgBump(
                trigger: price,
                // Money is never cut: a long amount scales down instead.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(price!, maxLines: 1, softWrap: false, style: priceStyle),
                ),
              ),
          ]);
    final label = trailingLabel;
    Widget? trailing;
    if (onTrailing != null && label != null) {
      // Context row = dock width − 2 × 16 padding − the docked AI disc (8 + 44).
      final row = width - 32 - 52;
      final full = math.max(44.0, bkLineWidth(context, label, linkStyle) + 34);
      final need = blocker != null
          ? math.max(150.0, 22 + bkWordWidth(context, blocker!, blockerStyle))
          : math.max(120.0,
              math.max(bkWordWidth(context, context2 ?? '', ctxStyle), bkLineWidth(context, price ?? '', priceStyle)));
      final iconOnly = row - full < need;
      final chevron = MgIcon(blocker != null ? MgIcons.chevronDown : MgIcons.chevronUp,
          size: iconOnly ? 18 : 16, color: MgColors.neonText);
      trailing = Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: onTrailing,
        child: MgPress(
          onTap: onTrailing,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: iconOnly
                ? Center(
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: MgColors.neonA(0.35)),
                      ),
                      child: chevron,
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(label, maxLines: 1, softWrap: false, style: linkStyle),
                      const SizedBox(width: 2),
                      chevron,
                    ]),
                  ),
          ),
        ),
      );
    }
    // Opaque backing: the dock is night .96 without blur, so page text
    // would ghost through (most visible under the locked CTA).
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: MgColors.night,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: MgDock(
        aiDisc: true,
        contextLine: line,
        trailing: trailing,
        child: MgFabAvoid(
          child: MgCta(
            label: tr.tr('proceedToPayment'),
            arrow: true,
            onTap: canProceed ? onProceed : null,
            enabled: canProceed,
            size: MgCtaSize.lg60,
            loop: canProceed,
          ),
        ),
      ),
    );
  }
}
