import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/states/mg_state_screen.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_type.dart';
import '../../../../core/v2/widgets/mg_back_v2.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_dialog.dart';
import '../../../../core/v2/widgets/mg_sheet.dart';
import '../../../../core/v2/widgets/mg_skeleton.dart';
import '../../../../core/v2/widgets/mg_toast.dart';
import '../../../../core/widgets/state_views.dart' show MgErrorView;
import '../../ride_card.dart' show rideDuration, rideKm;
import '../../ride_provider.dart' show myRidesProvider;
import '../../ride_share.dart' show rideShareWaypoints;
import '../../ride_trip.dart';
import '../../ride_trip_api.dart';
import '../../route_export.dart';
import 'ride_phase_v2.dart';
import 'ride_share_v2.dart';
import 'ride_trip_card_v2.dart' show tripNameV2;
import 'trip_actions_v2.dart';
import 'trip_detail_view_v2.dart';

/// Opens the v2 trip detail (root navigator; back = pop).
Future<void> openTripDetailV2(BuildContext context, RideTrip trip) => Navigator.of(context, rootNavigator: true)
    .push(MaterialPageRoute<void>(builder: (_) => TripDetailScreenV2(leaderId: trip.leader.id)));

/// The trip of [leaderId] from the ride list (the key of a rental group
/// changes when it gets a name — the oldest ride does not).
RideTrip? tripOfV2(List<RideListItem> items, String leaderId) {
  for (final i in items) {
    if (i is RideListItemTrip && i.trip.rides.any((r) => r.id == leaderId)) return i.trip;
  }
  return null;
}

/// Trip detail screen (v2): reads `myRideItemsProvider`, renders
/// [TripDetailViewV2] and runs the trip operations (rename, share,
/// sharing switch, split, delete) — every one with a clear result and,
/// where it can be undone, "Zpět".
class TripDetailScreenV2 extends ConsumerStatefulWidget {
  final String leaderId;
  const TripDetailScreenV2({super.key, required this.leaderId});

  @override
  ConsumerState<TripDetailScreenV2> createState() => _TripDetailScreenV2State();
}

class _TripDetailScreenV2State extends ConsumerState<TripDetailScreenV2> {
  bool _busy = false;
  RideTripOpResult? _error;

  void _back() => Navigator.of(context).maybePop();

  Future<void> _op(RideTripPlan plan, String doneKey, {bool close = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final op = await tripApplyV2(ref, plan);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!op.ok) _error = op.result;
    });
    if (!op.ok) return;
    showTripDoneV2(context, t(context).tr(doneKey), undo: op.undo);
    if (close) _back();
  }

  Future<void> _rename(RideTrip trip) async {
    final tr = t(context);
    final name = await askTripNameV2(context, initial: trip.name ?? '', title: tr.tr('v2RpTripRename'));
    if (name == null || !mounted) return;
    await _op(rideTripRenamePlan(trip, name), 'v2RpTripRenamed');
  }

  Future<void> _split(RideTrip trip, {bool ask = true}) async {
    final tr = t(context);
    if (ask) {
      final ok = await showMgConfirm(
        context,
        title: tr.tr('v2RpTripSplitQ'),
        body: tr.tr('v2RpTripSplitBody'),
        safeLabel: tr.cancel,
        actionLabel: tr.tr('v2RpTripSplit'),
      );
      if (ok != true || !mounted) return;
    }
    await _op(rideTripSplitPlan(trip), 'v2RpTripSplitDone', close: true);
  }

  Future<void> _visibility(RideTrip trip, bool public) async {
    setState(() => _busy = true);
    final r = await ref.read(tripVisibilitySeamV2)(ref, trip, public);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != RideTripOpResult.ok) showTripErrorV2(context, r);
  }

  Future<void> _delete(RideTrip trip) async {
    final tr = t(context);
    final choice = await showMgSheet<String>(
      context,
      title: tr.tr('v2RpTripDeleteTitle'),
      builder: (c) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(tr.tr('v2RpTripDeleteOnlyGroupSub'), style: MgType.small.copyWith(color: MgColors.body2)),
        const SizedBox(height: 8),
        MgBtnInk(label: tr.tr('v2RpTripDeleteOnlyGroup'), icon: MgIcons.cut, neonLabel: true, onTap: () => Navigator.pop(c, 'group')),
        const SizedBox(height: 16),
        Text(tr.trArgs('v2RpTripDeleteAllSub', {'rides': recRidesV2(tr, trip.rides.length)}),
            style: MgType.small.copyWith(color: MgColors.body2)),
        const SizedBox(height: 8),
        MgBtnDestructive(label: tr.tr('v2RpTripDeleteAll'), onTap: () => Navigator.pop(c, 'all')),
      ]),
    );
    if (!mounted || choice == null) return;
    if (choice == 'group') return _split(trip, ask: false);
    final ok = await showMgConfirm(
      context,
      title: tr.tr('v2RpTripDeleteQ'),
      body: tr.trArgs('v2RpTripDeleteBody', {'rides': recRidesV2(tr, trip.rides.length)}),
      safeLabel: tr.cancel,
      actionLabel: tr.tr('v2RpTripDeleteAll'),
      destructive: true,
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final r = await ref.read(tripDeleteSeamV2)(ref, trip);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r == RideTripOpResult.ok) {
      showMgToast(context, tr.tr('v2RpTripDeleted'));
      _back();
    } else {
      showTripErrorV2(context, r);
    }
  }

  void _share(RideTrip trip, String name) {
    final tr = t(context);
    final a = trip.aggregate;
    final pts = rideShareWaypoints(a);
    final link = pts.length >= 2 ? RouteExport.mapy(pts).toString() : '';
    final text = [
      name,
      [
        rideDateRange(trip.from, trip.to),
        if (trip.days >= 2) recDaysV2(tr, trip.days),
        rideKm(a.distanceKm),
        if (a.movingSec > 0) tr.trArgs('v2RpChipRiding', {'time': rideDuration(a.movingMin)}),
      ].join(' · '),
      if (link.isNotEmpty) link,
      tr.tr('rideShareFooter'),
    ].join('\n');
    showRideShareSheetV2(context, text: text, link: link);
  }

  Widget _frame(Widget body) => Scaffold(
        backgroundColor: MgColors.canvas,
        body: SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: Align(alignment: AlignmentDirectional.centerStart, child: MgV2Back(onTap: _back, style: MgBackStyle.light)),
            ),
            Expanded(child: body),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final async = ref.watch(myRideItemsProvider);
    return async.when(
      loading: () => _frame(ListView(padding: const EdgeInsets.all(16), children: const [
        MgSkeletonCard(imageHeight: 200),
        SizedBox(height: 12),
        MgSkeletonCard(imageHeight: 72),
      ])),
      error: (e, _) => _frame(ListView(padding: const EdgeInsets.all(16), children: [
        MgErrorView(error: e, what: tr.tr('v2RpTripLoadFail'), onRetry: () => ref.invalidate(myRidesProvider)),
      ])),
      data: (items) {
        final trip = tripOfV2(items, widget.leaderId);
        if (trip == null) {
          return MgStateScreen(
            tone: MgTone.info,
            icon: MgIcons.route,
            title: tr.tr('v2RpTripGone'),
            why: tr.tr('v2RpTripGoneWhy'),
            support: false,
            onClose: _back,
            closeIsBack: true,
            primary: MgStateAction(tr.tr('v2RideBackToMine'), _back),
          );
        }
        final name = tripNameV2(tr, trip);
        return TripDetailViewV2(
          trip: trip,
          name: name,
          busy: _busy,
          error: _error,
          onBack: _back,
          onRename: () => _rename(trip),
          onShare: () => _share(trip, name),
          onDelete: () => _delete(trip),
          onSplit: () => _split(trip),
          onVisibility: (v) => _visibility(trip, v),
        );
      },
    );
  }
}
