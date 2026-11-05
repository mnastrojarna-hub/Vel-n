import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/chrome/mg_dock.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/motion/mg_anim.dart';
import '../../../../core/v2/states/mg_state_banner.dart';
import '../../../../core/v2/states/mg_tone.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_back_v2.dart';
import '../../../../core/v2/widgets/mg_cta.dart';
import '../../../../core/v2/widgets/mg_skeleton.dart';
import '../../../../core/v2/widgets/mg_word_fit.dart';
import '../../../../core/widgets/state_views.dart' show MgErrorView;
import '../../ride_card.dart' show rideKm;
import '../../ride_model.dart';
import '../../ride_provider.dart' show myRidesProvider;
import '../../ride_trip.dart';
import '../../ride_trip_api.dart';
import 'moje_tabs_v2.dart' show MojeEmptyV2;
import 'ride_phase_v2.dart';
import 'ride_track_sketch_v2.dart';
import 'ride_trip_card_v2.dart' show tripNameV2;
import 'trip_actions_v2.dart';

/// Opens "Sloučit jízdy" ([preselectRideId] = "Přidat do cesty…" from a ride).
Future<void> openRideMergeV2(BuildContext context, {String? preselectRideId}) =>
    Navigator.of(context, rootNavigator: true)
        .push(MaterialPageRoute<void>(builder: (_) => RideMergeScreenV2(preselectRideId: preselectRideId)));

/// Key of a list item in the selection (stable across refreshes).
String mergeItemKeyV2(RideListItem i) => switch (i) {
      RideListItemRide(:final ride) => 'ride:${ride.id}',
      RideListItemTrip(:final trip) => 'trip:${trip.leader.id}',
    };

/// "Sloučit jízdy" (SPEC §8.3 / §9.2; old-look rules in the v2 frame):
/// what merging does, every ride / trip with a 44 px checkbox, the
/// SLOUČIT (n) dock (from two), the name question (empty = by dates), then
/// back with "Jízdy jsou sloučené" + Zpět. Failure stays here with what /
/// why / fix.
class RideMergeScreenV2 extends ConsumerStatefulWidget {
  final String? preselectRideId;
  const RideMergeScreenV2({super.key, this.preselectRideId});

  @override
  ConsumerState<RideMergeScreenV2> createState() => _RideMergeScreenV2State();
}

class _RideMergeScreenV2State extends ConsumerState<RideMergeScreenV2> {
  final Set<String> _sel = {};
  bool _preselected = false;
  bool _busy = false;
  RideTripOpResult? _error;

  void _toggle(RideListItem i) => setState(() {
        final k = mergeItemKeyV2(i);
        if (!_sel.remove(k)) _sel.add(k);
        _error = null;
      });

  Future<void> _merge(List<RideListItem> items) async {
    final chosen = [for (final i in items) if (_sel.contains(mergeItemKeyV2(i))) i];
    if (chosen.length < 2 || _busy) return;
    final name = await askTripNameV2(context);
    if (name == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final op = await tripApplyV2(ref, rideTripMergePlan(chosen, name));
    if (!mounted) return;
    setState(() => _busy = false);
    if (!op.ok) {
      setState(() => _error = op.result);
      return;
    }
    showTripDoneV2(context, t(context).tr('v2RpMergeDone'), undo: op.undo);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final async = ref.watch(myRideItemsProvider);
    final items = async.valueOrNull ?? const <RideListItem>[];
    if (!_preselected && async.hasValue) {
      _preselected = true;
      final id = widget.preselectRideId;
      for (final i in items) {
        final rides = switch (i) { RideListItemRide(:final ride) => [ride], RideListItemTrip(:final trip) => trip.rides };
        if (id != null && rides.any((r) => r.id == id)) _sel.add(mergeItemKeyV2(i));
      }
    }
    final n = items.where((i) => _sel.contains(mergeItemKeyV2(i))).length;

    final Widget body = async.when(
      loading: () => ListView(padding: const EdgeInsets.all(16), children: const [
        MgSkeletonCard(imageHeight: 56),
        SizedBox(height: 10),
        MgSkeletonCard(imageHeight: 56),
      ]),
      error: (e, _) => ListView(padding: const EdgeInsets.all(16), children: [
        MgErrorView(compact: true, error: e, what: tr.tr('v2RpMergeLoadFail'), onRetry: () => ref.invalidate(myRidesProvider)),
      ]),
      data: (items) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Text(tr.tr('v2RpMergeHint'), style: MgType.body.copyWith(color: MgColors.body2)),
          const SizedBox(height: 12),
          if (_error != null) ...[
            MgStateBanner(tone: MgTone.err, icon: MgIcons.alert, title: tr.tr('v2RpMergeFailTitle'), text: tr.tr(tripErrorKeyV2(_error!))),
            const SizedBox(height: 12),
          ],
          if (items.length < 2)
            MojeEmptyV2(icon: MgIcons.route, title: tr.tr('v2RpMergeEmpty'), text: tr.tr('v2RpMergeEmptySub'))
          else
            for (final i in items)
              _MergeTile(item: i, selected: _sel.contains(mergeItemKeyV2(i)), onTap: _busy ? null : () => _toggle(i)),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: MgColors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 16, 6),
            child: Row(children: [
              MgV2Back(onTap: () => Navigator.of(context).maybePop(), style: MgBackStyle.light),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  header: true,
                  child: MgWordFit(minScale: 0.75, child: Text(tr.tr('v2RpMergeTitle'), maxLines: 2, style: MgType.h3.copyWith(color: MgColors.ink))),
                ),
              ),
            ]),
          ),
          Expanded(child: body),
          if (items.length >= 2)
            MgDock(
              contextLine: Text(
                n < 2 ? tr.tr('v2RpMergeMinTwo') : recRidesV2(tr, _countRides(items)),
                style: MgType.small.copyWith(fontWeight: FontWeight.w700, color: MgColors.onDarkLead),
              ),
              child: MgCta(
                label: tr.trArgs('v2RpMergeBtn', {'n': n}),
                enabled: n >= 2,
                busy: _busy,
                onTap: n >= 2 ? () => _merge(items) : null,
              ),
            ),
        ]),
      ),
    );
  }

  int _countRides(List<RideListItem> items) => items
      .where((i) => _sel.contains(mergeItemKeyV2(i)))
      .fold(0, (s, i) => s + switch (i) { RideListItemRide() => 1, RideListItemTrip(:final trip) => trip.rides.length });
}

class _MergeTile extends StatelessWidget {
  final RideListItem item;
  final bool selected;
  final VoidCallback? onTap;
  const _MergeTile({required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final (UserRide r, String name, String? tag) = switch (item) {
      RideListItemRide(:final ride) => (ride, ride.name.isNotEmpty ? ride.name : tr.tr('rideUntitled'), null),
      RideListItemTrip(:final trip) => (
          trip.aggregate,
          tripNameV2(tr, trip),
          tr.trArgs('v2RpTripCard', {'days': recDaysV2(tr, trip.days)})
        ),
    };
    final range = rideDateRange(r.startedAt, r.endedAt ?? r.lastFixAt ?? r.startedAt);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        checked: selected,
        label: '$name, $range, ${rideKm(r.distanceKm)}',
        excludeSemantics: true,
        child: MgPress(
          scale: 0.98,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
            decoration: BoxDecoration(
              color: selected ? MgColors.tintFeatureA : MgColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? MgColors.neonLo : MgColors.line, width: selected ? 1.5 : 1),
            ),
            child: Row(children: [
              RideTrackSketch(ride: r, size: 56),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (tag != null) ...[
                    RideBadgeV2(kind: RideBadgeKind.trip, label: tag),
                    const SizedBox(height: 4),
                  ],
                  MgWordFit(
                    minScale: 0.8,
                    child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: MgType.title.copyWith(color: MgColors.ink)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [range, rideKm(r.distanceKm), if (item case RideListItemTrip(:final trip)) recRidesV2(tr, trip.rides.length)].join(' · '),
                    style: MgType.tab(MgType.small.copyWith(color: MgColors.meta)),
                  ),
                ]),
              ),
              SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: selected ? MgColors.neon : MgColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: selected ? MgColors.neonLo : MgColors.lineInput, width: 2),
                    ),
                    child: selected ? const Center(child: MgIcon(MgIcons.check, size: 16, color: MgColors.onNeon, stroke: 2.8)) : null,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
