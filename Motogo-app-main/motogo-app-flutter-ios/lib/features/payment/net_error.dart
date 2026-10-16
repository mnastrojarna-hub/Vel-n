import 'dart:async';
import 'dart:io' show SocketException, HttpException;

import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, AuthRetryableFetchException;

import '../../core/auth_guard.dart';

/// Výjimka znamená výpadek spojení / timeout (ne odmítnutí serverem) →
/// hláška „zkontroluj připojení", ne „neznámá chyba" ani syrový text.
bool isNetworkError(Object e) {
  if (e is TimeoutException || e is SocketException || e is ClientException ||
      e is HttpException) {
    return true;
  }
  final m = e.toString().toLowerCase();
  return m.contains('socketexception') ||
      m.contains('failed host lookup') ||
      m.contains('connection closed') ||
      m.contains('connection reset') ||
      m.contains('connection refused') ||
      m.contains('network is unreachable') ||
      m.contains('authretryablefetchexception') ||
      m.contains('timeoutexception');
}

/// Prošlé / neplatné přihlášení (JWT) — sdílí vzory s `auth_guard`.
bool isAuthExpiredError(Object e) => isAuthError(e);

/// Požadavek prokazatelně NEODEŠEL (DNS, síť nedostupná, spojení odmítnuto,
/// TLS handshake) — server nic nedostal, takže ani nic nestrhl → klidně
/// „zkontroluj připojení a zkus znovu". Timeout, přerušené / resetované
/// spojení ani 5xx sem NEPATŘÍ: požadavek mohl dorazit a kartu strhnout.
bool requestNeverSent(Object e) {
  final m = e.toString().toLowerCase();
  return m.contains('failed host lookup') ||
      m.contains('no address associated') ||
      m.contains('network is unreachable') ||
      m.contains('no route to host') ||
      m.contains('connection refused') ||
      m.contains('handshakeexception');
}

/// Obnova přihlášení selhala na síti / dočasně (offline, timeout, výpadek
/// serveru), ne odmítnutím přihlášení — kvůli tomu se NIKDY neodhlašuje.
/// Odhlásit smí jen skutečné odmítnutí (neplatný / použitý refresh token).
bool authRefreshNetworkFailure(Object e) {
  if (e is AuthRetryableFetchException) return true;
  if (isNetworkError(e)) return true;
  return e is! AuthException;
}
