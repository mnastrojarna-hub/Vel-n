import '../../core/supabase_client.dart';

/// Email service — mirrors send-booking-email + send-cancellation-email
/// edge function calls from the original app.
/// Sends branded HTML emails for booking events.
class EmailService {
  EmailService._();

  /// Send booking confirmation email (reserved status).
  /// Mirrors send-booking-email with slug 'booking_reserved'.
  static Future<void> sendBookingReserved(String bookingId) async {
    await _sendBookingEmail(bookingId, 'booking_reserved');
  }

  /// Send booking completed email.
  static Future<void> sendBookingCompleted(String bookingId) async {
    await _sendBookingEmail(bookingId, 'booking_completed');
  }

  /// Send booking modified email.
  static Future<void> sendBookingModified(String bookingId) async {
    await _sendBookingEmail(bookingId, 'booking_modified');
  }

  /// Send voucher purchased email with codes.
  static Future<void> sendVoucherPurchased(String orderId) async {
    try {
      await MotoGoSupabase.client.functions.invoke('send-booking-email', body: {
        'order_id': orderId,
        'slug': 'voucher_purchased',
        'source': 'app',
      });
    } catch (_) {}
  }

  /// Send cancellation email with restore CTA.
  static Future<void> sendCancellationEmail(String bookingId) async {
    try {
      await MotoGoSupabase.client.functions.invoke('send-cancellation-email', body: {
        'booking_id': bookingId,
        'source': 'app',
      });
    } catch (_) {}
  }

  static Future<void> _sendBookingEmail(String bookingId, String slug) async {
    try {
      await MotoGoSupabase.client.functions.invoke('send-booking-email', body: {
        'booking_id': bookingId,
        'slug': slug,
        'source': 'app',
      });
    } catch (_) {}
  }
}
