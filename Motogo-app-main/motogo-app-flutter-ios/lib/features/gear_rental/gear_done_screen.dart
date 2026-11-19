import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart' show Routes;
import '../../core/v2/flag/v2_scope.dart';
import '../payment/payment_ui_helpers.dart' show isTopmostRoute;
import '../reservations/gear/gear_booking_api.dart';
import 'gear_contract.dart';
import 'gear_done_info.dart';
import 'gear_order_controller.dart' show gearForgetDraft, gearOrderUserProvider;
import 'v2/gear_done_view_v2.dart';
import 'widgets/gear_done_view.dart';

export 'gear_done_info.dart';

/// Načtení výpůjčky výbavy (`get_web_gear_booking`); testy ho podstrčí.
final gearDoneFetchProvider =
    Provider<Future<Map<String, dynamic>?> Function(String id)>((ref) => fetchGearBookingJson);

/// Děkovací stránka výpůjčky výbavy (web `confirmView` / `paidView`):
/// dokud není zaplaceno, ověřuje stav (12× po 2 s), pak potvrzení,
/// doklad totožnosti, další kroky a odkazy na rezervaci a Domů.
class GearDoneScreen extends ConsumerStatefulWidget {
  final String bookingId;
  final Duration pollEvery;
  const GearDoneScreen({super.key, required this.bookingId, this.pollEvery = const Duration(seconds: 2)});

  @override
  ConsumerState<GearDoneScreen> createState() => _GearDoneScreenState();
}

class _GearDoneScreenState extends ConsumerState<GearDoneScreen> {
  GearDoneInfo? _info;
  GearDoneStage _stage = GearDoneStage.wait;
  Timer? _t;
  int _n = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    final fetch = ref.read(gearDoneFetchProvider);
    Map<String, dynamic>? o;
    try {
      o = await fetch(widget.bookingId);
    } catch (_) {
      o = null;
    }
    if (!mounted) return;
    var prices = const <GearPrice>[];
    try {
      prices = await ref.read(gearPricesProvider.future).timeout(const Duration(seconds: 5));
    } catch (_) {}
    if (!mounted) return;
    final info = o == null ? null : GearDoneInfo(o, prices);
    final settled = info != null && (info.paid || info.status == 'cancelled' || info.status == 'completed');
    if (settled || ++_n >= 12) {
      setState(() {
        _info = info;
        _stage = gearDoneStage(info, pending: !settled);
      });
      if (info != null && info.paid) {
        refreshGearBookings(ref, widget.bookingId);
        gearForgetDraft(ref.read(gearOrderUserProvider).$1);
      }
      return;
    }
    _t = Timer(widget.pollEvery, _poll);
  }

  void _close() => context.go(Routes.home);

  @override
  Widget build(BuildContext context) {
    final id = widget.bookingId;
    final actions = GearDoneActions(
      showBooking: () => context.go('/reservations/$id'),
      home: _close,
      uploadDocs: () => openGearIdDocs(context, ref, id),
      pay: _info == null
          ? null
          : () => payGearBooking(context, ref, bookingId: id, amount: _info!.toPay, createdAt: _info!.createdAt),
    );
    final view = MgV2.on(context)
        ? GearDoneViewV2(stage: _stage, info: _info, actions: actions)
        : GearDoneView(stage: _stage, info: _info, actions: actions);
    return BackButtonListener(
      onBackButtonPressed: () async {
        if (!isTopmostRoute(context)) return false;
        _close();
        return true;
      },
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _close();
        },
        child: view,
      ),
    );
  }
}

/// Akce děkovací stránky.
class GearDoneActions {
  final VoidCallback showBooking;
  final VoidCallback home;
  final VoidCallback uploadDocs;
  final VoidCallback? pay;
  const GearDoneActions({required this.showBooking, required this.home, required this.uploadDocs, this.pay});
}
