import 'dart:async';
import 'dart:io' show SocketException, HttpException;

import 'package:http/http.dart' show ClientException;

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
