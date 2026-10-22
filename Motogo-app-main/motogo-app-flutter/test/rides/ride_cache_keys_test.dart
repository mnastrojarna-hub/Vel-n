// Nové klíče záznamníku musí přežít úklid SharedPreferences
// (CacheCleanupService běží při KAŽDÉM přechodu appky do pozadí).
// Pozn.: `CacheCleanupService.run()` se v testu NESMÍ spouštět — maže
// i systémový temp adresář.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:motogo_app/features/routes/ride_recorder.dart';
import 'package:motogo_app/features/routes/ride_session.dart';

void main() {
  test('mg_ride_session a mg_ride_caps jsou v _preserveKeys', () {
    final src = File('lib/core/cache_cleanup_service.dart').readAsStringSync();
    final start = src.indexOf('_preserveKeys = <String>{');
    final end = src.indexOf('};', start);
    expect(start, greaterThan(0));
    final block = src.substring(start, end);
    for (final k in [kRideSessionKey, kRideCapsKey, kRideAutoRecordKey, kRideRecIdKey, kRideRecBufKey, kRideRecManualKey]) {
      expect(block, contains("'$k'"), reason: k);
    }
  });
}
