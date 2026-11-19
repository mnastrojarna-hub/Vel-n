import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/catalog_provider.dart';
import '../gear_rental/gear_contract.dart';
import '../gear_rental/gear_offer_provider.dart';
import '../reservations/reservation_provider.dart';
import '../routes/routes_provider.dart';

/// Pull-to-refresh domovské obrazovky — PŘESUNUTO beze změny z
/// `HomeScreen` (PM-8), sdílí ho stará i v2 domovská obrazovka.
Future<void> refreshHome(WidgetRef ref) async {
  ref.invalidate(motorcyclesProvider);
  ref.invalidate(filteredMotorcyclesProvider);
  ref.invalidate(reservationsProvider);
  // Vstup „Půjčit samotnou výbavu“ (nastavení, ceník, pobočky, zavření).
  ref.invalidate(gearRentalSettingsProvider);
  ref.invalidate(gearPricesProvider);
  ref.invalidate(gearBranchesProvider);
  ref.invalidate(gearClosuresProvider);
  await ref.read(motorcyclesProvider.future);
}

/// Warm-up tabu „Trasy" (PM-8, beze změny z `HomeScreen.initState`): těžké
/// payloady (trasy + katalog POI) se přednačtou na pozadí. Volající drží
/// původní 2s zpoždění a kontrolu `mounted`.
void warmUpRoutes(WidgetRef ref) {
  ref.read(routesDataProvider);
  ref.read(catalogPoisProvider);
}
