import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/catalog_provider.dart';
import '../reservations/reservation_provider.dart';
import '../routes/routes_provider.dart';

/// Pull-to-refresh domovské obrazovky — PŘESUNUTO beze změny z
/// `HomeScreen` (PM-8), sdílí ho stará i v2 domovská obrazovka.
Future<void> refreshHome(WidgetRef ref) async {
  ref.invalidate(motorcyclesProvider);
  ref.invalidate(filteredMotorcyclesProvider);
  ref.invalidate(reservationsProvider);
  await ref.read(motorcyclesProvider.future);
}

/// Warm-up tabu „Trasy" (PM-8, beze změny z `HomeScreen.initState`): těžké
/// payloady (trasy + katalog POI) se přednačtou na pozadí. Volající drží
/// původní 2s zpoždění a kontrolu `mounted`.
void warmUpRoutes(WidgetRef ref) {
  ref.read(routesDataProvider);
  ref.read(catalogPoisProvider);
}
