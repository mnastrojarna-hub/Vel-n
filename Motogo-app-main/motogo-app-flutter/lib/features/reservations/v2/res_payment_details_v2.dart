import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/tokens/mg_type.dart';
import '../../../core/v2/widgets/mg_toast.dart';
import '../../../core/v2/widgets/mg_word_fit.dart';
import '../../documents/document_models.dart';
import '../../documents/invoices_screen.dart' show InvoiceTile;
import '../../payment/card_minimum.dart' show kcExact;
import '../reservation_models.dart';
import '../widgets/res_payment_details_tab.dart' show PaymentDetails;
import 'res_fit_v2.dart';

/// v2 look of `ResPaymentDetailsTab` ("Platební údaje" inside Peníze). The
/// tab keeps the fetch (`paymentDetailsProvider`) and every derived value;
/// this draws the SAME rows under the SAME conditions, long IDs copy on tap
/// (as today), payment documents via the existing `InvoiceTile`.
class ResPaymentDetailsV2 extends StatelessWidget {
  final Reservation res;
  final PaymentDetails? d;
  final String statusLabel;
  final String methodLabel;
  final String? card;
  final String? paidAt;
  final String? stripeTx;
  final double refunded;
  final double surcharge;
  final bool loading;

  const ResPaymentDetailsV2({
    super.key,
    required this.res,
    required this.d,
    required this.statusLabel,
    required this.methodLabel,
    required this.card,
    required this.paidAt,
    required this.stripeTx,
    required this.refunded,
    required this.surcharge,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final tr = t(context).tr;
    final d = this.d;
    final rounding = d?.n('card_rounding') ?? 0;
    final rows = <Widget>[
      _row(tr('reservationNumber'), res.shortId),
      _row(tr('paymentStatusLabel'), statusLabel, color: res.paymentStatus == 'paid' ? MgColors.link : null),
      _row(tr('totalAmount'), Money.czk(res.totalPrice), bold: true),
      if (d != null && rounding != 0)
        _row(tr(rounding > 0 ? 'pdMinCardLine' : 'pdWaiveLine'), '${rounding > 0 ? '+' : ''}${kcExact(rounding)}'),
      if (refunded > 0) _row(tr('payRefunded'), Money.czk(refunded), color: MgColors.link),
      if (surcharge > 0) _row(tr('paySurchargeDue'), Money.czk(surcharge), bold: true, color: MgColors.err),
      _row(tr('paymentMethodLabel'), methodLabel),
      if (card != null) _row(tr('payCard'), card!),
      if (paidAt != null) _row(tr('payPaidAt'), paidAt!),
      if (stripeTx != null) _CopyRowV2(label: tr('payStripeTx'), value: stripeTx!),
      if (d?.s('payment_reference') != null) _CopyRowV2(label: tr('payReference'), value: d!.s('payment_reference')!),
      if (d?.s('payment_vs') != null) _CopyRowV2(label: tr('payVs'), value: d!.s('payment_vs')!),
      if (surcharge > 0 && d?.s('mod_surcharge_vs') != null)
        _CopyRowV2(label: tr('paySurchargeVs'), value: d!.s('mod_surcharge_vs')!),
      if (d?.s('stripe_refund_id') != null) _CopyRowV2(label: tr('payStripeRefund'), value: d!.s('stripe_refund_id')!),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ...rows,
      if (loading)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Center(
            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: MgColors.link)),
          ),
        ),
      if (res.paymentStatus == 'paid' && res.status != 'cancelled')
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: MgColors.tintOk,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MgColors.tintOkBorder.withValues(alpha: 0.5)),
          ),
          child: Row(children: [
            const MgIcon(MgIcons.checkCircle, size: 18, color: MgColors.link),
            const SizedBox(width: 8),
            Expanded(child: Text(tr('paymentProcessed'), style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onTintOk))),
          ]),
        ),
      if (d != null && d.invoices.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text(tr('payDocsTitle').toUpperCase(), style: MgType.eyebrow.copyWith(color: MgColors.link)),
        const SizedBox(height: 8),
        ...d.invoices.map((UserInvoice i) => InvoiceTile(invoice: i)),
      ],
    ]);
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MgColors.line))),
        child: _LabelValue(
          label: label,
          value: Text(value,
              textAlign: TextAlign.right,
              style: MgType.tab(MgType.small.copyWith(
                  fontWeight: bold ? FontWeight.w900 : FontWeight.w700, color: color ?? MgColors.ink))),
          valueText: value,
          valueStyle: MgType.small.copyWith(fontWeight: bold ? FontWeight.w900 : FontWeight.w700),
        ),
      );
}

/// Label vlevo a hodnota vpravo v jednom řádku, jen když se popisek vejde
/// celými slovy (de „Reservierungsnummer", „Zahlungsmethode" na 320 dp s
/// velkým písmem) — jinak hodnota pod popiskem (nikdy přetečení ani slovo
/// rozdělené uprostřed).
class _LabelValue extends StatelessWidget {
  final String label;
  final Widget value;
  final String valueText;
  final TextStyle valueStyle;
  final double trailing;
  const _LabelValue({
    required this.label,
    required this.value,
    required this.valueText,
    required this.valueStyle,
    this.trailing = 0,
  });

  static final _labelStyle = MgType.small.copyWith(color: MgColors.lead);

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final labelText = MgWordFit(minScale: 0.85, child: Text(label, style: _labelStyle));
        final valueW = resLineWidth(context, valueText, valueStyle);
        // Hodnota dostane, co potřebuje (max. 60 %), popisek zbytek.
        final valueSlot = valueW.clamp(0.0, c.maxWidth * 0.6) + trailing;
        final inline = resWordsFit(context, label, _labelStyle, c.maxWidth - 12 - valueSlot, minScale: 0.85);
        if (inline) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: labelText),
            const SizedBox(width: 12),
            ConstrainedBox(constraints: BoxConstraints(maxWidth: valueSlot), child: value),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          labelText,
          const SizedBox(height: 2),
          Align(alignment: AlignmentDirectional.centerEnd, child: value),
        ]);
      });
}

/// Long ID row — tap copies it (same as today's `_CopyRow`).
class _CopyRowV2 extends StatelessWidget {
  final String label;
  final String value;
  const _CopyRowV2({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label $value',
      excludeSemantics: true,
      child: MgPress(
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: value));
          if (!context.mounted) return;
          showMgToast(context, '$label · ${t(context).tr('copiedToClipboard')}', icon: MgIcons.copy);
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MgColors.line))),
          child: _LabelValue(
            label: label,
            valueText: value,
            valueStyle: MgType.small.copyWith(fontWeight: FontWeight.w700),
            trailing: 22,
            value: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text(value,
                    textAlign: TextAlign.right,
                    style: MgType.tab(MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.ink))),
              ),
              const SizedBox(width: 6),
              const MgIcon(MgIcons.copy, size: 16, color: MgColors.meta),
            ]),
          ),
        ),
      ),
    );
  }
}
