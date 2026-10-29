import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/theme.dart';
import '../../core/widgets/mg_nav_controls.dart';
import '../../core/widgets/state_views.dart';
import 'ride_card.dart' show rideKm;
import 'ride_fit_text.dart';
import 'ride_live_stats.dart';
import 'ride_model.dart';
import 'ride_provider.dart';
import 'ride_trip.dart';
import 'ride_trip_api.dart';
import 'ride_trip_ui.dart';

/// „Sloučit jízdy" (SPEC §8.3, §9.1): výběr jízd / cest, které patří k jedné
/// cestě → název → `set_user_rides_trip`. Po úspěchu hláška se „Zpět".
/// Jízdy se nemažou ani nemění, jen se zobrazí jako jedna cesta.
class RideMergeScreen extends ConsumerStatefulWidget {
  const RideMergeScreen({super.key, this.preselectRideId});

  /// Jízda předvybraná z detailu („Přidat do cesty…").
  final String? preselectRideId;

  @override
  ConsumerState<RideMergeScreen> createState() => _RideMergeScreenState();
}

/// Stabilní klíč položky výběru (cesta = podle nejstarší jízdy).
String _itemKey(RideListItem i) => switch (i) {
      RideListItemRide(:final ride) => 'R:${ride.id}',
      RideListItemTrip(:final trip) => 'T:${trip.leader.id}',
    };

List<UserRide> _members(RideListItem i) => switch (i) {
      RideListItemRide(:final ride) => [ride],
      RideListItemTrip(:final trip) => trip.rides,
    };

class _RideMergeScreenState extends ConsumerState<RideMergeScreen> {
  final Set<String> _sel = {};
  bool _preDone = false;
  bool _busy = false;

  void _preselect(List<RideListItem> items) {
    if (_preDone) return;
    _preDone = true;
    final id = widget.preselectRideId;
    if (id == null) return;
    for (final i in items) {
      if (_members(i).any((r) => r.id == id)) _sel.add(_itemKey(i));
    }
  }

  Future<void> _merge(List<RideListItem> items) async {
    final tr = t(context);
    final msg = ScaffoldMessenger.of(context);
    final chosen = [for (final i in items) if (_sel.contains(_itemKey(i))) i];
    if (chosen.length < 2) {
      msg
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(tr.tr('rpMergeMinTwo'))));
      return;
    }
    String? existing;
    for (final i in chosen) {
      if (i is RideListItemTrip && i.trip.explicitTripId != null) existing ??= i.trip.name;
    }
    final name = await rideTripNameDialog(context, initial: existing, title: tr.tr('rpMergeNameTitle'));
    if (name == null || !mounted) return;
    setState(() => _busy = true);
    final bookings = [for (final i in chosen) ..._members(i).map((r) => r.bookingId)];
    final op = await rideTripApply(ref, rideTripMergePlan(chosen, name), bookingIds: bookings);
    if (!mounted) return;
    setState(() => _busy = false);
    rideTripSnack(context, op, 'rpMergeDone', bookingIds: bookings);
    if (op.ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final rides = ref.watch(myRidesProvider);
    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _header(context),
          Expanded(
            child: rides.when(
              loading: () => MgLoadingView(
                  color: MotoGoColors.greenDark, onRetry: () => ref.invalidate(myRidesProvider)),
              error: (e, _) => MgErrorView(
                  error: e, what: tr.tr('eoRideLoadFail'), onRetry: () => ref.invalidate(myRidesProvider)),
              data: (list) {
                final items = groupRides(list);
                _preselect(items);
                return _body(context, list, items);
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _body(BuildContext context, List<UserRide> rides, List<RideListItem> items) {
    final tr = t(context);
    final ok = items.length >= 2;
    // Server cesty ještě nezná → výběr ani tlačítko nejdou použít (dřív šlo
    // vybírat a chyba přišla až po klepnutí na Sloučit); hláška zůstává.
    final server = rides.any((r) => r.serverV2);
    final n = server ? _sel.length : 0;
    final can = server && !_busy;
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
          Text(tr.tr('rpMergeHint'), style: _hint),
          if (!server) ...[const SizedBox(height: 10), _note(tr.tr('rpTripUnavailable'))],
          if (!ok) ...[const SizedBox(height: 10), _note(tr.tr('rpMergeNothing'))],
          const SizedBox(height: 12),
          for (final i in items) _row(context, i, enabled: server),
        ]),
      ),
      if (ok)
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            color: Colors.white,
            child: Semantics(
              button: true,
              enabled: n >= 2 && can,
              label: tr.trArgs('rpMergeBtn', {'n': n}),
              excludeSemantics: true,
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: n >= 2 ? MotoGoColors.green : MotoGoColors.g200,
                    foregroundColor: MotoGoColors.black,
                    disabledBackgroundColor: MotoGoColors.g200,
                    disabledForegroundColor: MotoGoColors.g400,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MotoGoRadius.pill)),
                  ),
                  // Pod 2 jízdy tlačítko vypadá vypnutě, ale klepnutí řekne proč.
                  onPressed: can ? () => _merge(items) : null,
                  child: _busy
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
                      // Jeden řádek — na úzkém telefonu se zmenší, nezalomí.
                      : rideFitLabel(tr.trArgs('rpMergeBtn', {'n': n}),
                          style: const TextStyle(fontSize: MotoGoTypo.sizeXl, fontWeight: MotoGoTypo.w900)),
                ),
              ),
            ),
          ),
        ),
    ]);
  }

  static const _hint = TextStyle(
      fontSize: MotoGoTypo.sizeBase,
      fontWeight: MotoGoTypo.w600,
      color: MotoGoColors.g600,
      height: 1.4,
      decoration: TextDecoration.none);

  Widget _note(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MotoGoColors.amberBg,
          border: Border.all(color: MotoGoColors.amberBorder),
          borderRadius: BorderRadius.circular(MotoGoRadius.xl),
        ),
        child: Text(text, style: _hint.copyWith(color: const Color(0xFF78350F))),
      );

  Widget _row(BuildContext context, RideListItem i, {bool enabled = true}) {
    final tr = t(context);
    final key = _itemKey(i);
    final sel = enabled && _sel.contains(key);
    final (title, sub) = switch (i) {
      RideListItemRide(:final ride) => (
          ride.name.isNotEmpty ? ride.name : tr.tr('rideUntitled'),
          [
            rideDateRange(ride.startedAt, ride.endedAt ?? ride.lastFixAt ?? ride.startedAt),
            rideKm(ride.distanceKm),
            if (ride.days >= 2) rideDaysLabel(ride.days, tr),
          ].join(' · ')
        ),
      RideListItemTrip(:final trip) => (
          '${trip.isRental ? '🏍️' : '🧳'} ${rideTripDefaultName(trip, tr)}',
          [
            rideDateRange(trip.from, trip.to),
            rideRidesLabel(trip.rides.length, tr),
            rideKm(trip.aggregate.distanceKm),
          ].join(' · ')
        ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        checked: sel,
        button: true,
        enabled: enabled,
        label: '$title, $sub',
        excludeSemantics: true,
        child: Material(
          color: sel ? MotoGoColors.greenPale : Colors.white,
          borderRadius: BorderRadius.circular(MotoGoRadius.xl),
          child: InkWell(
            borderRadius: BorderRadius.circular(MotoGoRadius.xl),
            onTap: _busy || !enabled ? null : () => setState(() => sel ? _sel.remove(key) : _sel.add(key)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
              child: Row(children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(sel ? Icons.check_box : Icons.check_box_outline_blank,
                      color: !enabled ? MotoGoColors.g200 : (sel ? MotoGoColors.greenDarker : MotoGoColors.g400)),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: MotoGoTypo.sizeLg,
                            fontWeight: MotoGoTypo.w800,
                            color: MotoGoColors.black,
                            decoration: TextDecoration.none)),
                    const SizedBox(height: 2),
                    Text(sub, style: _hint.copyWith(fontSize: MotoGoTypo.sizeMd)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 16, 14),
        decoration: const BoxDecoration(
          color: MotoGoColors.dark,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(MotoGoRadius.hdr)),
        ),
        child: Row(children: [
          MgBackTap(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(MotoGoRadius.lg),
              ),
              child: const Icon(Icons.arrow_back, size: 20, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              header: true,
              child: Text('🔗 ${t(context).tr('rpMerge')}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: MotoGoTypo.sizeH2,
                      fontWeight: MotoGoTypo.w900,
                      color: Colors.white,
                      decoration: TextDecoration.none)),
            ),
          ),
        ]),
      );
}
