import 'dart:async';

import 'package:http/http.dart' as http;

/// HTTP klient Supabase s časovým limitem na KAŽDÝ požadavek (2026-10-16,
/// požadavek majitele: „nikde se to nesmí zaseknout").
///
/// Dart `HttpClient` nemá limit na čtení — na zaseklém LTE / Wi-Fi s přihlášením
/// (captive portal) by požadavek visel navždy a obrazovka by se točila bez
/// konce. Limit hlídá dobu do hlaviček odpovědi a pak i prodlevy při čtení
/// těla; po vypršení letí [TimeoutException], kterou `FriendlyError` přeloží
/// na „Server neodpovídá – zkus to znovu na lepším signálu".
///
/// Auth (GoTrue) výjimku sám obalí do `AuthRetryableFetchException`, takže
/// pomalé obnovení tokenu zákazníka NIKDY neodhlásí.
class TimeoutClient extends http.BaseClient {
  TimeoutClient(this._inner, {Duration Function(Uri url)? limits})
      : _limits = limits ?? limitFor;

  final http.Client _inner;
  final Duration Function(Uri url) _limits;

  /// Limit podle cesty požadavku (veřejné kvůli testům).
  static Duration limitFor(Uri url) {
    final p = url.path;
    if (p.contains('/functions/v1/')) {
      final fn = p.split('/functions/v1/').last.split('/').first;
      switch (fn) {
        case 'ai-moto-agent':
          return const Duration(seconds: 90);
        case 'scan-document':
        case 'save-verification-document':
          return const Duration(seconds: 60);
        case 'generate-invoice':
        case 'generate-document':
        case 'process-refund':
          return const Duration(seconds: 45);
        default:
          return const Duration(seconds: 30);
      }
    }
    if (p.contains('/storage/v1/')) return const Duration(seconds: 120);
    if (p.contains('/rest/v1/rpc/')) return const Duration(seconds: 30);
    return const Duration(seconds: 20); // /rest/v1, /auth/v1
  }

  /// Nejdelší povolená pauza mezi dvěma kusy těla odpovědi.
  static const Duration bodyIdle = Duration(seconds: 30);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final limit = _limits(request.url);
    final res = await _inner.send(request).timeout(limit, onTimeout: () {
      throw TimeoutException('No response from ${request.url.path}', limit);
    });
    return http.StreamedResponse(
      res.stream.timeout(bodyIdle, onTimeout: (sink) {
        sink.addError(
            TimeoutException('Response body stalled (${request.url.path})', bodyIdle));
        sink.close();
      }),
      res.statusCode,
      contentLength: res.contentLength,
      request: res.request,
      headers: res.headers,
      isRedirect: res.isRedirect,
      persistentConnection: res.persistentConnection,
      reasonPhrase: res.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}
