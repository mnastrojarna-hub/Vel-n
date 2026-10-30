import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/chrome/mg_page.dart';
import '../../../../core/v2/motion/mg_motion.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_shadows.dart';
import '../../../booking/booking_quote.dart';
import '../../../loyalty/loyalty_provider.dart';
import '../../moto_model.dart';
import '../catalog_text.dart';
import 'detail_dock_v2.dart';
import 'detail_hero_v2.dart';
import 'detail_more_v2.dart';
import 'detail_specs_v2.dart';
import 'detail_trip_card_v2.dart';

/// v2 view of one bike detail page (PLAN §2.2.2, technique S): a DUMB view
/// — `_MotoDetailPageState` keeps the photo index / pager controller, the
/// selected dates, the calendar expansion, the booked-dates watch and the
/// REZERVOVAT action (PM-3) and hands values + its own callbacks in here.
/// The only things derived here are the display prices ([quoteFor] = the
/// booking form's own calculation for a fresh draft; the 12:00 variant is
/// information only) and the scroll to the date step ("VYBRAT TERMÍN").
class MotoDetailV2View extends ConsumerStatefulWidget {
  final Motorcycle moto;
  final List<String> images;
  final String branchInfo;
  final int imageIndex;
  final PageController pageCtrl;
  final ValueChanged<int> onImageChanged;
  final VoidCallback? onOpenGallery;

  /// null in pager mode (the pager overlay draws the back control).
  final VoidCallback? onBack;
  final DateTime? selStart;
  final DateTime? selEnd;
  final bool hasDates;
  final int dayCount;
  final double totalPrice;
  final bool calendarExpanded;
  final VoidCallback onToggleCalendar;
  final void Function(DateTime, DateTime) onRangeSelected;
  final void Function(DateTime) onStartSelected;
  final VoidCallback onReset;
  final AsyncValue<List<BookedDateRange>> bookedAsync;

  /// The chosen days hit a booked day (carried dates): warning, CTA off.
  final bool busy;

  /// Opens the date step's calendar (the page's own expand action).
  final VoidCallback onPickDates;

  /// The page's CTA action; null = `canProceed` false (no start date) or
  /// [busy].
  final VoidCallback? onReserve;

  const MotoDetailV2View({
    super.key,
    required this.moto,
    required this.images,
    required this.branchInfo,
    required this.imageIndex,
    required this.pageCtrl,
    required this.onImageChanged,
    required this.onOpenGallery,
    required this.onBack,
    required this.selStart,
    required this.selEnd,
    required this.hasDates,
    required this.dayCount,
    required this.totalPrice,
    required this.calendarExpanded,
    required this.onToggleCalendar,
    required this.onRangeSelected,
    required this.onStartSelected,
    required this.onReset,
    required this.bookedAsync,
    required this.onReserve,
    required this.onPickDates,
    this.busy = false,
  });

  @override
  ConsumerState<MotoDetailV2View> createState() => _MotoDetailV2ViewState();
}

class _MotoDetailV2ViewState extends ConsumerState<MotoDetailV2View> {
  final GlobalKey _tripKey = GlobalKey();

  /// Dock "VYBRAT TERMÍN": open the calendar, then bring "Tvoje jízda" up.
  void _pickDates() {
    widget.onPickDates();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _tripKey.currentContext;
      if (c == null || !mounted) return;
      Scrollable.ensureVisible(c, duration: MgMotion.of(context, MgMotion.sheet), curve: MgMotion.out, alignment: 0.05);
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final moto = w.moto;
    final loyalty = ref.watch(loyaltyStatusProvider).valueOrNull;
    final dated = w.hasDates && moto.prices != null;
    final q = dated ? quoteFor(moto, w.selStart!, w.selEnd!, loyalty: loyalty) : null;
    final q12 = dated && w.dayCount >= 2 ? quoteFor(moto, w.selStart!, w.selEnd!, pickupTime: '12:00', loyalty: loyalty) : null;
    final cheapest = moto.prices?.cheapest ?? 0;
    final from = cheapest > 0
        ? t(context).trArgs('v2CatGridFrom', {'amount': catMoney(catFromPerDay(moto, loyalty?.percent ?? 0))})
        : null;
    final heroH = (MediaQuery.sizeOf(context).height * 0.6).clamp(340.0, 560.0);
    return MgPage(
      background: MgColors.surface,
      pinnedBack: w.onBack,
      header: DetailHeroV2(
        moto: moto,
        images: w.images,
        branchInfo: w.branchInfo,
        imageIndex: w.imageIndex,
        pageCtrl: w.pageCtrl,
        onImageChanged: w.onImageChanged,
        onOpenGallery: w.onOpenGallery,
        onBack: w.onBack,
        height: heroH,
      ),
      sections: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          decoration: const BoxDecoration(
            color: MgColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            boxShadow: MgShadows.sheet,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: Container(
                width: 42,
                height: 5,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: MgColors.grabberLight, borderRadius: BorderRadius.circular(3)),
              ),
            ),
            DetailKeyTilesV2(moto: moto),
            const SizedBox(height: 16),
            DetailTripCardV2(
              key: _tripKey,
              moto: moto,
              selStart: w.selStart,
              selEnd: w.selEnd,
              hasDates: w.hasDates,
              dayCount: w.dayCount,
              listTotal: w.totalPrice,
              quote: q,
              quote12: q12,
              busy: w.busy,
              calendarExpanded: w.calendarExpanded,
              onToggleCalendar: w.onToggleCalendar,
              onRangeSelected: w.onRangeSelected,
              onStartSelected: w.onStartSelected,
              onReset: w.onReset,
              bookedAsync: w.bookedAsync,
            ),
            DetailMoreV2(moto: moto, branchInfo: w.branchInfo),
          ]),
        ),
      ],
      dock: DetailDockV2(
        selStart: w.selStart,
        selEnd: w.selEnd,
        dayCount: w.dayCount,
        price: !w.busy && q != null && q.total > 0 ? catMoney(q.total) : null,
        fromPrice: from,
        onPickDates: _pickDates,
        onReserve: w.onReserve,
        busy: w.busy,
      ),
    );
  }
}
