import '../../core/i18n/app_lang.dart';
import '../../core/i18n/i18n_provider.dart' show lastKnownAppLang;
import '../../core/supabase_client.dart';

/// Invoice generation service — mirrors generate-invoice + generate-document
/// edge function calls from api-invoices.js.
/// Generates proforma (ZF), payment receipt (DP), final invoice (KF).
class InvoiceService {
  InvoiceService._();

  /// Generate advance/proforma invoice (ZF) — called after booking creation.
  static Future<void> generateAdvanceInvoice(
    String bookingId,
    double amount, [
    String source = 'booking',
  ]) async {
    try {
      await MotoGoSupabase.client.functions.invoke('generate-invoice', body: {
        'booking_id': bookingId,
        'type': 'advance',
        'amount': amount,
        'source': source,
        'send_email': false,
      });
    } catch (_) {}
  }

  /// Generate payment receipt (DP) — called after successful payment.
  static Future<void> generatePaymentReceipt(
    String bookingId,
    double amount, [
    String source = 'booking',
  ]) async {
    try {
      await MotoGoSupabase.client.functions.invoke('generate-invoice', body: {
        'booking_id': bookingId,
        'type': 'payment_receipt',
        'amount': amount,
        'source': source,
      });
    } catch (_) {}
  }

  /// Smlouva + VOP k rezervaci v JAZYCE REZERVACE (`bookings.language`).
  /// Edge `generate-document` bere jeden dokument na volání
  /// ({template_slug, booking_id, language}) — dřívější `{types: [...]}` vracel
  /// 400 a dokumenty nevznikaly. Předávací protokol se z šablony negeneruje
  /// (jen reálně podepsaný elektronický — zadání majitele 2026-09-29).
  static Future<void> generateBookingDocs(String bookingId, {String? fallbackLang}) async {
    var lang = normalizeAppLang(fallbackLang ?? lastKnownAppLang);
    try {
      final row = await MotoGoSupabase.client
          .from('bookings')
          .select('language')
          .eq('id', bookingId)
          .maybeSingle();
      final l = row?['language'] as String?;
      if (l != null && l.isNotEmpty) lang = normalizeAppLang(l);
    } catch (_) {/* jazyk appky */}
    for (final slug in const ['rental_contract', 'vop']) {
      try {
        await MotoGoSupabase.client.functions.invoke('generate-document', body: {
          'template_slug': slug,
          'booking_id': bookingId,
          'language': lang,
        });
      } catch (_) {}
    }
  }

  /// Generate cancellation receipt with refund info.
  static Future<void> generateCancellationReceipt(
    String bookingId,
    int refundPercent,
    double refundAmount,
  ) async {
    try {
      await MotoGoSupabase.client.functions.invoke('generate-invoice', body: {
        'booking_id': bookingId,
        'type': 'cancellation_receipt',
        'refund_percent': refundPercent,
        'refund_amount': refundAmount,
      });
    } catch (_) {}
  }

  /// Generate shop proforma invoice.
  static Future<void> generateShopProforma(String orderId) async {
    try {
      await MotoGoSupabase.client.functions.invoke('generate-invoice', body: {
        'order_id': orderId,
        'type': 'shop_proforma',
        'send_email': false,
      });
    } catch (_) {}
  }

  /// Generate shop payment receipt.
  static Future<void> generateShopReceipt(String orderId) async {
    try {
      await MotoGoSupabase.client.functions.invoke('generate-invoice', body: {
        'order_id': orderId,
        'type': 'payment_receipt',
      });
    } catch (_) {}
  }

  /// Log promo code usage after successful payment.
  /// Mirrors apiUsePromoCode() from cart-booking-price.js.
  static Future<void> usePromoCode(
    String code,
    String bookingId,
    double baseAmount,
  ) async {
    try {
      await MotoGoSupabase.client.rpc('use_promo_code', params: {
        'p_code': code,
        'p_booking_id': bookingId,
        'p_base_amount': baseAmount,
      });
    } catch (_) {}
  }
}
