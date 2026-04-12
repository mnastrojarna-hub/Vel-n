import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Color;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;

import '../../core/auth_guard.dart';
import '../../core/supabase_client.dart';

/// Stripe payment service — native Payment Sheet (in-app, no redirect).
///
/// Flutter uses mode: 'intent'. Edge function returns client_secret,
/// customer_id, and ephemeral_key for full Payment Sheet support
/// (including saved cards).
class StripeService {
  StripeService._();

  /// Create PaymentIntent via process-payment edge function (mode: intent).
  /// Returns client_secret + customer data for Stripe Payment Sheet.
  static Future<PaymentResult> createPaymentIntent({
    String? bookingId,
    required int amount,
    String method = 'card',
    String type = 'booking',
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
        'mode': 'intent',
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
        await handleAuthError(Exception('401'));
        return PaymentResult.error('Platnost přihlášení vypršela');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (data['success'] == true && data['free'] == true) {
        return PaymentResult.free(bookingId: bookingId);
      }

      if (data['success'] == true && data['client_secret'] != null) {
        return PaymentResult.intent(
          clientSecret: data['client_secret'] as String,
          paymentIntentId: data['payment_intent_id'] as String?,
          customerId: data['customer_id'] as String?,
          ephemeralKey: data['ephemeral_key'] as String?,
          bookingId: bookingId,
        );
      }

      return PaymentResult.error(
        data['error'] as String? ??
            'Platba selhala (HTTP ${response.statusCode})',
      );
    } on TimeoutException {
      return PaymentResult.error('Platba vypršela — zkuste znovu');
    } catch (e) {
      return PaymentResult.error('Chyba platby: $e');
    }
  }

  /// Present Stripe Payment Sheet natively inside the app.
  /// Supports saved cards when customerId + ephemeralKey are provided.
  static Future<bool> presentPaymentSheet({
    required String clientSecret,
    String? customerId,
    String? ephemeralKey,
  }) async {
    try {
      final params = SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        merchantDisplayName: 'MotoGo24',
        style: ThemeMode.light,
        appearance: const PaymentSheetAppearance(
          colors: PaymentSheetAppearanceColors(
            primary: Color(0xFF74FB71),
            background: Color(0xFFFFFFFF),
            componentBackground: Color(0xFFF1FAF7),
            componentBorder: Color(0xFFD4E8E0),
          ),
          shapes: PaymentSheetShape(
            borderRadius: 12,
            shadow: PaymentSheetShadowParams(color: Color(0x1A0F1A14)),
          ),
        ),
        // Enable saved cards when customer data is available
        customerId: customerId,
        customerEphemeralKeySecret: ephemeralKey,
      );

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: params,
      );

      await Stripe.instance.presentPaymentSheet();
      return true;
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) {
        return false;
      }
      rethrow;
    }
  }

  /// Poll booking payment status after payment.
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
  static Future<PaymentResult> confirmFreeBooking(String bookingId) async {
    return createPaymentIntent(
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
  final String? clientSecret;
  final String? paymentIntentId;
  final String? customerId;
  final String? ephemeralKey;
  final String? errorMessage;
  final String? bookingId;

  const PaymentResult._({
    required this.type,
    this.clientSecret,
    this.paymentIntentId,
    this.customerId,
    this.ephemeralKey,
    this.errorMessage,
    this.bookingId,
  });

  factory PaymentResult.intent({
    required String clientSecret,
    String? paymentIntentId,
    String? customerId,
    String? ephemeralKey,
    String? bookingId,
  }) =>
      PaymentResult._(
        type: PaymentResultType.intent,
        clientSecret: clientSecret,
        paymentIntentId: paymentIntentId,
        customerId: customerId,
        ephemeralKey: ephemeralKey,
        bookingId: bookingId,
      );

  factory PaymentResult.free({String? bookingId}) =>
      PaymentResult._(type: PaymentResultType.free, bookingId: bookingId);

  factory PaymentResult.error(String message) =>
      PaymentResult._(type: PaymentResultType.error, errorMessage: message);

  bool get isSuccess =>
      type == PaymentResultType.intent || type == PaymentResultType.free;
}

enum PaymentResultType { intent, free, error }
