import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/currency.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/supabase_client.dart';
import '../../../core/theme.dart';
import '../../auth/widgets/toast_helper.dart';
import '../../documents/document_models.dart';
import '../../documents/invoices_screen.dart' show InvoiceTile;
import '../reservation_models.dart';
import 'res_detail_card.dart';
import 'res_detail_row.dart';

/// Platební údaje rezervace — vlastní řádek `bookings` (RLS vlastníka, `*`,
/// ať chybějící sloupec nerozbije dotaz) + doklady z `invoices` (i vratky =
/// dobropisy a datum platby u starších rezervací bez `confirmed_at`). Kartu
/// (`card_brand`/`card_last4`) a `stripe_payment_intent_id` plní
/// webhook-receiver po `payment_intent.succeeded` (u doplatku přepíše na
/// poslední platbu), ruční platby Velín (`payment_method`, `payment_reference`,
/// `payment_vs`). Backend beze změny.
class PaymentDetails {
  final Map<String, dynamic> booking;
  final List<UserInvoice> invoices;
  const PaymentDetails(this.booking, this.invoices);

  String? s(String key) {
    final v = booking[key];
    return v is String && v.trim().isNotEmpty ? v.trim() : null;
  }

  double n(String key) => (booking[key] as num?)?.toDouble() ?? 0;
}

final paymentDetailsProvider =
    FutureProvider.autoDispose.family<PaymentDetails, String>((ref, bookingId) async {
  final b = await MotoGoSupabase.client.from('bookings').select().eq('id', bookingId).maybeSingle();
  var invoices = const <UserInvoice>[];
  try {
    final rows = await MotoGoSupabase.client
        .from('invoices')
        .select()
        .eq('booking_id', bookingId)
        .order('created_at', ascending: true);
    invoices = (rows as List)
        .map((e) => UserInvoice.fromJson(e as Map<String, dynamic>))
        .where((i) => i.status != 'draft' && i.status != 'cancelled')
        .toList();
  } catch (e) {
    debugPrint('[PAYMENT_DETAILS] invoices fetch failed: $e');
  }
  return PaymentDetails(b ?? const {}, invoices);
});

/// Záložka „Podrobnosti o platbě“ v detailu rezervace (dřív „Platební karta“
/// jen se „Stripe“ — zadání majitele 2026-09-29: chyběla transakce, karta…).
class ResPaymentDetailsTab extends ConsumerWidget {
  final Reservation res;
  const ResPaymentDetailsTab({super.key, required this.res});

  static const _paidStates = {'paid', 'partial_refund', 'refund_pending', 'refunded'};
  static const _manualMethods = {'bank_transfer', 'wire', 'qr', 'cash', 'crypto', 'voucher'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context).tr;
    final async = ref.watch(paymentDetailsProvider(res.id));
    final d = async.valueOrNull;
    final paid = _paidStates.contains(res.paymentStatus);
    final manual = _manualMethods.contains(d?.s('payment_method')?.toLowerCase());
    final card = d == null || manual ? null : _cardLabel(d.s('card_brand'), d.s('card_last4'));
    // `stripe_payment_intent_id` se přepisuje i nedokončeným pokusem (doplatek,
    // opakovaná platba) → číslo transakce jen u zaplacené karetní platby.
    final stripeTx = paid && !manual ? d?.s('stripe_payment_intent_id') : null;
    // Vratky: `bookings` sloupec částky nemá (živá DB) → součet dobropisů.
    double refunded = 0;
    DateTime? paidAt = paid ? res.confirmedAt : null;
    for (final i in d?.invoices ?? const <UserInvoice>[]) {
      if (i.isCreditNote) refunded += (i.total ?? 0).abs();
      // `confirmed_at` starších rezervací chybí → datum dokladu k přijaté platbě.
      if (paid && paidAt == null && i.type == 'payment_receipt') paidAt = i.issuedAt ?? i.createdAt;
    }
    final surcharge = d != null && d.s('mod_surcharge_paid_at') == null ? d.n('mod_surcharge_due') : 0.0;

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList.list(
        children: [
          ResDetailCard(children: [
            Text(tr('paymentDetailsTab'),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: MotoGoColors.black)),
            const SizedBox(height: 12),
            ResDetailRow(label: tr('reservationNumber'), value: res.shortId),
            ResDetailRow(
              label: tr('paymentStatusLabel'),
              value: _statusLabel(tr, res.paymentStatus, res.status),
              valueColor: res.paymentStatus == 'paid' ? MotoGoColors.greenDarker : null,
            ),
            ResDetailRow(label: tr('totalAmount'), value: Money.czk(res.totalPrice), bold: true),
            if (refunded > 0)
              ResDetailRow(label: tr('payRefunded'), value: Money.czk(refunded), valueColor: MotoGoColors.greenDarker),
            if (surcharge > 0)
              ResDetailRow(label: tr('paySurchargeDue'), value: Money.czk(surcharge), bold: true, valueColor: MotoGoColors.red),
            ResDetailRow(label: tr('paymentMethodLabel'), value: _methodLabel(tr, d, paid)),
            if (card != null) ResDetailRow(label: tr('payCard'), value: card),
            if (paidAt != null) ResDetailRow(label: tr('payPaidAt'), value: _fmtDateTime(paidAt.toLocal())),
            if (stripeTx != null) _CopyRow(label: tr('payStripeTx'), value: stripeTx),
            if (d?.s('payment_reference') != null)
              _CopyRow(label: tr('payReference'), value: d!.s('payment_reference')!),
            if (d?.s('payment_vs') != null) _CopyRow(label: tr('payVs'), value: d!.s('payment_vs')!),
            if (surcharge > 0 && d?.s('mod_surcharge_vs') != null)
              _CopyRow(label: tr('paySurchargeVs'), value: d!.s('mod_surcharge_vs')!),
            if (d?.s('stripe_refund_id') != null)
              _CopyRow(label: tr('payStripeRefund'), value: d!.s('stripe_refund_id')!),
            if (async.isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Center(
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: MotoGoColors.green)),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          if (res.paymentStatus == 'paid' && res.status != 'cancelled')
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: MotoGoColors.greenPale,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MotoGoColors.green.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle, size: 18, color: MotoGoColors.greenDark),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tr('paymentProcessed'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MotoGoColors.greenDarker)),
                ),
              ]),
            ),
          if (d != null && d.invoices.isNotEmpty) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(tr('payDocsTitle'),
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: MotoGoColors.g400, letterSpacing: 0.5)),
            ),
            ...d.invoices.map((i) => InvoiceTile(invoice: i)),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  /// Stav platby jako Velín `paymentStatusInfo`: zaplacená + zrušená rezervace
  /// = „Čeká na vrácení“ (Stripe vratku ještě nepotvrdil).
  static String _statusLabel(String Function(String) tr, String status, String bookingStatus) => switch (status) {
        'paid' when bookingStatus == 'cancelled' => tr('payStatusRefundPending'),
        'paid' => tr('paid'),
        'refunded' => tr('payStatusRefunded'),
        'partial_refund' => tr('payStatusPartialRefund'),
        'refund_pending' => tr('payStatusRefundPending'),
        _ => tr('payStatusUnpaid'),
      };

  /// Způsob platby — hodnoty `bookings.payment_method` jako Velín
  /// (`PAYMENT_METHOD_LABELS`); Stripe bez metody = karta, 0 Kč = bez platby.
  static String _methodLabel(String Function(String) tr, PaymentDetails? d, bool paid) {
    final m = d?.s('payment_method')?.toLowerCase();
    switch (m) {
      case 'card' || 'stripe':
        return tr('payMethodCard');
      case 'google_pay':
        return 'Google Pay';
      case 'apple_pay':
        return 'Apple Pay';
      case 'klarna':
        return 'Klarna';
      case 'paypal':
        return 'PayPal';
      case 'bank_transfer' || 'wire':
        return tr('payMethodBank');
      case 'qr':
        return tr('payMethodQr');
      case 'cash':
        return tr('payMethodCash');
      case 'crypto':
        return tr('payMethodCrypto');
      case 'voucher':
        return tr('payMethodVoucher');
    }
    if (d?.s('card_last4') != null || d?.s('stripe_payment_intent_id') != null) return tr('payMethodCard');
    if (d?.s('pay_channel') == 'qr') return tr('payMethodQr');
    if (paid && (d?.n('total_price') ?? 1) <= 0) return tr('payMethodFree');
    return m ?? '—';
  }

  /// „Visa •••• 4242“ (Stripe brand: visa, mastercard, amex, …).
  static String? _cardLabel(String? brand, String? last4) {
    if (brand == null && last4 == null) return null;
    final b = switch (brand?.toLowerCase()) {
      'visa' => 'Visa',
      'mastercard' => 'Mastercard',
      'amex' => 'American Express',
      'diners' => 'Diners Club',
      'discover' => 'Discover',
      'jcb' => 'JCB',
      'unionpay' => 'UnionPay',
      null || 'unknown' => '',
      final String other => other[0].toUpperCase() + other.substring(1),
    };
    return [b, if (last4 != null) '•••• $last4'].where((e) => e.isNotEmpty).join(' ');
  }

  static String _fmtDateTime(DateTime d) =>
      '${d.day}. ${d.month}. ${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Řádek s dlouhým ID (transakce, VS) — ťuknutím se zkopíruje do schránky.
class _CopyRow extends StatelessWidget {
  final String label;
  final String value;
  const _CopyRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.g400)),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (!context.mounted) return;
              showMotoGoToast(context, icon: '📋', title: label, message: t(context).tr('copiedToClipboard'));
            },
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Flexible(
                child: Text(value,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: MotoGoColors.black)),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.copy_rounded, size: 14, color: MotoGoColors.g400),
            ]),
          ),
        ),
      ]),
    );
  }
}
