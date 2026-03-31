import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../core/supabase_client.dart';

/// Stripe payment service — mirrors process-payment edge function calls
/// from api-bookings.js + stripe-inline.js.
///
/// Flutter uses Stripe Checkout redirect exclusively (no inline card form).
/// The process-payment edge function creates a Checkout Session.
class StripeService {
  StripeService._();

  /// Create Stripe Checkout Session via process-payment edge function.
  /// Returns checkout URL or error.
  ///
  /// Mirrors apiProcessPayment() from api-bookings.js.
  static Future<PaymentResult> createCheckoutSession({
    String? bookingId,
    required int amount,
    String method = 'card',
    String type = 'booking', // booking, extension, shop, incident
    String? orderId,
    String? incidentId,
  }) async {
    try {
      final session = MotoGoSupabase.currentSession;
      if (session == null) {
        return PaymentResult.error('Přihlášení vypršelo');
      }

      final body = <String, dynamic>{
        'amount': amount,
        'method': method,
        'type': type,
        'mode': 'checkout', // Flutter always uses checkout redirect
      };
      if (bookingId != null) body['booking_id'] = bookingId;
      if (orderId != null) body['order_id'] = orderId;
      if (incidentId != null) body['incident_id'] = incidentId;

      final response = await http.post(
        Uri.parse('${MotoGoSupabase.url}/functions/v1/process-payment'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}',
          'apikey': MotoGoSupabase.anonKey,
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 401) {
        return PaymentResult.error('Platnost přihlášení vypršela');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (data['success'] == true && data['free'] == true) {
        return PaymentResult.free(bookingId: bookingId);
      }

      if (data['success'] == true && data['checkout_url'] != null) {
        return PaymentResult.checkoutUrl(
          data['checkout_url'] as String,
          bookingId: bookingId,
        );
      }

      return PaymentResult.error(
        data['error'] as String? ?? 'Platba selhala (HTTP ${response.statusCode})',
      );
    } on TimeoutException {
      return PaymentResult.error('Platba vypršela — zkuste znovu');
    } catch (e) {
      return PaymentResult.error('Chyba platby: $e');
    }
  }

  /// Open Stripe Checkout URL in system browser.
  /// Mirrors _openExternalUrl() from native-bridge.js.
  static Future<bool> openCheckout(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  /// Poll booking payment status after Stripe redirect.
  /// Mirrors _checkPaymentAfterStripe() from payment-ui.js.
  /// Returns true if paid, false if still unpaid after maxAttempts.
  static Future<bool> pollBookingPaymentStatus(
    String bookingId, {
    int maxAttempts = 5,
    Duration interval = const Duration(seconds: 2),
  }) async {
    for (var i = 0; i < maxAttempts; i++) {
      try {
        final res = await MotoGoSupabase.client
            .from('bookings')
            .select('status, payment_status')
            .eq('id', bookingId)
            .single();

        if (res['payment_status'] == 'paid') return true;
        if (res['status'] == 'cancelled') return false;
      } catch (_) {}

      if (i < maxAttempts - 1) {
        await Future.delayed(interval);
      }
    }
    return false;
  }

  /// Poll shop order payment status.
  static Future<bool> pollOrderPaymentStatus(
    String orderId, {
    int maxAttempts = 5,
    Duration interval = const Duration(seconds: 2),
  }) async {
    for (var i = 0; i < maxAttempts; i++) {
      try {
        final res = await MotoGoSupabase.client
            .from('shop_orders')
            .select('payment_status')
            .eq('id', orderId)
            .single();

        if (res['payment_status'] == 'paid') return true;
      } catch (_) {}

      if (i < maxAttempts - 1) {
        await Future.delayed(interval);
      }
    }
    return false;
  }

  /// Confirm free booking (100% discount).
  /// Mirrors _confirmFreeBooking() from payment-ui-2.js.
  static Future<PaymentResult> confirmFreeBooking(String bookingId) async {
    return createCheckoutSession(
      bookingId: bookingId,
      amount: 0,
      method: 'free',
      type: 'booking',
    );
  }
}

/// Payment operation result.
class PaymentResult {
  final PaymentResultType type;
  final String? checkoutUrl;
  final String? errorMessage;
  final String? bookingId;

  const PaymentResult._({
    required this.type,
    this.checkoutUrl,
    this.errorMessage,
    this.bookingId,
  });

  factory PaymentResult.checkoutUrl(String url, {String? bookingId}) =>
      PaymentResult._(
        type: PaymentResultType.checkout,
        checkoutUrl: url,
        bookingId: bookingId,
      );

  factory PaymentResult.free({String? bookingId}) =>
      PaymentResult._(type: PaymentResultType.free, bookingId: bookingId);

  factory PaymentResult.error(String message) =>
      PaymentResult._(type: PaymentResultType.error, errorMessage: message);

  bool get isSuccess =>
      type == PaymentResultType.checkout || type == PaymentResultType.free;
}

enum PaymentResultType { checkout, free, error }
