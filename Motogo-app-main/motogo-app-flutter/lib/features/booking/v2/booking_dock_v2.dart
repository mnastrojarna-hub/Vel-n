import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_dock.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_cta.dart';

/// Sticky pay dock of the v2 booking form (board `.rk-sticky`): one context
/// line — the first blocker in amber ([blocker], same meaning as the
/// form's `canProceed` rule) or "Tvoje cena · n dny" over the price — a trailing link that
/// scrolls to the reason / the receipt, the docked AI disc (the floating
/// button is hidden on /booking) and the 60 px rank CTA with the OLD label
/// `proceedToPayment` and the form's OWN action ([onProceed]); locked
/// (still, no loop) exactly when the old button was disabled.
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
  Widget build(BuildContext context) {
    final tr = t(context);
    final line = blocker != null
        ? MgEnter(
            trigger: blocker,
            child: Row(children: [
              MgIcon(MgIcons.warn, size: 16, color: MgColors.warnDark),
              const SizedBox(width: 6),
              Flexible(
                child: Text(blocker!,
                    maxLines: 2, style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.warnDark)),
              ),
            ]),
          )
        : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(context2 ?? '', maxLines: 2, style: const TextStyle(color: MgColors.onDarkLead)),
            if (price != null)
              MgBump(
                trigger: price,
                child: Text(price!,
                    maxLines: 1,
                    style: MgType.tab(MgType.section.copyWith(fontWeight: FontWeight.w900, color: MgColors.neon))),
              ),
          ]);
    final trailing = onTrailing == null || trailingLabel == null
        ? null
        : Semantics(
            button: true,
            label: trailingLabel,
            excludeSemantics: true,
            onTap: onTrailing,
            child: MgPress(
              onTap: onTrailing,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(trailingLabel!,
                        style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.neonText)),
                    const SizedBox(width: 2),
                    MgIcon(blocker != null ? MgIcons.chevronDown : MgIcons.chevronUp,
                        size: 16, color: MgColors.neonText),
                  ]),
                ),
              ),
            ),
          );
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
