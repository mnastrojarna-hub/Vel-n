import 'package:flutter/material.dart';

import '../../../core/v2/chrome/mg_dock.dart';
import '../../../core/v2/chrome/mg_fab_avoid.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_cta.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';

/// Pay dock of the v2 payment page (Booking board `.rk-sticky`): one
/// context line ("Tvoje cena · 3 dny · ušetříš 1 585 Kč" / "K zaplacení ·
/// 3 408 Kč"), the optional "Rozpis ▴" link (the existing breakdown in a
/// sheet), and the 60 px rank CTA "ZAPLATIT · {charge}" running the
/// screen's OWN pay action. [busy] = spinner inside the CTA (+ [status] /
/// [statusNote] under it, the old button's verifying texts); [enabled]
/// false = locked exactly when the old button was (expired). The price
/// bumps when it changes; no shimmer (the CTA loop is the one fx).
class PayDockV2 extends StatelessWidget {
  final String contextLine;
  final String label;
  final String? price;
  final bool enabled;
  final bool busy;
  final bool arrow;
  final VoidCallback onPay;
  final String? status;
  final String? statusNote;
  final String? trailingLabel;
  final VoidCallback? onTrailing;

  /// false = light dock with the ink button (SOS: no rank, no loop).
  final bool rank;

  const PayDockV2({
    super.key,
    required this.contextLine,
    required this.label,
    required this.price,
    required this.enabled,
    required this.busy,
    required this.onPay,
    this.arrow = false,
    this.status,
    this.statusNote,
    this.trailingLabel,
    this.onTrailing,
    this.rank = true,
  });

  @override
  Widget build(BuildContext context) {
    final linkStyle = MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.neonText);
    final tl = trailingLabel;
    final trailing = tl == null || onTrailing == null
        ? null
        : Semantics(
            button: true,
            label: tl,
            excludeSemantics: true,
            onTap: onTrailing,
            child: MgPress(
              onTap: onTrailing,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(tl, maxLines: 1, softWrap: false, style: linkStyle),
                    const SizedBox(width: 2),
                    const MgIcon(MgIcons.chevronUp, size: 16, color: MgColors.neonText),
                  ]),
                ),
              ),
            ),
          );
    final noteStyle = MgType.small.copyWith(color: MgColors.onDarkLead);
    if (!rank) {
      return MgDock(
        light: true,
        contextLine: MgWordFit(child: Text(contextLine, maxLines: 2, style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w700)))),
        child: MgBtnInk(
          key: const ValueKey('pay-v2-cta'),
          label: price == null ? label : '$label · $price',
          busy: busy,
          onTap: enabled ? onPay : null,
        ),
      );
    }
    return DecoratedBox(
      // Opaque backing: the night dock would let page text ghost through.
      decoration: const BoxDecoration(
        color: MgColors.night,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: MgDock(
        contextLine: MgWordFit(
          child: Text(contextLine,
              maxLines: 2, style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDarkLead))),
        ),
        trailing: trailing,
        child: MgFabAvoid(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            MgBump(
              trigger: price,
              child: MgCta(
                key: const ValueKey('pay-v2-cta'),
                label: label,
                price: price,
                arrow: arrow,
                onTap: enabled ? onPay : null,
                enabled: enabled,
                busy: busy,
                size: MgCtaSize.lg60,
                loop: enabled && !busy,
              ),
            ),
            if (busy && status != null) ...[
              const SizedBox(height: 8),
              Text(status!, textAlign: TextAlign.center, style: noteStyle.copyWith(fontWeight: FontWeight.w800, color: MgColors.onDark)),
            ],
            if (busy && statusNote != null) ...[
              const SizedBox(height: 4),
              Text(statusNote!, textAlign: TextAlign.center, style: noteStyle),
            ],
          ]),
        ),
      ),
    );
  }
}
