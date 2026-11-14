// Journey rig — fake Supabase backend. Initialised once per isolate with a
// mock HTTP client (no network): a few RPCs the screens call directly
// answer from the current start state, every other request answers an
// empty list. Login = a locally recovered session with a far-future JWT
// (no auth server call), so the REAL router redirect sees
// `MotoGoSupabase.currentSession`.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motogo_app/core/supabase_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'journey_states.dart';

const kJourneyUserId = '0f0f0f0f-1111-4222-8333-444444444444';

/// The state the fake backend answers for (set by the rig before boot).
JourneyData? journeyBackendData;

/// Every request the app made (method + path), for the step log.
final journeyRequests = <String>[];

bool _init = false;

/// The request currently answered (postgrest reads `response.request`).
http.Request? _req;

http.Response _json(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status,
    request: _req, headers: {'content-type': 'application/json; charset=utf-8'});

String _ymd(DateTime x) =>
    '${x.year.toString().padLeft(4, '0')}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';

/// Busy ranges of a bike (start, end, status, booking id): the Shotgun is in
/// service for the next 60 days, the BMW is booked by someone else in 3–5
/// weeks (a taken date to bump into), the state's other customers'
/// bookings ([JourneyData.others]) and the customer's own open bookings.
List<(DateTime, DateTime, String, String)> journeyBlocks(String motoId, JourneyData? d) {
  final n = DateTime.now();
  final t = DateTime(n.year, n.month, n.day);
  DateTime at(int k) => DateTime(t.year, t.month, t.day + k);
  return [
    if (motoId == 'm-shot') (at(-1), at(60), 'service', 'svc-shot'),
    if (motoId == 'm-bmw') (at(21), at(35), 'reserved', 'other-bmw'),
    for (final o in d?.others ?? const <(String, int, int)>[])
      if (o.$1 == motoId) (at(o.$2), at(o.$3), 'reserved', 'other-${o.$1}-${o.$2}'),
    for (final r in d?.reservations ?? const [])
      if (r.motoId == motoId && const ['pending', 'reserved', 'active'].contains(r.status))
        (r.startDate, r.endDate, r.status, r.id),
  ];
}

Future<http.Response> _handle(http.Request r) async {
  _req = r;
  final path = r.url.path;
  journeyRequests.add('${r.method} $path');
  final d = journeyBackendData;
  final single = (r.headers['Accept'] ?? r.headers['accept'] ?? '').contains('vnd.pgrst.object');
  if (path.endsWith('/rpc/get_docs_gate_checklist')) {
    return _json(d?.gateJson ?? {'error': 'not_logged_in'});
  }
  if (path.endsWith('/rpc/get_moto_booked_dates') || path.endsWith('/rpc/check_moto_availability')) {
    Map<String, dynamic> p = const {};
    try {
      p = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
    } catch (_) {}
    final blocks = journeyBlocks('${p['p_moto_id']}', d);
    if (path.endsWith('get_moto_booked_dates')) {
      return _json([
        for (final b in blocks) {'start_date': _ymd(b.$1), 'end_date': _ymd(b.$2), 'status': b.$3},
      ]);
    }
    // check_moto_availability ignores service blocks (like the real RPC).
    final s = DateTime.tryParse('${p['p_start']}');
    final e = DateTime.tryParse('${p['p_end']}');
    if (s == null || e == null) return _json(true);
    // p_exclude_booking_id = the booking being changed (like the server).
    final skip = '${p['p_exclude_booking_id'] ?? ''}';
    final busy = blocks.any((b) => b.$3 != 'service' && b.$4 != skip && !s.isAfter(b.$2) && !b.$1.isAfter(e));
    return _json(!busy);
  }
  if (path.endsWith('/rest/v1/profiles') && d?.profile != null) {
    final v = d!.verification;
    final row = {
      'id': kJourneyUserId,
      ...d.profile!,
      'id_verified_at': v.idVerifiedAt?.toIso8601String(),
      'license_verified_at': v.licenseVerifiedAt?.toIso8601String(),
    };
    return _json(single ? row : [row]);
  }
  if (single) return http.Response('', 406, request: r);
  return _json(const []);
}

Future<void> initJourneyBackend() async {
  if (_init) return;
  _init = true;
  await Supabase.initialize(
    url: MotoGoSupabase.url,
    publishableKey: 'test-anon',
    httpClient: MockClient(_handle),
    authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(), detectSessionInUri: false, autoRefreshToken: false),
    debug: false,
  );
}

String _b64(Map<String, dynamic> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

/// Logs the fake customer in (or out) without any server call.
Future<void> journeySetLoggedIn(bool loggedIn) async {
  final auth = Supabase.instance.client.auth;
  if (!loggedIn) {
    if (auth.currentSession != null) {
      try {
        await auth.signOut(scope: SignOutScope.local);
      } catch (_) {}
    }
    return;
  }
  final exp = DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch ~/ 1000;
  final jwt = '${_b64({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${_b64({'sub': kJourneyUserId, 'exp': exp, 'role': 'authenticated', 'aud': 'authenticated'})}.c2ln';
  await auth.recoverSession(jsonEncode({
    'access_token': jwt,
    'expires_in': 315360000,
    'expires_at': exp,
    'refresh_token': 'journey-refresh',
    'token_type': 'bearer',
    'user': {
      'id': kJourneyUserId,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': journeyBackendData?.profile?['email'] ?? 'zakaznik@example.cz',
      'created_at': '2025-01-01T10:00:00Z',
      'app_metadata': {'provider': 'email'},
      'user_metadata': <String, dynamic>{},
    },
  }));
}
