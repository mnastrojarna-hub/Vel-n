import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/states/mg_tone.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_buttons.dart';
import '../../../core/v2/widgets/mg_dialog.dart';
import '../../../core/v2/widgets/mg_inputs.dart';

/// T6 look of the storno confirmation (`ResCancelDialog`, V22 12.21). The
/// dialog State keeps the refund maths, the reason, the RPC and the
/// "cannot close while cancelling" guard; this only draws them.
class ResCancelConfirmV2 extends StatelessWidget {
  final String motoName;
  final String dateRange;
  final int pct;
  final String refundLine;
  final bool loading;
  final ValueChanged<String> onReason;
  final VoidCallback onKeep;
  final VoidCallback onCancel;

  const ResCancelConfirmV2({
    super.key,
    required this.motoName,
    required this.dateRange,
    required this.pct,
    required this.refundLine,
    required this.loading,
    required this.onReason,
    required this.onKeep,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final (Color bg, Color border, Color fg) = pct == 100
        ? (MgColors.tintOk, MgColors.tintOkBorder, MgColors.onTintOk)
        : pct == 50
            ? (MgColors.warnBg, MgColors.warnBorder, MgColors.warn)
            : (MgColors.errBg, MgColors.errBorder, MgColors.err);
    return MgDialogFrame(
      title: tr.tr('cancelReservationQ'),
      content: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(motoName, style: MgType.body.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
        Text(dateRange, style: MgType.tab(MgType.small.copyWith(color: MgColors.lead))),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr.tr('stornoConditions'), style: MgType.small.copyWith(fontWeight: FontWeight.w800, color: MgColors.ink)),
            const SizedBox(height: 2),
            Text(tr.tr('stornoRules'), style: MgType.meta.copyWith(color: MgColors.body2)),
            const SizedBox(height: 6),
            Text(refundLine, style: MgType.tab(MgType.body.copyWith(fontWeight: FontWeight.w800, color: fg))),
          ]),
        ),
        const SizedBox(height: 12),
        TextField(
          enabled: !loading,
          maxLines: 2,
          onChanged: onReason,
          style: MgType.body.copyWith(color: MgColors.ink),
          decoration: mgInputDecoration(context, hint: tr.tr('cancelReasonHint')),
        ),
      ]),
      safe: MgBtnGhostLight(label: t(context).back, onTap: loading ? null : onKeep),
      action: MgBtnDestructive(label: tr.tr('cancelReservationBtn'), onTap: loading ? null : onCancel, busy: loading),
      safeLabel: t(context).back,
      actionLabel: tr.tr('cancelReservationBtn'),
    );
  }
}

/// T1-style result inside the same dialog (`cancelResultDialog`): done /
/// already cancelled = ✓, failure = ✕ with the SAME text and the SAME
/// retry rule. [title] / [body] are the strings the old function chose.
class ResCancelResultV2 extends StatelessWidget {
  final bool ok;
  final String title;
  final String body;
  final String closeLabel;
  final VoidCallback onClose;
  final VoidCallback? onRetry;

  const ResCancelResultV2({
    super.key,
    required this.ok,
    required this.title,
    required this.body,
    required this.closeLabel,
    required this.onClose,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return MgDialogFrame(
      content: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        MgToneDisc(tone: ok ? MgTone.ok : MgTone.err, size: 64, icon: ok ? MgIcons.check : MgIcons.close),
        const SizedBox(height: 14),
        Semantics(
          header: true,
          child: Text(title, textAlign: TextAlign.center, style: MgType.h3.copyWith(color: MgColors.ink)),
        ),
        const SizedBox(height: 8),
        Text(body, textAlign: TextAlign.center, style: MgType.body.copyWith(color: MgColors.body2)),
      ]),
      safe: onRetry == null ? null : MgBtnGhostLight(label: closeLabel, onTap: onClose),
      action: onRetry == null ? MgBtnInk(label: closeLabel, onTap: onClose) : MgBtnInk(label: tr.tr('retry'), onTap: onRetry),
      safeLabel: onRetry == null ? null : closeLabel,
      actionLabel: onRetry == null ? closeLabel : tr.tr('retry'),
    );
  }
}
