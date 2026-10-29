import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/icons/mg_icon.dart';
import '../../../../core/v2/widgets/mg_buttons.dart';
import '../../../../core/v2/widgets/mg_dialog.dart';
import '../../../../core/v2/widgets/mg_inputs.dart';
import '../../../../core/v2/widgets/mg_toast.dart';
import '../../ride_server_api.dart';
import '../../ride_trip.dart';
import '../../ride_trip_api.dart';

/// v2 trip operations (SPEC §8.3) on top of the shared plans in
/// `ride_trip_api.dart`: every operation keeps its undo map and the toast
/// offers "Zpět" — the undo runs through the app-wide provider container,
/// so it still works after the screen that started it was closed.

typedef TripSetFn = RideTripSetFn;
typedef TripVisibilityFn = Future<RideTripOpResult> Function(WidgetRef ref, RideTrip trip, bool public);
typedef TripDeleteFn = Future<RideTripOpResult> Function(WidgetRef ref, RideTrip trip);

/// Seams (tests override them): `set_user_rides_trip`, per-ride visibility,
/// delete of all rides — the app uses the shared functions.
final tripSetSeamV2 = Provider<TripSetFn>((ref) => setUserRidesTrip);
final tripVisibilitySeamV2 = Provider<TripVisibilityFn>((ref) => rideTripSetVisibility);
final tripDeleteSeamV2 = Provider<TripDeleteFn>((ref) => rideTripDeleteAll);

/// Runs [plan] on the server and refreshes the ride lists — the shared
/// `rideTripApplyIn` (same result rules as the old look), with the v2 seam.
Future<RideTripOp> tripApplyV2(WidgetRef ref, RideTripPlan plan) {
  final c = rideTripContainer(ref);
  return rideTripApplyIn(c, plan, set: c.read(tripSetSeamV2));
}

/// What went wrong + how to fix it (v2 texts).
String tripErrorKeyV2(RideTripOpResult r) => switch (r) {
      RideTripOpResult.partial => 'v2RpTripPartial',
      RideTripOpResult.unavailable => 'v2RpTripUnavailable',
      _ => 'v2RpTripFailed',
    };

void showTripErrorV2(BuildContext context, RideTripOpResult r) =>
    showMgToast(context, t(context).tr(tripErrorKeyV2(r)), icon: MgIcons.alert);

/// Confirmation toast with "Zpět" (when [undo] has anything to restore).
void showTripDoneV2(BuildContext context, String message, {RideTripUndo? undo}) {
  final tr = t(context);
  final c = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final canUndo = undo != null && undo.isNotEmpty;
  showMgToast(
    context,
    message,
    actionLabel: canUndo ? tr.tr('v2RpUndo') : null,
    onAction: !canUndo
        ? null
        : () async {
            final r = (await rideTripApplyIn(c, rideTripUndoPlan(undo), set: c.read(tripSetSeamV2))).result;
            messenger?.showSnackBar(SnackBar(
              content: Text(tr.tr(r == RideTripOpResult.ok ? 'v2RpUndone' : tripErrorKeyV2(r))),
            ));
          },
  );
}

/// "Pojmenuj cestu" — returns the typed name ('' = default name by dates),
/// null = cancelled.
Future<String?> askTripNameV2(BuildContext context, {String initial = '', String? title}) => showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _TripNameDialog(initial: initial, title: title),
    );

class _TripNameDialog extends StatefulWidget {
  final String initial;
  final String? title;
  const _TripNameDialog({required this.initial, this.title});

  @override
  State<_TripNameDialog> createState() => _TripNameDialogState();
}

class _TripNameDialogState extends State<_TripNameDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return MgDialogFrame(
      title: widget.title ?? tr.tr('v2RpMergeNameTitle'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _ctrl,
          autofocus: true,
          maxLength: 120,
          textCapitalization: TextCapitalization.sentences,
          decoration: mgInputDecoration(context,
              label: tr.tr('v2RpMergeNameLabel'), hint: tr.tr('v2RpMergeNameHint'), helper: tr.tr('v2RpMergeNameSub')),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
      ]),
      safeLabel: tr.cancel,
      actionLabel: tr.tr('ridePointSave'),
      safe: MgBtnGhostLight(label: tr.cancel, onTap: () => Navigator.pop(context)),
      action: MgBtnInk(label: tr.tr('ridePointSave'), neonLabel: true, onTap: () => Navigator.pop(context, _ctrl.text.trim())),
    );
  }
}
