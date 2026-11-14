// Journey rig — the 5.0.1 start states (README "5.0.1 states"). Every one
// is a customer with a full profile, verified documents, licence A+B and
// rank 3, on the 12-bike fleet (journey_fleet.dart) unless noted. Only
// DATA differs (bookings of other customers, branch closures, the filter
// the customer left set, routes); availability, next free days, closures
// and the offer are the app's real code against the fake backend.
import 'package:motogo_app/features/catalog/catalog_provider.dart' show CatalogFilter;
import 'package:motogo_app/features/documents/docs_gate_provider.dart';
import 'package:motogo_app/features/documents/document_provider.dart';

import '../support/fakes_home.dart' show loyaltyAt;
import 'journey_fleet.dart';
import 'journey_routes.dart';
import 'journey_states.dart';

/// Other customers' bookings: the 6 bikes in [ids] are booked on days
/// [from]–[to] (day offsets from today).
List<(String, int, int)> _booked(List<String> ids, int from, int to) => [for (final id in ids) (id, from, to)];

DateTime _day(int k) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day + k);
}

/// Days 7–9 from today (dates of the `filters_*` states; never a past day).
CatalogFilter _dated(CatalogFilter f) => CatalogFilter(
      category: f.category,
      licenseGroup: f.licenseGroup,
      branch: f.branch,
      minPowerKw: f.minPowerKw,
      maxPowerKw: f.maxPowerKw,
      availableTodayOnly: f.availableTodayOnly,
      startDate: _day(7),
      endDate: _day(9),
    );

JourneyData journeyDataV501(JourneyState s,
    {required Map<String, dynamic> profile, required DocsGateChecklist gate, required DocsVerification verification}) {
  JourneyData d({
    List<(String, int, int)> others = const [],
    List<(String, int, int)> closures = const [],
    CatalogFilter? filter,
    bool routes = false,
    Set<String> countries = const {},
    int delay = 0,
    String? start,
  }) {
    // `availableToday` matches the data: false when a booking or a closed
    // branch covers today.
    final busy = {
      for (final o in others)
        if (o.$2 <= 0 && o.$3 >= 0) o.$1,
      for (final c in closures)
        if (c.$2 <= 0 && c.$3 >= 0)
          for (final m in journeyFleet())
            if (m.branchId == c.$1) m.id,
    };
    return JourneyData(
        state: s,
        loggedIn: true,
        profile: profile,
        gate: gate,
        verification: verification,
        loyalty: loyaltyAt(3),
        motos: journeyFleet(busyToday: busy),
        others: others,
        closures: closures,
        filter: filter,
        routes: routes ? kJourneyRoutes : null,
        routeCountries: countries,
        availDelayMs: delay,
        start: start,
      );
  }

  switch (s) {
    // Half the fleet booked by other customers on days 0–9 (always covers
    // the nearest weekend, whatever the weekday). Availability answers take
    // 2.5 s, so the Home offer shows its batches of 6 (waits 2000, 2500).
    case JourneyState.fleet12:
      return d(others: _booked(const ['f-bmw', 'f-husq', 'f-z900', 'f-africa', 'f-tiger', 'f-sr125'], 0, 9), delay: 2500);
    // Nothing set: the default Home. Tiger, VTX and Husqvarna are booked by
    // other customers on days 0–4 (their pill reads "Volná od", the rest
    // "Volná dnes").
    case JourneyState.noDates:
      return d(others: _booked(const ['f-tiger', 'f-vtx', 'f-husq'], 0, 4));
    // Both branches closed from 14 days ago until day 130 → nothing free
    // in the coming weekends, every bike free again on day 131.
    case JourneyState.winter:
      return d(closures: const [(kBranchMeznaId, -14, 130), (kBranchVnId, -14, 130)]);
    // Branches open, every bike booked by other customers on days 0–20
    // (the next two weekends), free from day 21.
    case JourneyState.bookedOut:
      return d(others: _booked(kFleetIds, 0, 20));
    // Two real filters left set: licence A2 + power 30–60 kW (Shotgun,
    // Husqvarna, TRK 502 X, Jawa match), no dates.
    case JourneyState.filtersOn:
      return d(filter: const CatalogFilter(licenseGroup: 'A2', minPowerKw: 30, maxPowerKw: 60));
    // The filter builder's set: naked, A2, 35–70 kW, "Jen dnes volné",
    // branch Velké Němčice, days 7–9.
    case JourneyState.filtersMany:
      return d(
          filter: _dated(const CatalogFilter(
              category: 'naked', licenseGroup: 'A2', minPowerKw: 35, maxPowerKw: 70, availableTodayOnly: true, branch: kBranchVnId)));
    // As filters_on with days 7–9, and every availability answer takes 3 s
    // (a recount shows "Hledám…" until it arrives).
    case JourneyState.filtersSlow:
      return d(
          filter: _dated(const CatalogFilter(licenseGroup: 'A2', minPowerKw: 30, maxPowerKw: 60)), delay: 3000, start: '/search');
    // Trasy: 20 routes with photos (journey_routes.dart), opens /routes-list.
    case JourneyState.routesPhotos:
      return d(routes: true, start: '/routes-list');
    case JourneyState.routesFiltered:
      return d(routes: true, countries: const {'CZ'}, start: '/routes-list');
    default:
      throw ArgumentError('not a 5.0.1 state: ${s.id}');
  }
}
