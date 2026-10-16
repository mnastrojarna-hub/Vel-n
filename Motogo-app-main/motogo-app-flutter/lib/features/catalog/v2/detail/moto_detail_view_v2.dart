import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/v2/chrome/mg_page.dart';
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
/// The only thing derived here is the display price ([quoteFor] = the
/// booking form's own calculation for a fresh draft).
class MotoDetailV2View extends ConsumerWidget {
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

  /// The page's CTA action; null = `canProceed` false (no start date).
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
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loyalty = ref.watch(loyaltyStatusProvider).valueOrNull;
    final q = hasDates && moto.prices != null ? quoteFor(moto, selStart!, selEnd!, loyalty: loyalty) : null;
    final heroH = (MediaQuery.sizeOf(context).height * 0.6).clamp(340.0, 560.0);
    return MgPage(
      background: MgColors.surface,
      pinnedBack: onBack,
      header: DetailHeroV2(
        moto: moto,
        images: images,
        branchInfo: branchInfo,
        imageIndex: imageIndex,
        pageCtrl: pageCtrl,
        onImageChanged: onImageChanged,
        onOpenGallery: onOpenGallery,
        onBack: onBack,
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
              moto: moto,
              selStart: selStart,
              selEnd: selEnd,
              hasDates: hasDates,
              dayCount: dayCount,
              listTotal: totalPrice,
              quote: q,
              calendarExpanded: calendarExpanded,
              onToggleCalendar: onToggleCalendar,
              onRangeSelected: onRangeSelected,
              onStartSelected: onStartSelected,
              onReset: onReset,
              bookedAsync: bookedAsync,
            ),
            DetailMoreV2(moto: moto, branchInfo: branchInfo),
          ]),
        ),
      ],
      dock: DetailDockV2(
        selStart: selStart,
        selEnd: selEnd,
        dayCount: dayCount,
        price: q != null && q.total > 0 ? catMoney(q.total) : null,
        onReserve: onReserve,
      ),
    );
  }
}
