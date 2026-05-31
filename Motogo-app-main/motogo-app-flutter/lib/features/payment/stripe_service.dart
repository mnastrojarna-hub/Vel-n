import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Color;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

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
  /// Když je předán [paymentMethodId], edge fn provede off-session charge a
  /// místo Payment Sheetu se vrátí buď `succeeded`, nebo `requires_action` s
  /// client_secret pro SCA (klient pak volá `handleNextAction`).
  static Future<PaymentResult> createPaymentIntent({
    String? bookingId,
    required int amount,
    String method = 'card',
    String type = 'booking',
    String? orderId,
    String? incidentId,
    String? paymentMethodId,
  }) async {
    try {
      final session = MotoGoSupabase.currentSession;
      if (session == null) {
        return PaymentResult.error(
          'Vaše přihlášení vypršelo. Pro dokončení platby '
          'se prosím znovu přihlaste.',
          code: PaymentErrorCode.authExpired,
        );
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
      if (paymentMethodId != null) body['payment_method_id'] = paymentMethodId;

      final response = await http.post(
        Uri.parse('${MotoGoSupabase.url}/functions/v1/process-payment'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}',
          'apikey': MotoGoSupabase.anonKey,
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 401) {
        await handleAuthError(AuthException('401 from process-payment'));
        return PaymentResult.error(
          'Vaše přihlášení vypršelo. Pro dokončení platby '
          'se prosím znovu přihlaste.',
          code: PaymentErrorCode.authExpired,
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      // Off-session: backend buď strhl rovnou (succeeded), nebo vyžaduje SCA
      // (requires_action s client_secret). Klient v PaymentScreen dotáhne SCA
      // přes Stripe.instance.handleNextAction(clientSecret).
      if (data['off_session'] == true) {
        if (data['success'] == true && data['status'] == 'succeeded') {
          return PaymentResult.offSessionSucceeded(
            paymentIntentId: data['payment_intent_id'] as String?,
            bookingId: bookingId,
          );
        }
        if (data['success'] == true &&
            (data['status'] == 'requires_action' || data['status'] == 'requires_confirmation') &&
            data['client_secret'] != null) {
          return PaymentResult.offSessionRequiresAction(
            clientSecret: data['client_secret'] as String,
            paymentIntentId: data['payment_intent_id'] as String?,
            bookingId: bookingId,
          );
        }
        // Off-session selhal (typicky declined / expired / authentication denied).
        // Vracíme strukturovanou chybu, aby PaymentScreen mohl spadnout do
        // Payment Sheetu se sdělením „Karta selhala, zkuste znovu".
        final msg = (data['message'] as String?) ?? 'Strhnutí uložené karty selhalo.';
        return PaymentResult.offSessionFailed(
          message: msg,
          errorCode: data['error_code'] as String?,
          declineCode: data['decline_code'] as String?,
        );
      }

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

      final serverMsg = data['error'] as String?;
      return PaymentResult.error(
        serverMsg ??
            'Server vrátil neočekávanou odpověď (HTTP ${response.statusCode}). '
                'Zkuste to prosím znovu.',
        code: PaymentErrorCode.serverError,
      );
    } on TimeoutException {
      return PaymentResult.error(
        'Spojení se serverem trvá příliš dlouho. '
        'Zkontrolujte připojení k internetu a zkuste platbu znovu.',
        code: PaymentErrorCode.timeout,
      );
    } catch (e) {
      return PaymentResult.error(
        'Nepodařilo se spojit s platebním serverem. '
        'Zkontrolujte připojení k internetu a zkuste to znovu.',
        code: PaymentErrorCode.networkError,
      );
    }
  }

  /// Present Stripe Payment Sheet natively inside the app.
  /// Supports saved cards when customerId + ephemeralKey are provided.
  static Future<bool> presentPaymentSheet({
    required String clientSecret,
    String? customerId,
    String? ephemeralKey,
  }) async {
    debugPrint('[Stripe] presentPaymentSheet START');
    debugPrint('[Stripe] publishableKey set: ${Stripe.publishableKey.isNotEmpty}');
    debugPrint('[Stripe] urlScheme: "${Stripe.urlScheme}"');
    debugPrint('[Stripe] clientSecret length: ${clientSecret.length}');
    debugPrint('[Stripe] clientSecret prefix: ${clientSecret.substring(0, clientSecret.length.clamp(0, 12))}...');
    debugPrint('[Stripe] customerId: $customerId');
    debugPrint('[Stripe] ephemeralKey: ${ephemeralKey != null ? "${ephemeralKey!.substring(0, ephemeralKey!.length.clamp(0, 8))}..." : "null"}');

    // Step 1: applySettings
    debugPrint('[Stripe] Step 1: applySettings...');
    bool sdkReady = false;
    String? applyError;
    for (var i = 0; i < 2 && !sdkReady; i++) {
      try {
        await Stripe.instance.applySettings();
        sdkReady = true;
        debugPrint('[Stripe] applySettings OK (attempt ${i + 1})');
      } catch (e) {
        applyError = '$e';
        debugPrint('[Stripe] applySettings FAILED (attempt ${i + 1}): $e');
        if (i == 0) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    if (!sdkReady) {
      final msg = 'applySettings selhalo: $applyError';
      debugPrint('[Stripe] ABORT: $msg');
      throw Exception(msg);
    }

    // Only pass customer data when BOTH customerId and ephemeralKey exist
    final useCustomer = customerId != null && ephemeralKey != null;
    debugPrint('[Stripe] useCustomer (saved cards): $useCustomer');

    // Step 2: initPaymentSheet
    debugPrint('[Stripe] Step 2: initPaymentSheet...');
    final params = SetupPaymentSheetParameters(
      paymentIntentClientSecret: clientSecret,
      merchantDisplayName: 'MotoGo24',
      returnURL: 'motogo24://payment',
      style: ThemeMode.light,
      appearance: const PaymentSheetAppearance(
        colors: PaymentSheetAppearanceColors(
          primary: Color(0xFF74FB71),
          background: Color(0xFFFFFFFF),
          componentBackground: Color(0xFFF1FAF7),
          componentBorder: Color(0xFFD4E8E0),
        ),
      ),
      // Google Pay — auto-detected on supported devices
      googlePay: const PaymentSheetGooglePay(
        merchantCountryCode: 'CZ',
        currencyCode: 'CZK',
        // DOČASNĚ true: testovací build pro pořízení screenshotů Google Pay
        // sheetu do žádosti o production access. Po nahrání screenů vrátit na false.
        testEnv: true,
      ),
      // Apple Pay (for future iOS builds)
      applePay: const PaymentSheetApplePay(
        merchantCountryCode: 'CZ',
      ),
      customerId: useCustomer ? customerId : null,
      customerEphemeralKeySecret: useCustomer ? ephemeralKey : null,
    );

    try {
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: params,
      );
      debugPrint('[Stripe] initPaymentSheet OK');
    } catch (e, stack) {
      debugPrint('[Stripe] initPaymentSheet FAILED: $e');
      debugPrint('[Stripe] initPaymentSheet stack: $stack');
      throw Exception('initPaymentSheet: $e');
    }

    // Step 3: presentPaymentSheet
    debugPrint('[Stripe] Step 3: presentPaymentSheet...');
    try {
      await Stripe.instance.presentPaymentSheet();
      debugPrint('[Stripe] presentPaymentSheet OK — payment completed');
      return true;
    } on StripeException catch (e) {
      debugPrint('[Stripe] presentPaymentSheet StripeException: ${e.error.code} / ${e.error.message}');
      if (e.error.code == FailureCode.Canceled) {
        debugPrint('[Stripe] User cancelled');
        return false;
      }
      rethrow;
    } catch (e, stack) {
      debugPrint('[Stripe] presentPaymentSheet FAILED: $e');
      debugPrint('[Stripe] presentPaymentSheet stack: $stack');
      rethrow;
    }
  }

  /// Dokončí SCA (3DS) pro off-session PaymentIntent, který backend založil
  /// s `requires_action`. Volá se z PaymentScreen po PaymentResult.offSessionRequiresAction.
  ///
  /// Vrací true, pokud se intent po SCA dostal na `succeeded` (případně už byl),
  /// false pokud uživatel SCA zrušil nebo selhal.
  static Future<bool> handleNextAction(String clientSecret) async {
    debugPrint('[Stripe] handleNextAction START');
    try {
      await Stripe.instance.applySettings();
    } catch (e) {
      debugPrint('[Stripe] handleNextAction applySettings failed: $e');
      // pokračujeme — handleNextAction často projde i bez explicitního applySettings
    }
    try {
      final result = await Stripe.instance.handleNextAction(clientSecret);
      final status = result.status;
      debugPrint('[Stripe] handleNextAction status: $status');
      // succeeded i requiresCapture (manual capture flow) považujeme za OK
      return status == PaymentIntentsStatus.Succeeded ||
          status == PaymentIntentsStatus.RequiresCapture;
    } on StripeException catch (e) {
      debugPrint('[Stripe] handleNextAction StripeException: ${e.error.code} / ${e.error.message}');
      return false;
    } catch (e) {
      debugPrint('[Stripe] handleNextAction FAILED: $e');
      return false;
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
  final PaymentErrorCode? errorCode;
  final String? declineCode;

  const PaymentResult._({
    required this.type,
    this.clientSecret,
    this.paymentIntentId,
    this.customerId,
    this.ephemeralKey,
    this.errorMessage,
    this.bookingId,
    this.errorCode,
    this.declineCode,
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

  factory PaymentResult.error(String message, {PaymentErrorCode? code}) =>
      PaymentResult._(
        type: PaymentResultType.error,
        errorMessage: message,
        errorCode: code,
      );

  /// Off-session charge proběhl, Stripe vrátil status='succeeded'.
  /// Žádný Payment Sheet ani SCA — webhook potvrdí v DB.
  factory PaymentResult.offSessionSucceeded({
    String? paymentIntentId,
    String? bookingId,
  }) =>
      PaymentResult._(
        type: PaymentResultType.offSessionSucceeded,
        paymentIntentId: paymentIntentId,
        bookingId: bookingId,
      );

  /// Off-session vyžaduje SCA (3DS) — klient pokračuje přes Stripe.handleNextAction.
  factory PaymentResult.offSessionRequiresAction({
    required String clientSecret,
    String? paymentIntentId,
    String? bookingId,
  }) =>
      PaymentResult._(
        type: PaymentResultType.offSessionRequiresAction,
        clientSecret: clientSecret,
        paymentIntentId: paymentIntentId,
        bookingId: bookingId,
      );

  /// Off-session selhal (karta declined, expired, ...). Klient může spadnout
  /// do klasického Payment Sheetu.
  factory PaymentResult.offSessionFailed({
    required String message,
    String? errorCode,
    String? declineCode,
  }) =>
      PaymentResult._(
        type: PaymentResultType.offSessionFailed,
        errorMessage: message,
        declineCode: declineCode,
      );

  bool get isSuccess =>
      type == PaymentResultType.intent ||
      type == PaymentResultType.free ||
      type == PaymentResultType.offSessionSucceeded;
}

enum PaymentResultType {
  intent,
  free,
  error,
  offSessionSucceeded,
  offSessionRequiresAction,
  offSessionFailed,
}

/// Categorized error codes for specific UI guidance.
enum PaymentErrorCode { authExpired, timeout, networkError, serverError }
