// Rozlišení „starý server" / offline / chyba a odpovědi append (SPEC §5.4, §7.4).
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:motogo_app/features/routes/ride_server_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('classifyRideRpcError', () {
    for (final c in ['PGRST202', '42883', '42703', '404']) {
      expect(classifyRideRpcError(PostgrestException(message: 'x', code: c)), RideRpcErrorKind.missing, reason: c);
    }
    expect(classifyRideRpcError(PostgrestException(message: 'x', code: '500')), RideRpcErrorKind.error);
    expect(classifyRideRpcError(const SocketException('x')), RideRpcErrorKind.offline);
    expect(classifyRideRpcError(TimeoutException('x')), RideRpcErrorKind.offline);
    expect(classifyRideRpcError(http.ClientException('x')), RideRpcErrorKind.offline);
    expect(classifyRideRpcError(AuthRetryableFetchException()), RideRpcErrorKind.offline);
    expect(classifyRideRpcError(StateError('x')), RideRpcErrorKind.error);
  });

  test('odpověď append_ride_track: starý i nový server', () {
    final old = RideAppendOutcome.fromResponse(
        {'success': true, 'points': 10, 'distance_km': 12.3, 'moving_sec': 900, 'idle_sec': 1, 'gap_sec': 0});
    expect(old.result, RideAppendResult.ok);
    expect(old.distanceKm, 12.3);
    expect(old.stagesN, isNull);
    final nu = RideAppendOutcome.fromResponse(
        {'success': true, 'distance_km': 1, 'moving_sec': 2, 'pause_sec': 3, 'stages_n': 2, 'now': 1792000000.5});
    expect([nu.pauseSec, nu.stagesN, nu.serverNow], [3, 2, 1792000000.5]);
    expect(RideAppendOutcome.fromResponse({'success': false, 'error': 'ride_finished'}).result, RideAppendResult.closed);
    expect(RideAppendOutcome.fromResponse({'success': false, 'error': 'ride_finished', 'reason': 'booking_ended'}).bookingEnded,
        isTrue);
    expect(RideAppendOutcome.fromResponse({'success': false, 'error': 'ride_not_found'}).result, RideAppendResult.gone);
    expect(RideAppendOutcome.fromResponse({'success': false, 'error': 'not_authenticated'}).result, RideAppendResult.retry);
    expect(RideAppendOutcome.fromResponse(null).result, RideAppendResult.retry);
  });

  test('posun hodin: do ±120 s nula, jinak střed volání', () {
    final t0 = DateTime.fromMillisecondsSinceEpoch(1792000000000);
    final t1 = t0.add(const Duration(seconds: 2));
    expect(rideClockOffset(1792000001 + 100, t0, t1), 0);
    expect(rideClockOffset(1792000001 + 7200, t0, t1), 7200);
    expect(rideClockOffset(1792000001 - 7 * 3600, t0, t1), -25200);
  });

  test('položka set_user_rides_trip', () {
    expect(const RideTripItem('a', 't', 'Alpy').toJson(), {'id': 'a', 'trip_id': 't', 'trip_name': 'Alpy'});
    expect(const RideTripItem('a', null, null).toJson(), {'id': 'a', 'trip_id': null, 'trip_name': null});
  });
}
