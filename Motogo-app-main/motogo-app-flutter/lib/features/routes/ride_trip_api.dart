import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ride_model.dart';
import 'ride_provider.dart';
import 'ride_recorder.dart';
import 'ride_server_api.dart';
import 'ride_trip.dart';

/// Operace s cestami (SPEC §8.3) — sloučit, rozdělit, přejmenovat, přidat,
/// vyjmout, ZPĚT. Každá si PŘED voláním uloží „undo mapu" (předchozí
/// `trip_id`/`trip_name` všech dotčených jízd); „Zpět" ji pošle zpátky.
/// Plánovací funkce jsou čisté (testují se), I/O je v [rideTripApply].

/// Předchozí stav dotčených jízd: id → (trip_id, trip_name).
typedef RideTripUndo = Map<String, ({String? tripId, String? tripName})>;

enum RideTripOpResult { ok, partial, unavailable, failed }

/// i18n klíč hlášky výsledku (null = OK, ukaž vlastní potvrzení + Zpět).
String? rideTripResultKey(RideTripOpResult r) => switch (r) {
      RideTripOpResult.ok => null,
      RideTripOpResult.partial => 'rpTripPartial',
      RideTripOpResult.unavailable => 'rpTripUnavailable',
      RideTripOpResult.failed => 'rpTripFailed',
    };

/// Výsledek operace + undo mapa pro „Zpět".
class RideTripOp {
  const RideTripOp(this.result, this.undo, {this.items = const []});
  final RideTripOpResult result;
  final RideTripUndo undo;
  final List<RideTripItem> items;
  bool get ok => result == RideTripOpResult.ok;
  String? get messageKey => rideTripResultKey(result);
}

/// Plán operace: co se pošle + jak to vrátit.
typedef RideTripPlan = ({List<RideTripItem> items, RideTripUndo undo});

RideTripUndo rideTripUndoOf(Iterable<UserRide> rides) =>
    {for (final r in rides) r.id: (tripId: r.tripId, tripName: r.tripName)};

List<UserRide> _members(RideListItem i) => switch (i) {
      RideListItemRide(:final ride) => [ride],
      RideListItemTrip(:final trip) => trip.rides,
    };

String _leaderId(Iterable<UserRide> rides) =>
    (rides.toList()..sort((a, b) => a.startedAt.compareTo(b.startedAt))).first.id;

String? _clean(String? name) {
  final n = name?.trim();
  if (n == null || n.isEmpty) return null;
  return n.length > 120 ? n.substring(0, 120) : n;
}

/// Sloučit vybrané položky (jízdy i celé cesty) do jedné cesty. Klíč =
/// explicitní cesta nejstarší vybrané explicitní cesty, jinak id nejstarší
/// jízdy. [name] prázdné = výchozí název (dopočítá appka).
RideTripPlan rideTripMergePlan(List<RideListItem> selected, String? name) {
  final rides = [for (final i in selected) ..._members(i)];
  final trips = [
    for (final i in selected)
      if (i is RideListItemTrip && i.trip.explicitTripId != null) i.trip,
  ]..sort((a, b) => a.from.compareTo(b.from));
  final key = trips.isNotEmpty ? trips.first.explicitTripId! : _leaderId(rides);
  final n = _clean(name);
  return (
    items: [for (final r in rides) RideTripItem(r.id, key, n)],
    undo: rideTripUndoOf(rides),
  );
}

/// Rozdělit cestu na samostatné jízdy (i implicitní skupinu výpůjčky).
RideTripPlan rideTripSplitPlan(RideTrip t) => (
      items: [for (final r in t.rides) RideTripItem(r.id, r.id, null)],
      undo: rideTripUndoOf(t.rides),
    );

/// Přejmenovat cestu (implicitní skupina se tím stane explicitní).
RideTripPlan rideTripRenamePlan(RideTrip t, String name) {
  final key = t.explicitTripId ?? t.leader.id;
  final n = _clean(name);
  return (
    items: [for (final r in t.rides) RideTripItem(r.id, key, n)],
    undo: rideTripUndoOf(t.rides),
  );
}

/// Přidat jízdu do cesty (u implicitní skupiny dostanou explicitní klíč
/// i ostatní členové).
RideTripPlan rideTripAddPlan(RideTrip t, UserRide ride) {
  final key = t.explicitTripId ?? t.leader.id;
  final touched = [if (t.explicitTripId == null) ...t.rides, ride];
  return (
    items: [for (final r in touched) RideTripItem(r.id, key, t.name)],
    undo: rideTripUndoOf(touched),
  );
}

/// Vyjmout jízdu z cesty (zůstane samostatná).
RideTripPlan rideTripRemovePlan(UserRide ride) => (
      items: [RideTripItem(ride.id, ride.id, null)],
      undo: rideTripUndoOf([ride]),
    );

/// „Zpět": vrátit přesně předchozí stav.
RideTripPlan rideTripUndoPlan(RideTripUndo undo) => (
      items: [for (final e in undo.entries) RideTripItem(e.key, e.value.tripId, e.value.tripName)],
      undo: const {},
    );

/// Volání `set_user_rides_trip` (v2 testy ho přepisují vlastním).
typedef RideTripSetFn = Future<RideTripSetResult> Function(List<RideTripItem> items);

/// Výsledek `set_user_rides_trip` → výsledek operace (jediné mapování pro
/// starý vzhled, v2 i „Zpět"): vše uloženo = ok, méně = partial, starý
/// server = unavailable, offline / chyba = failed.
RideTripOpResult rideTripResultOf(RideTripSetResult res, int sent) => switch (res.kind) {
      RideTripSetKind.ok => res.updated >= sent ? RideTripOpResult.ok : RideTripOpResult.partial,
      RideTripSetKind.missing => RideTripOpResult.unavailable,
      RideTripSetKind.offline || RideTripSetKind.error => RideTripOpResult.failed,
    };

/// Obnoví seznamy jízd: „Moje jízdy" + jízdy u výpůjček ([bookingIds],
/// null = u všech).
void rideTripRefresh(ProviderContainer c, [Iterable<String?>? bookingIds]) {
  c.invalidate(myRidesProvider);
  if (bookingIds == null) {
    c.invalidate(bookingRidesProvider);
    return;
  }
  for (final b in bookingIds.toSet()) {
    if (b != null) c.invalidate(bookingRidesProvider(b));
  }
}

/// Kontejner aplikace z `ref` obrazovky — vzít HNED, před prvním `await`
/// (obrazovka se mezitím může zavřít a její `ref` by už neplatil).
ProviderContainer rideTripContainer(WidgetRef ref) =>
    ProviderScope.containerOf(ref.context, listen: false);

/// Provede plán na serveru přes kontejner aplikace a obnoví seznamy —
/// funguje i po zavření obrazovky (např. „Zpět" ze snackbaru).
Future<RideTripOp> rideTripApplyIn(ProviderContainer c, RideTripPlan plan,
    {Iterable<String?>? bookingIds, RideTripSetFn set = setUserRidesTrip}) async {
  final res = await set(plan.items);
  if (res.kind == RideTripSetKind.ok) rideTripRefresh(c, bookingIds);
  return RideTripOp(rideTripResultOf(res, plan.items.length), plan.undo, items: plan.items);
}

/// Provede plán na serveru (`set_user_rides_trip`) a obnoví seznamy.
Future<RideTripOp> rideTripApply(WidgetRef ref, RideTripPlan plan, {Iterable<String?> bookingIds = const []}) =>
    rideTripApplyIn(rideTripContainer(ref), plan, bookingIds: bookingIds);

/// Sdílení celé cesty (přepínač platí pro všechny její jízdy).
Future<RideTripOpResult> rideTripSetVisibility(WidgetRef ref, RideTrip t, bool public) =>
    rideTripSetVisibilityIn(rideTripContainer(ref), t, public);

Future<RideTripOpResult> rideTripSetVisibilityIn(ProviderContainer c, RideTrip t, bool public) async {
  var ok = 0;
  for (final r in t.rides) {
    if (await updateUserRide(r.id, visibility: public ? 'public' : 'private')) ok++;
  }
  rideTripRefresh(c, t.rides.map((r) => r.bookingId));
  if (ok == t.rides.length) return RideTripOpResult.ok;
  return ok == 0 ? RideTripOpResult.failed : RideTripOpResult.partial;
}

/// Smazat cestu i se všemi jízdami (po potvrzení `rpTripDeleteQ`). Právě
/// nahrávanou jízdu nejdřív odpojí záznamník (bez ukončení na serveru).
Future<RideTripOpResult> rideTripDeleteAll(WidgetRef ref, RideTrip t) =>
    rideTripDeleteAllIn(rideTripContainer(ref), t);

Future<RideTripOpResult> rideTripDeleteAllIn(ProviderContainer c, RideTrip t) async {
  final rec = c.read(rideRecorderProvider);
  if (t.rides.any((r) => r.id == rec.rideId)) {
    await c.read(rideRecorderProvider.notifier).discardCurrent();
  }
  var ok = 0;
  for (final r in t.rides) {
    if (await deleteUserRide(r.id)) ok++;
  }
  rideTripRefresh(c, t.rides.map((r) => r.bookingId));
  if (ok == t.rides.length) return RideTripOpResult.ok;
  return ok == 0 ? RideTripOpResult.failed : RideTripOpResult.partial;
}
