import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../../core/v2/widgets/mg_segmented.dart';
import '../../../core/widgets/state_views.dart';
import '../reservation_models.dart';
import '../reservation_provider.dart' show DoorCode;
import '../widgets/res_detail_tab_content.dart';
import '../widgets/res_payment_details_tab.dart';
import 'res_detail_hero_v2.dart';
import 'res_status_v2.dart';

/// Reservation detail, v2 look (PLAN §2.4.2, seam S). DUMB view: the old
/// `_DetailState` keeps the 5 s refresh, realtime listener, loading / error
/// views and every action; it passes them here. Owner 2026-11-07 "jen
/// upgrade vzhledu": the SAME two tabs as before (Podrobnosti / Podrobnosti
/// o platbě, as an `MgSegmented`) under the photo hero, and in them the
/// SAME widgets in the SAME order — `ResDetailTabContent` (card with the
/// info rows and places, 12:00 note, money, history, codes, pickup steps,
/// rating, documents, the status's buttons, rides) and
/// `ResPaymentDetailsTab` — each drawing its v2 look through its own seam.
class ResDetailV2View extends ConsumerStatefulWidget {
  final Reservation res;
  final AsyncValue<List<DoorCode>> doorCodesAsync;
  final String? branchFullAddress;
  final VoidCallback? onStaleRetry;
  final VoidCallback onBack;
  final VoidCallback onShowCancelDialog;
  final Future<void> Function(BuildContext, String) onOpenFinalInvoice;
  final Future<void> Function(BuildContext, String) onOpenContract;
  final Future<void> Function(BuildContext, Reservation) onRestoreBooking;

  const ResDetailV2View({
    super.key,
    required this.res,
    required this.doorCodesAsync,
    required this.branchFullAddress,
    required this.onStaleRetry,
    required this.onBack,
    required this.onShowCancelDialog,
    required this.onOpenFinalInvoice,
    required this.onOpenContract,
    required this.onRestoreBooking,
  });

  @override
  ConsumerState<ResDetailV2View> createState() => _ResDetailV2ViewState();
}

class _ResDetailV2ViewState extends ConsumerState<ResDetailV2View> {
  /// The old `_activeTab` ('detail' / 'card'), opening on Podrobnosti.
  String _tab = 'detail';

  Reservation get res => widget.res;

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final onBack = widget.onBack;
    final head = Container(
      decoration: const BoxDecoration(
        color: MgColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.onStaleRetry != null) MgStaleNote(onRetry: widget.onStaleRetry!),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: MgSegmented<String>(
            key: const ValueKey('res-detail-tabs'),
            segments: [
              MgSegment(value: 'detail', label: tr.tr('detailTab')),
              MgSegment(value: 'card', label: tr.tr('paymentDetailsTab')),
            ],
            value: _tab,
            onChanged: (v) => setState(() => _tab = v),
          ),
        ),
      ]),
    );

    // Hero + tabs v JEDNOM sloupci: list (−24 px přes fotku, V22 `.sht`) se
    // kreslí nad hero; obsah záložky pod ním jako sliver (jako dřív).
    return MgPage(
      overlapHero: false,
      pinnedBack: onBack,
      pinnedTitle: res.motoName,
      sections: [
        ResDetailHeroV2(res: res, onBack: onBack),
        Transform.translate(offset: const Offset(0, -24), child: head),
      ],
      slivers: [
        if (_tab == 'detail')
          ResDetailTabContent(
            res: res,
            doorCodesAsync: widget.doorCodesAsync,
            statusColor: MgColors.link,
            statusTitle: resStatusLabel(tr, res.displayStatus),
            branchFullAddress: widget.branchFullAddress,
            onShowCancelDialog: widget.onShowCancelDialog,
            onOpenFinalInvoice: widget.onOpenFinalInvoice,
            onOpenContract: widget.onOpenContract,
            onRestoreBooking: widget.onRestoreBooking,
          )
        else
          // v2: the tab draws its rows as a box (`ResPaymentDetailsV2`).
          SliverToBoxAdapter(
            child: Padding(padding: const EdgeInsets.all(16), child: ResPaymentDetailsTab(res: res)),
          ),
      ],
    );
  }
}
