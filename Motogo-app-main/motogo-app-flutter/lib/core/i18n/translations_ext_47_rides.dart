import 'translations_ext_47_rides_pause_a.dart';
import 'translations_ext_47_rides_pause_b.dart';
import 'translations_ext_47_rides_pause_c.dart';
import 'translations_ext_47_rides_pause_d.dart';
import 'translations_ext_47_rides_trips_a.dart';
import 'translations_ext_47_rides_trips_b.dart';
import 'translations_ext_47_rides_trips_c.dart';
import 'translations_ext_47_rides_trips_d.dart';
import 'translations_ext_60_rides_logic.dart';

/// Záznam jízd (pauza, auto-pauza, cesty) — všechny klíče `rp*` v jedné
/// mapě, aby `translations.dart` potřeboval jediný řádek (oba stromy appky).
final Map<String, Map<String, String>> translationsExt47Rides = () {
  final out = <String, Map<String, String>>{};
  for (final part in [
    translationsExt47RidesPauseA,
    translationsExt47RidesPauseB,
    translationsExt47RidesPauseC,
    translationsExt47RidesPauseD,
    translationsExt47RidesTripsA,
    translationsExt47RidesTripsB,
    translationsExt47RidesTripsC,
    translationsExt47RidesTripsD,
    translationsExt60RidesLogic,
  ]) {
    part.forEach((lang, map) => out.putIfAbsent(lang, () => {}).addAll(map));
  }
  return out;
}();
