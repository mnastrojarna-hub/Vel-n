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

  /// Smlouva + VOP k rezervaci — jen JAKO ZÁLOHA. Primárně je generuje
  /// `send-booking-email` (přílohy booking_reserved / booking_modified dle
  /// Velínu) v jazyce zákazníka. Souběžné volání z appky by vyrobilo druhou
  /// verzi (duplicitní řádek v Dokumentech, PDF navíc) a mohlo smazat soubor
  /// přílohy e-mailu (generate-document maže starší verze téhož typu). Appka
  /// proto počká, až e-mail doběhne, a vygeneruje jen dokument, který k
  /// rezervaci pořád chybí. Jazyk určí edge (`detect_customer_language`,
  /// zákazník smí jen jazyk rezervace). Předávací protokol se z šablony
  /// negeneruje (jen reálně podepsaný — zadání majitele 2026-09-29).
  /// Dřívější `{types: [...]}` vracel 400 a nikdy nic nevyrobil.
  static Future<void> generateBookingDocs(String bookingId) async {
    await Future.delayed(const Duration(seconds: 45));
    final client = MotoGoSupabase.client;
    final have = <String>{};
    var lang = normalizeAppLang(lastKnownAppLang);
    try {
      final row = await client
          .from('bookings')
          .select('language')
          .eq('id', bookingId)
          .maybeSingle();
      final l = row?['language'] as String?;
      if (l != null && l.isNotEmpty) lang = normalizeAppLang(l);
      final gen = await client
          .from('generated_documents')
          .select('template_id')
          .eq('booking_id', bookingId);
      final ids = (gen as List)
          .map((r) => (r as Map)['template_id'])
          .whereType<String>()
          .toSet();
      if (ids.isNotEmpty) {
        final tpls = await client
            .from('document_templates')
            .select('id, type')
            .inFilter('id', ids.toList());
        for (final r in (tpls as List)) {
          final ty = (r as Map)['type'];
          if (ty is String) have.add(ty);
        }
      }
    } catch (_) {
      return; // stav nejde ověřit → raději nic (žádná duplicita)
    }
    for (final slug in const ['rental_contract', 'vop']) {
      if (have.contains(slug)) continue;
      try {
        await client.functions.invoke('generate-document', body: {
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
