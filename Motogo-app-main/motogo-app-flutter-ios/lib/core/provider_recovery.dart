import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_provider.dart' show profileProvider;
import '../features/catalog/catalog_provider.dart' show motorcyclesProvider;
import '../features/messages/messages_provider.dart'
    show adminMessagesProvider, threadsProvider;
import '../features/reservations/reservation_provider.dart' show reservationsProvider;
import '../features/routes/routes_provider.dart'
    show catalogPoisProvider, userPoisProvider;
import '../features/sos/sos_provider.dart' show activeSosProvider;

/// Po návratu připojení / do popředí znovu načte sdílené providery, které
/// zůstaly v chybě (nejsou autoDispose → jinak by chyba visela do restartu
/// appky). Neexistující providery nezakládá.
void recoverFailedProviders(WidgetRef ref) {
  void check(ProviderBase<AsyncValue<Object?>> p) {
    try {
      if (ref.exists(p) && ref.read(p).hasError) ref.invalidate(p);
    } catch (_) {}
  }

  check(activeSosProvider);
  check(threadsProvider);
  check(adminMessagesProvider);
  check(reservationsProvider);
  check(profileProvider);
  check(motorcyclesProvider);
  check(catalogPoisProvider);
  check(userPoisProvider);
}
