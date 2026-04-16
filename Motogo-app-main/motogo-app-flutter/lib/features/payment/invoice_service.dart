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

  /// Generate booking documents (contract + VOP + handover protocol).
  static Future<void> generateBookingDocs(
    String bookingId, [
    bool regenerate = false,
  ]) async {
    try {
      await MotoGoSupabase.client.functions.invoke('generate-document', body: {
        'booking_id': bookingId,
        'types': ['rental_contract', 'vop', 'handover_protocol'],
        'regenerate': regenerate,
      });
    } catch (_) {}
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
