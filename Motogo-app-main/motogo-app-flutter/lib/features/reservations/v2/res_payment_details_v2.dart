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
    final rows = <_PayRow>[
      _PayRow(tr('reservationNumber'), res.shortId),
      _PayRow(tr('paymentStatusLabel'), statusLabel, color: res.paymentStatus == 'paid' ? MgColors.link : null),
      _PayRow(tr('totalAmount'), Money.czk(res.totalPrice), bold: true),
      if (d != null && rounding != 0)
        _PayRow(tr(rounding > 0 ? 'pdMinCardLine' : 'pdWaiveLine'), '${rounding > 0 ? '+' : ''}${kcExact(rounding)}'),
      if (refunded > 0) _PayRow(tr('payRefunded'), Money.czk(refunded), color: MgColors.link),
      if (surcharge > 0) _PayRow(tr('paySurchargeDue'), Money.czk(surcharge), bold: true, color: MgColors.err),
      _PayRow(tr('paymentMethodLabel'), methodLabel),
      if (card != null) _PayRow(tr('payCard'), card!),
      if (paidAt != null) _PayRow(tr('payPaidAt'), paidAt!),
      if (stripeTx != null) _PayRow(tr('payStripeTx'), stripeTx!, copy: true),
      if (d?.s('payment_reference') != null) _PayRow(tr('payReference'), d!.s('payment_reference')!, copy: true),
      if (d?.s('payment_vs') != null) _PayRow(tr('payVs'), d!.s('payment_vs')!, copy: true),
      if (surcharge > 0 && d?.s('mod_surcharge_vs') != null)
        _PayRow(tr('paySurchargeVs'), d!.s('mod_surcharge_vs')!, copy: true),
      if (d?.s('stripe_refund_id') != null) _PayRow(tr('payStripeRefund'), d!.s('stripe_refund_id')!, copy: true),
    ];
    // Všechny řádky stejně: hodnota vpravo vedle popisku, jen když se do
    // řádku vejdou celými slovy všechny popisky (de „Reservierungsnummer"
    // na 320 dp s velkým písmem) — jinak u všech hodnota pod popiskem.
    final table = LayoutBuilder(builder: (context, c) {
      final stacked = rows.any((r) => !_LabelValue.fits(context, r, c.maxWidth));
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final r in rows)
          r.copy ? _CopyRowV2(row: r, stacked: stacked, maxWidth: c.maxWidth) : _row(r, stacked, c.maxWidth),
      ]);
    });
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      table,
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

  Widget _row(_PayRow r, bool stacked, double maxWidth) => Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: MgColors.line))),
        child: _LabelValue(
          label: r.label,
          stacked: stacked,
          valueMax: maxWidth * 0.6 + r.trailing,
          value: Text(r.value, textAlign: TextAlign.right, style: r.valueStyle.copyWith(color: r.color ?? MgColors.ink)),
        ),
      );
}

/// One "Platební údaje" line: label, value (bold / colour as today) and
/// whether a tap copies it (long IDs).
class _PayRow {
  final String label;
  final String value;
  final bool bold;
  final Color? color;
  final bool copy;
  const _PayRow(this.label, this.value, {this.bold = false, this.color, this.copy = false});

  TextStyle get valueStyle => MgType.tab(MgType.small.copyWith(fontWeight: bold ? FontWeight.w900 : FontWeight.w700));

  /// Copy icon + gap after the value.
  double get trailing => copy ? 22 : 0;
}

/// Label on the left, value on the right ([stacked] = value under the label).
class _LabelValue extends StatelessWidget {
  final String label;
  final Widget value;
  final bool stacked;

  /// Widest the value may get on one line with the label (60 % + icon).
  final double valueMax;
  const _LabelValue({required this.label, required this.value, required this.stacked, required this.valueMax});

  static final _labelStyle = MgType.small.copyWith(color: MgColors.lead);

  /// true when [r] fits one line of [width] with every word whole: the
  /// value gets what it needs (at most 60 %), the label the rest.
  static bool fits(BuildContext context, _PayRow r, double width) {
    final slot = (resLineWidth(context, r.value, r.valueStyle) + 1).clamp(0.0, width * 0.6) + r.trailing;
    return resWordsFit(context, r.label, _labelStyle, width - 12 - slot, minScale: 0.85);
  }

  @override
  Widget build(BuildContext context) {
    final labelText = MgWordFit(minScale: 0.85, child: Text(label, style: _labelStyle));
    if (!stacked) {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: labelText),
        const SizedBox(width: 12),
        ConstrainedBox(constraints: BoxConstraints(maxWidth: valueMax), child: value),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      labelText,
      const SizedBox(height: 2),
      Align(alignment: AlignmentDirectional.centerEnd, child: value),
    ]);
  }
}

/// Long ID row — tap copies it (same as today's `_CopyRow`).
class _CopyRowV2 extends StatelessWidget {
  final _PayRow row;
  final bool stacked;
  final double maxWidth;
  const _CopyRowV2({required this.row, required this.stacked, required this.maxWidth});

  String get label => row.label;
  String get value => row.value;

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
            stacked: stacked,
            valueMax: maxWidth * 0.6 + row.trailing,
            value: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text(value, textAlign: TextAlign.right, style: row.valueStyle.copyWith(color: MgColors.ink)),
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
