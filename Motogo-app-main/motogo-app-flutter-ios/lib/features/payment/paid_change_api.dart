import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/supabase_client.dart';
import 'net_error.dart' show isNetworkError;

/// Stav dokončení zaplacené výměny / úpravy na serveru (D6) — odpověď
/// `process-payment` `{action:'complete_extension', payment_intent_id}`.
enum CompleteState {
  /// Změna je v rezervaci zapsaná (teď, nebo už dřív — webhook).
  applied,
  /// Změna se do Stripe metadat nevešla → zapíše ji appka (stará cesta).
  clientApply,
  /// Banka platbu ještě zpracovává / server zapisuje → zkusit později.
  pending,
  /// Dočasná chyba (síť, server, přihlášení) → zkusit později.
  retry,
  /// Změnu trvale nejde zapsat (motorku mezitím obsadil jiný…) — doplatek se vrací.
  failed,
  /// Platba neproběhla (nic nestrženo) → nic nedokončovat.
  notPaid,
}

class CompleteResponse {
  final CompleteState state;
  /// Bez spojení (offline / timeout) — text „dokončíme po připojení".
  final bool offline;
  /// `failed`: kód důvodu (new_moto_unavailable, wrong_status, swap_date_out_of_range…).
  final String? reason;
  /// `failed`: 'auto' = vratka odeslaná automaticky, 'staff' = vrátí obsluha.
  final String refund;
  /// `failed`: zaplacená částka (Kč).
  final double? amount;
  final String? newBookingId;
  const CompleteResponse(this.state,
      {this.offline = false, this.reason, this.refund = 'auto', this.amount, this.newBookingId});

  /// Mapování odpovědi serveru (HTTP stav + JSON) — čistá funkce kvůli testům.
  factory CompleteResponse.fromHttp(int status, Map<String, dynamic>? d) {
    final st = d?['state']?.toString();
    final code = d?['code']?.toString();
    if (d?['success'] == true && (st == 'applied' || st == 'already_applied')) {
      return CompleteResponse(CompleteState.applied, newBookingId: d?['new_booking_id']?.toString());
    }
    if (d?['success'] == true && st == 'client_apply') {
      return const CompleteResponse(CompleteState.clientApply);
    }
    if (st == 'failed') {
      return CompleteResponse(CompleteState.failed,
          reason: d?['reason']?.toString(),
          refund: d?['refund'] == 'staff' ? 'staff' : 'auto',
          amount: (d?['amount'] as num?)?.toDouble());
    }
    if (st == 'not_paid' || code == 'not_paid') return const CompleteResponse(CompleteState.notPaid);
    if (st == 'pending' || status == 202) return const CompleteResponse(CompleteState.pending);
    // retry / 5xx / 401 / neznámé → zkusit znovu (server je idempotentní).
    return const CompleteResponse(CompleteState.retry);
  }
}

/// Zavolá dokončení zaplacené změny. Nikdy nehází — chyba = [CompleteState.retry].
Future<CompleteResponse> completeExtension(String paymentIntentId,
    {Duration timeout = const Duration(seconds: 20)}) async {
  try {
    var session = MotoGoSupabase.currentSession;
    if (session == null) return const CompleteResponse(CompleteState.retry);
    if (session.isExpired) {
      try {
        final r = await MotoGoSupabase.client.auth.refreshSession().timeout(timeout);
        session = r.session ?? MotoGoSupabase.currentSession;
      } catch (_) {
        return const CompleteResponse(CompleteState.retry, offline: true);
      }
      if (session == null) return const CompleteResponse(CompleteState.retry);
    }
    Future<http.Response> send(String token) => http
        .post(
          Uri.parse('${MotoGoSupabase.url}/functions/v1/process-payment'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
            'apikey': MotoGoSupabase.anonKey,
          },
          body: jsonEncode({'action': 'complete_extension', 'payment_intent_id': paymentIntentId}),
        )
        .timeout(timeout);
    var res = await send(session.accessToken);
    if (res.statusCode == 401) {
      try {
        final r = await MotoGoSupabase.client.auth.refreshSession().timeout(timeout);
        final s = r.session;
        if (s != null) res = await send(s.accessToken);
      } catch (_) {/* zkusí se při dalším pokusu */}
    }
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      data = null; // 502/504 HTML brány
    }
    return CompleteResponse.fromHttp(res.statusCode, data);
  } catch (e) {
    debugPrint('[PaidChange] complete_extension failed: $e');
    return CompleteResponse(CompleteState.retry, offline: isNetworkError(e));
  }
}

/// `pi_xxx_secret_yyy` → `pi_xxx` (id PaymentIntentu z client secret).
String? piIdFromClientSecret(String? cs) {
  if (cs == null) return null;
  final i = cs.indexOf('_secret_');
  return i > 0 && cs.startsWith('pi_') ? cs.substring(0, i) : null;
}
