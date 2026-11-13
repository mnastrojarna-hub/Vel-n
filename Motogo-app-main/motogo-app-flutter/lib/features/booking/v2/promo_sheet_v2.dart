import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_space.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_inputs.dart';
import '../../../core/v2/widgets/mg_sheet.dart';

/// v2 look of the promo-code entry (CB-04): light sheet "Slevový kód nebo
/// poukaz" instead of the AlertDialog. Everything that matters is the old
/// dialog's: the SAME controller, the SAME `apply` (guard, validation,
/// percent rule, `onUpd`, pop on success), the SAME voucher chips and the
/// same error / loading state (read through [error] / [loading]). ✕,
/// "Zrušit", scrim and swipe-down close it without applying anything.
Future<void> showPromoSheetV2(
  BuildContext context, {
  required TextEditingController ctrl,
  required bool autofocus,
  required String? Function() error,
  required bool Function() loading,
  required Future<void> Function(BuildContext ctx, StateSetter ss) apply,
  required Widget Function(StateSetter ss) voucherChips,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: MgColors.nightA(0.55),
    elevation: 0,
    sheetAnimationStyle: MgMotion.sheetStyle(context),
    // R3-01: back closes this sheet, not the booking form under it.
    builder: (routeCtx) => mgSheetBack(routeCtx, StatefulBuilder(
      builder: (ctx, ss) {
        final tr = t(ctx);
        final busy = loading();
        final err = error();
        return MgSheetFrame(
          title: tr.tr('v2UxCbPromoTitle'),
          footer: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            MgBtnInk(
              label: tr.tr('apply'),
              busy: busy,
              onTap: busy ? null : () => apply(ctx, ss),
            ),
            Center(child: MgBtnText(label: tr.tr('cancel'), onTap: () => Navigator.pop(ctx))),
          ]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            voucherChips(ss),
            TextField(
              controller: ctrl,
              autofocus: autofocus,
              textCapitalization: TextCapitalization.characters,
              onSubmitted: (_) => apply(ctx, ss),
              style: MgType.tab(MgType.body.copyWith(color: MgColors.ink, fontWeight: FontWeight.w800)),
              decoration: mgInputDecoration(ctx, hint: tr.tr('efoPromoHint')),
            ),
            if (err != null) ...[
              const SizedBox(height: MgSpace.s12),
              MgStateBanner(tone: MgTone.err, title: err),
            ],
          ]),
        );
      },
    )),
  );
}
