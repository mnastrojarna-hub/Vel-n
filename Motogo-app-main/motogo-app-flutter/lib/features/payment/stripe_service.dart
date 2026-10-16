import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Color;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, Session;

import '../../core/auth_guard.dart';
import '../../core/supabase_client.dart';

/// Stripe payment service — native Payment Sheet (in-app, no redirect).
///
/// Flutter uses mode: 'intent'. Edge function returns client_secret,
/// customer_id, and ephemeral_key for full Payment Sheet support
/// (including saved cards).
class StripeService {
  StripeService._();

  /// Jeden dotaz na stav platby v DB nesmí viset (slabé LTE) — po limitu se
  /// bere jako „zatím nevíme" a polling pokračuje dalším pokusem.
  static const _queryTimeout = Duration(seconds: 8);

  /// Platný přístupový token: prošlý se nejdřív obnoví (dřív appka poslala
  /// prošlý token → 401 → odhlášení uprostřed platby). null = obnova selhala.
  static Future<Session?> _validSession() async {
    final s = MotoGoSupabase.currentSession;
    if (s == null) return null;
    if (!s.isExpired) return s;
    return _refreshSession();
  }

  static Future<Session?> _refreshSession() async {
    try {
      final r = await MotoGoSupabase.client.auth
          .refreshSession()
          .timeout(const Duration(seconds: 15));
      return r.session;
    } catch (e) {
      debugPrint('[Stripe] refreshSession failed: $e');
      return null;
    }
  }

  /// Create PaymentIntent via process-payment edge function (mode: intent).
  /// Returns client_secret + customer data for Stripe Payment Sheet.
  /// Když je předán [paymentMethodId], edge fn provede off-session charge a
  /// místo Payment Sheetu se vrátí buď `succeeded`, nebo `requires_action` s
  /// client_secret pro SCA (klient pak volá `handleNextAction`).
  ///
  /// POZOR (peníze): s [paymentMethodId] server kartu rovnou STRHÁVÁ. Když se
  /// odpověď ztratí (timeout, výpadek sítě, 502 bez JSON), platba mohla projít
  /// → výsledek nese `uncertain: true` a volající NESMÍ tvrdit „nic nebylo
  /// strženo" ani nabízet novou platbu, dokud stav neověří v DB.
  static Future<PaymentResult> createPaymentIntent({
    String? bookingId,
    required int amount,
    String method = 'card',
    String type = 'booking',
    String? orderId,
    String? incidentId,
    String? paymentMethodId,
    Map<String, dynamic>? change,
  }) async {
    final charges = paymentMethodId != null;
    try {
      final session = await _validSession();
      if (session == null) {
        // Bez platného přihlášení server nic nestrhne — UI hlášku skládá z kódu.
        if (MotoGoSupabase.currentSession != null) {
          await handleAuthError(AuthException('session refresh failed'));
        }
        return PaymentResult.error('session expired',
            code: PaymentErrorCode.authExpired);
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
      // Doplatková změna rezervace (type=extension): kompaktní payload změny.
      // process-payment ho uloží do Stripe metadata.chg (limit 500 znaků) a
      // webhook-receiver změnu aplikuje server-side i bez návratu do appky.
      if (change != null && change.isNotEmpty) body['change'] = change;

      Future<http.Response> send(String token) => http
          .post(
            Uri.parse('${MotoGoSupabase.url}/functions/v1/process-payment'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
              'apikey': MotoGoSupabase.anonKey,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

      var response = await send(session.accessToken);
      // 401 vrací server PŘED jakoukoli platbou (ověření vlastníka) → jedna
      // obnova tokenu + jeden nový pokus je bezpečný. Odhlásit až když ani
      // obnova nepomůže (dřív odhlášení hned → ztracený flow i úprava).
      if (response.statusCode == 401) {
        final refreshed = await _refreshSession();
        if (refreshed != null) response = await send(refreshed.accessToken);
        if (response.statusCode == 401) {
          await handleAuthError(AuthException('401 from process-payment'));
          return PaymentResult.error('session expired',
              code: PaymentErrorCode.authExpired, httpStatus: 401);
        }
      }

      final Map<String, dynamic> data;
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        // 502/504 HTML brány apod. — server neodpověděl smysluplně. U stržení
        // uložené karty nevíme, jestli charge proběhl.
        debugPrint('[Stripe] non-JSON response ${response.statusCode}');
        return PaymentResult.error('server unavailable',
            code: PaymentErrorCode.serverUnavailable,
            httpStatus: response.statusCode,
            uncertain: charges);
      }

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
        // Off-session selhal (typicky declined / expired / authentication denied),
        // nebo PI skončil v neočekávaném stavu (processing → ověřit, ne chyba).
        final msg = (data['message'] as String?) ?? '';
        return PaymentResult.offSessionFailed(
          message: msg,
          errorCode: data['error_code'] as String?,
          declineCode: data['decline_code'] as String?,
          intentStatus: data['status'] as String?,
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

      // Odmítnutí serverem (4xx/5xx s JSON). Text serveru je česky a jen do
      // logu / pro odvození kódu — UI hlášku skládá PaymentRefusals z kódu.
      final serverMsg = data['error'] as String? ?? '';
      final total = (data['server_total'] as num?) ?? (data['expected'] as num?);
      return PaymentResult.error(
        serverMsg,
        code: PaymentErrorCode.serverError,
        serverCode: data['code'] as String?,
        serverTotal: total?.toDouble(),
        httpStatus: response.statusCode,
        // 5xx z vnějšího catch (Stripe výjimka) — u stržení uložené karty
        // raději ověřit stav, než tvrdit „nic nebylo strženo".
        uncertain: charges && response.statusCode >= 500,
      );
    } on TimeoutException {
      return PaymentResult.error('timeout',
          code: PaymentErrorCode.timeout, uncertain: charges);
    } catch (e) {
      debugPrint('[Stripe] createPaymentIntent failed: $e');
      return PaymentResult.error('network error',
          code: PaymentErrorCode.networkError, uncertain: charges);
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
    bool sdkReady = false;
    String? applyError;
    for (var i = 0; i < 2 && !sdkReady; i++) {
      try {
        await Stripe.instance.applySettings();
        sdkReady = true;
      } catch (e) {
        applyError = '$e';
        debugPrint('[Stripe] applySettings FAILED (attempt ${i + 1}): $e');
        if (i == 0) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    if (!sdkReady) {
      throw Exception('applySettings selhalo: $applyError');
    }

    // Only pass customer data when BOTH customerId and ephemeralKey exist
    final useCustomer = customerId != null && ephemeralKey != null;
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
        testEnv: false,
      ),
      // Apple Pay (for future iOS builds)
      applePay: const PaymentSheetApplePay(
        merchantCountryCode: 'CZ',
      ),
      customerId: useCustomer ? customerId : null,
      customerEphemeralKeySecret: useCustomer ? ephemeralKey : null,
    );

    try {
      await Stripe.instance.initPaymentSheet(paymentSheetParameters: params);
    } catch (e) {
      debugPrint('[Stripe] initPaymentSheet FAILED: $e');
      throw Exception('initPaymentSheet: $e');
    }

    try {
      await Stripe.instance.presentPaymentSheet();
      return true;
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) return false;
      rethrow;
    }
  }

  /// Dokončí SCA (3DS) pro off-session PaymentIntent, který backend založil
  /// s `requires_action`. Volá se z PaymentScreen po PaymentResult.offSessionRequiresAction.
  ///
  /// Rozlišuje: zaplaceno / banka ještě zpracovává / zákazník ověření
  /// nedokončil / banka ověření zamítla / nevíme (výpadek sítě — ověřit v DB).
  static Future<NextActionOutcome> handleNextAction(String clientSecret) async {
    try {
      await Stripe.instance.applySettings();
    } catch (e) {
      // pokračujeme — handleNextAction často projde i bez explicitního applySettings
      debugPrint('[Stripe] handleNextAction applySettings failed: $e');
    }
    try {
      final result = await Stripe.instance.handleNextAction(clientSecret);
      return outcomeForStatus(result.status);
    } on StripeException catch (e) {
      debugPrint('[Stripe] handleNextAction StripeException: ${e.error.code} / ${e.error.stripeErrorCode}');
      if (e.error.code == FailureCode.Canceled) return NextActionOutcome.notCompleted;
      // Bez Stripe kódu = typicky výpadek spojení po odeslání → stav nevíme.
      if ((e.error.stripeErrorCode ?? '').isEmpty &&
          (e.error.declineCode ?? '').isEmpty) {
        return NextActionOutcome.unknown;
      }
      return NextActionOutcome.failed;
    } catch (e) {
      debugPrint('[Stripe] handleNextAction FAILED: $e');
      return NextActionOutcome.unknown;
    }
  }

  /// Stav PaymentIntentu → výsledek (sdílí 3DS i ověření po chybě).
  static NextActionOutcome outcomeForStatus(PaymentIntentsStatus? s) {
    switch (s) {
      case PaymentIntentsStatus.Succeeded:
      case PaymentIntentsStatus.RequiresCapture:
        return NextActionOutcome.succeeded;
      case PaymentIntentsStatus.Processing:
        return NextActionOutcome.processing;
      case PaymentIntentsStatus.RequiresAction:
      case PaymentIntentsStatus.RequiresConfirmation:
        return NextActionOutcome.notCompleted;
      case PaymentIntentsStatus.RequiresPaymentMethod:
      case PaymentIntentsStatus.Canceled:
        return NextActionOutcome.failed;
      default:
        return NextActionOutcome.unknown;
    }
  }

  /// Skutečný stav PaymentIntentu po nejasné chybě (výpadek sítě během
  /// potvrzení, neznámá výjimka pluginu). Až 3 pokusy s timeoutem — bez sítě
  /// by jeden pokus visel až 60 s. null = stav nejde zjistit.
  static Future<PaymentIntentsStatus?> fetchIntentStatus(String clientSecret) async {
    for (var i = 0; i < 3; i++) {
      try {
        final pi = await Stripe.instance
            .retrievePaymentIntent(clientSecret)
            .timeout(const Duration(seconds: 8));
        return pi.status;
      } catch (_) {
        if (i < 2) await Future.delayed(Duration(milliseconds: 700 * (i + 1)));
      }
    }
    return null;
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
            .single()
            .timeout(_queryTimeout);

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
            .single()
            .timeout(_queryTimeout);

        if (res['payment_status'] == 'paid') return true;
      } catch (_) {}

      if (i < maxAttempts - 1) {
        await Future.delayed(interval);
      }
    }
    return false;
  }

  /// Poll doplatku úpravy: změna se promítla, když `bookings.total_price`
  /// dosáhl očekávané nové ceny (booking je `paid` už z původní platby).
  static Future<bool> pollBookingTotal(
    String bookingId,
    double expected, {
    int maxAttempts = 5,
    Duration interval = const Duration(seconds: 2),
  }) async {
    for (var i = 0; i < maxAttempts; i++) {
      try {
        final row = await MotoGoSupabase.client
            .from('bookings')
            .select('total_price')
            .eq('id', bookingId)
            .maybeSingle()
            .timeout(_queryTimeout);
        final cur = (row?['total_price'] as num?)?.toDouble();
        if (cur != null && (cur - expected).abs() < 0.5) return true;
      } catch (_) {}
      if (i < maxAttempts - 1) await Future.delayed(interval);
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

/// Výsledek dokončení 3DS / ověření stavu PaymentIntentu.
enum NextActionOutcome {
  /// Zaplaceno (Succeeded / RequiresCapture).
  succeeded,
  /// Banka platbu ještě zpracovává — čekat na server (webhook).
  processing,
  /// Zákazník ověření u banky nedokončil (zavřel / zrušil) — nic nestrženo.
  notCompleted,
  /// Banka ověření nebo platbu zamítla — nic nestrženo.
  failed,
  /// Stav nejde zjistit (výpadek sítě) — ověřit v DB, nikdy netvrdit „nestrženo".
  unknown,
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
  /// `code` z odpovědi process-payment (odmítnutí serverem před platbou).
  final String? serverCode;
  /// Stripe `error_code` při selhání stržení uložené karty (expired_card,
  /// resource_missing, amount_too_small…) — dřív se zahazoval.
  final String? stripeCode;
  /// Cena podle serveru (`server_total` / `expected`) u `amount_mismatch`.
  final double? serverTotal;
  final int? httpStatus;
  /// Stav PI u off-session odpovědi bez úspěchu (např. `processing`).
  final String? intentStatus;
  /// true = požadavek nesl `payment_method_id` a odpověď se ztratila —
  /// platba MOHLA proběhnout. Nikdy netvrdit „nic nebylo strženo".
  final bool uncertain;

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
    this.serverCode,
    this.stripeCode,
    this.serverTotal,
    this.httpStatus,
    this.intentStatus,
    this.uncertain = false,
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

  factory PaymentResult.error(String message,
          {PaymentErrorCode? code,
          String? serverCode,
          double? serverTotal,
          int? httpStatus,
          bool uncertain = false}) =>
      PaymentResult._(
        type: PaymentResultType.error,
        errorMessage: message,
        errorCode: code,
        serverCode: serverCode,
        serverTotal: serverTotal,
        httpStatus: httpStatus,
        uncertain: uncertain,
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

  /// Off-session selhal (karta declined, expired, ...).
  factory PaymentResult.offSessionFailed({
    required String message,
    String? errorCode,
    String? declineCode,
    String? intentStatus,
  }) =>
      PaymentResult._(
        type: PaymentResultType.offSessionFailed,
        errorMessage: message,
        declineCode: declineCode,
        stripeCode: errorCode,
        intentStatus: intentStatus,
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
enum PaymentErrorCode { authExpired, timeout, networkError, serverError, serverUnavailable }
