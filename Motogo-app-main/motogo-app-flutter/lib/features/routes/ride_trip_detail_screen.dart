import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/theme.dart';
import '../../core/widgets/mg_nav_controls.dart';
import '../../core/widgets/state_views.dart';
import 'ride_card.dart';
import 'ride_live_stats.dart';
import 'ride_map.dart';
import 'ride_model.dart';
import 'ride_provider.dart';
import 'ride_share.dart';
import 'ride_stage_list.dart';
import 'ride_stats_grid.dart';
import 'ride_trip.dart';
import 'ride_trip_api.dart';
import 'ride_trip_ui.dart';

/// Detail cesty (sloučené jízdy / jízdy jedné výpůjčky) — SPEC §9.1: mapa
/// celé cesty, součty, etapy, sdílení, přejmenovat / rozdělit / smazat
/// a jízdy, ze kterých se skládá. Cesta se hledá podle svých jízd, takže
/// přežije přejmenování i změnu klíče; když už neexistuje, řekne to.
class RideTripDetailScreen extends ConsumerStatefulWidget {
  const RideTripDetailScreen({super.key, required this.rideId});

  /// Kterákoli jízda cesty (obvykle nejstarší).
  final String rideId;

  @override
  ConsumerState<RideTripDetailScreen> createState() => _RideTripDetailScreenState();
}

class _RideTripDetailScreenState extends ConsumerState<RideTripDetailScreen> {
  late Set<String> _ids = {widget.rideId};
  bool _busy = false;

  RideTrip? _find(List<UserRide> rides) {
    RideTrip? best;
    for (final i in groupRides(rides)) {
      if (i is! RideListItemTrip) continue;
      final has = i.trip.rides.map((r) => r.id).toSet();
      if (has.contains(widget.rideId)) return i.trip;
      if (best == null && has.any(_ids.contains)) best = i.trip;
    }
    return best;
  }

  Iterable<String?> _bookings(RideTrip t) => t.rides.map((r) => r.bookingId);

  Future<void> _run(Future<void> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename(RideTrip trip) async {
    final tr = t(context);
    final name = await rideTripNameDialog(context, initial: trip.name, title: tr.tr('rpTripRename'));
    if (name == null || !mounted) return;
    await _run(() async {
      final op = await rideTripApply(ref, rideTripRenamePlan(trip, name), bookingIds: _bookings(trip));
      if (mounted && !op.ok) rideTripShowResult(ScaffoldMessenger.of(context), tr, op.result);
    });
  }

  /// Rozdělit cestu → zpět na seznam s hláškou a „Zpět".
  Future<void> _split(RideTrip trip, {bool confirm = true}) async {
    final tr = t(context);
    if (confirm &&
        !await rideConfirm(context,
            title: tr.tr('rpTripSplit'), body: tr.tr('rpTripSplitQ'), confirm: tr.tr('rpTripSplit'))) {
      return;
    }
    if (!mounted) return;
    await _run(() async {
      final op = await rideTripApply(ref, rideTripSplitPlan(trip), bookingIds: _bookings(trip));
      if (!mounted) return;
      rideTripSnack(context, op, 'rpTripSplitDone', bookingIds: _bookings(trip));
      if (op.ok) Navigator.of(context).maybePop();
    });
  }

  Future<void> _delete(RideTrip trip) async {
    final tr = t(context);
    final choice = await rideTripDeleteSheet(context);
    if (choice == null || !mounted) return;
    if (choice == RideTripDeleteChoice.split) return _split(trip, confirm: false);
    final ok = await rideConfirm(context,
        title: tr.tr('rpTripDelete'),
        body: tr.trArgs('rpTripDeleteQ', {'n': trip.rides.length}),
        confirm: tr.tr('myExpDelete'),
        danger: true);
    if (!ok || !mounted) return;
    await _run(() async {
      final msg = ScaffoldMessenger.of(context);
      final r = await rideTripDeleteAll(ref, trip);
      if (r == RideTripOpResult.ok) {
        msg
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(tr.tr('rpTripDeleted'))));
        if (mounted) Navigator.of(context).maybePop();
      } else {
        rideTripShowResult(msg, tr, r);
      }
    });
  }

  Future<void> _visibility(RideTrip trip, bool public) => _run(() async {
        final tr = t(context);
        final msg = ScaffoldMessenger.of(context);
        final r = await rideTripSetVisibility(ref, trip, public);
        rideTripShowResult(msg, tr, r);
      });

  void _share(RideTrip trip) =>
      showRideShareSheet(context, trip.aggregate, text: rideTripShareText(context, trip));

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final rides = ref.watch(myRidesProvider);
    void back() => Navigator.of(context).maybePop();
    return rides.when(
      loading: () => MgStateScaffold(
          onBack: back,
          child: MgLoadingView(
              color: MotoGoColors.greenDark, onRetry: () => ref.invalidate(myRidesProvider), onBack: back)),
      error: (e, _) => MgStateScaffold(
          onBack: back,
          child: MgErrorView(
              error: e, what: tr.tr('eoRideLoadFail'), onRetry: () => ref.invalidate(myRidesProvider), onBack: back)),
      data: (list) {
        final trip = _find(list);
        if (trip == null) {
          return MgStateScaffold(
              onBack: back,
              child: MgErrorView(message: tr.tr('rpTripGone'), what: tr.tr('rpTripChip'), contact: false, onBack: back));
        }
        _ids = trip.rides.map((r) => r.id).toSet();
        return _view(context, trip);
      },
    );
  }

  Widget _view(BuildContext context, RideTrip trip) {
    final tr = t(context);
    final a = trip.aggregate;
    return Scaffold(
      backgroundColor: MotoGoColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _header(context, trip),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
              if (a.mapPoints.length >= 2)
                ClipRRect(
                  borderRadius: BorderRadius.circular(MotoGoRadius.card),
                  child: SizedBox(
                    height: 260,
                    child: RideTrackMap(track: a.track, segments: a.segments, points: a.points, interactive: true),
                  ),
                ),
              const SizedBox(height: 12),
              RideStatsGrid(ride: a, showText: false),
              const SizedBox(height: 12),
              RideStageList(stages: rideTripStages(trip)),
              const SizedBox(height: 12),
              _card(Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr.tr('rideVisibility'), style: _title),
                    const SizedBox(height: 2),
                    Text(tr.tr(trip.isPublic ? 'rpTripVisibilityOn' : 'rpTripVisibilityOff'), style: _sub),
                  ]),
                ),
                Switch(
                  value: trip.isPublic,
                  activeColor: MotoGoColors.greenDark,
                  onChanged: _busy ? null : (v) => _visibility(trip, v),
                ),
              ])),
              const SizedBox(height: 12),
              _card(Column(children: [
                _action(Icons.edit_outlined, tr.tr('rpTripRename'), () => _rename(trip)),
                _action(Icons.call_split, tr.tr('rpTripSplit'), () => _split(trip)),
                _action(Icons.delete_outline, tr.tr('rpTripDelete'), () => _delete(trip), danger: true),
              ]), pad: const EdgeInsets.symmetric(vertical: 4)),
              const SizedBox(height: 16),
              Semantics(header: true, child: Text(tr.tr('rpTripMembers'), style: _title.copyWith(fontSize: MotoGoTypo.sizeXl))),
              const SizedBox(height: 10),
              for (final r in trip.rides.reversed)
                RideCard(ride: r, siblingIds: [for (final x in trip.rides.reversed) x.id]),
            ]),
          ),
        ]),
      ),
    );
  }

  static const _title = TextStyle(
      fontSize: MotoGoTypo.sizeLg, fontWeight: MotoGoTypo.w800, color: MotoGoColors.black, decoration: TextDecoration.none);
  static const _sub = TextStyle(
      fontSize: MotoGoTypo.sizeMd,
      fontWeight: MotoGoTypo.w600,
      color: MotoGoColors.g500,
      height: 1.35,
      decoration: TextDecoration.none);

  Widget _card(Widget child, {EdgeInsets pad = const EdgeInsets.fromLTRB(14, 10, 8, 10)}) => Container(
        padding: pad,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(MotoGoRadius.card),
          boxShadow: MotoGoShadows.cardSmall,
        ),
        child: child,
      );

  Widget _action(IconData icon, String label, VoidCallback onTap, {bool danger = false}) => ListTile(
        enabled: !_busy,
        minVerticalPadding: 10,
        leading: Icon(icon, color: danger ? MotoGoColors.red : MotoGoColors.greenDarker),
        title: Text(label, style: _title.copyWith(color: danger ? MotoGoColors.red : MotoGoColors.black)),
        onTap: onTap,
      );

  Widget _header(BuildContext context, RideTrip trip) {
    final tr = t(context);
    final days = trip.days;
    final sub = [rideDateRange(trip.from, trip.to), if (days >= 2) rideDaysLabel(days, tr)].join(' · ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 16),
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
                color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(MotoGoRadius.lg)),
            child: const Icon(Icons.arrow_back, size: 20, color: Colors.white),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Semantics(
            button: true,
            label: '${tr.tr('rpTripRename')}: ${rideTripDefaultName(trip, tr)}',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _busy ? null : () => _rename(trip),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${trip.isRental ? '🏍️' : '🧳'} ${rideTripDefaultName(trip, tr)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: MotoGoTypo.sizeH2,
                        fontWeight: MotoGoTypo.w900,
                        color: Colors.white,
                        decoration: TextDecoration.none)),
                const SizedBox(height: 2),
                Text(sub,
                    style: const TextStyle(
                        fontSize: MotoGoTypo.sizeBase,
                        fontWeight: MotoGoTypo.w600,
                        color: Color(0xFF8AAB99),
                        decoration: TextDecoration.none)),
              ]),
            ),
          ),
        ),
        _hdrBtn(Icons.ios_share, () => _share(trip), tr.tr('rpTripShare')),
        _hdrBtn(Icons.delete_outline, () => _delete(trip), tr.tr('rpTripDelete'), color: const Color(0xFFFF9B9B)),
      ]),
    );
  }

  Widget _hdrBtn(IconData icon, VoidCallback onTap, String label, {Color color = Colors.white}) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkResponse(
          onTap: _busy ? null : onTap,
          radius: 24,
          child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 22, color: color)),
        ),
      );
}
