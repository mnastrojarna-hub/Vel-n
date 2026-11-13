import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n_provider.dart';
import '../../../../core/v2/chrome/mg_page.dart';
import '../../../../core/v2/motion/mg_motion.dart';
import '../../../../core/v2/tokens/mg_colors.dart';
import '../../../../core/v2/tokens/mg_shadows.dart';
import '../../moto_model.dart';
import '../../widgets/validation_banner.dart' show bookingRangeErrors;
import '../catalog_text.dart';
import 'detail_dock_v2.dart';
import 'detail_hero_v2.dart';
import 'detail_more_v2.dart';
import 'detail_trip_card_v2.dart';

/// v2 view of one bike detail page (PLAN §2.2.2, technique S): a DUMB view
/// — `_MotoDetailPageState` keeps the photo index / pager controller, the
/// selected dates, the calendar expansion, the booked-dates watch and the
/// REZERVOVAT action (PM-3) and hands values + its own callbacks in here.
/// The only things derived here are the display prices (list prices, as
/// the old detail) and the scroll to the date step ("VYBRAT TERMÍN").
class MotoDetailV2View extends StatefulWidget {
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
  State<MotoDetailV2View> createState() => _MotoDetailV2ViewState();
}

class _MotoDetailV2ViewState extends State<MotoDetailV2View> {
  final GlobalKey _tripKey = GlobalKey();

  /// The pill claims "free" only when the loaded calendar has no booked day
  /// in the range at all (the busy rule waits for the own reservations).
  static bool _noBookedDay(MotoDetailV2View w) {
    final s = w.selStart, e = w.selEnd ?? w.selStart;
    final booked = w.bookedAsync.valueOrNull;
    if (s == null || e == null || booked == null) return false;
    for (var d = DateTime(s.year, s.month, s.day); !d.isAfter(e); d = DateTime(d.year, d.month, d.day + 1)) {
      if (booked.any((r) => r.containsDate(d))) return false;
    }
    return true;
  }

  /// Dock "VYBRAT TERMÍN": open the calendar, then bring "Tvoje jízda" up.
  void _pickDates() {
    widget.onPickDates();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _tripKey.currentContext;
      if (c == null || !mounted) return;
      MgPinnedBack.reveal(c, duration: MgMotion.of(context, MgMotion.sheet), curve: MgMotion.out);
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final moto = w.moto;
    final cheapest = moto.prices?.cheapest ?? 0;
    // „jen vzhled“: ceníková cena jako v původním detailu (sleva za rank až v rezervaci).
    final from = cheapest > 0 ? t(context).trArgs('v2CatGridFrom', {'amount': catMoney(cheapest)}) : null;
    final heroH = (MediaQuery.sizeOf(context).height * 0.6).clamp(340.0, 560.0);
    return MgPage(
      background: MgColors.surface,
      pinnedBack: w.onBack,
      pinnedTitle: moto.model,
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
        hasDates: w.hasDates,
        rangeFree: w.hasDates && w.bookedAsync.hasValue && !w.busy && _noBookedDay(w),
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
            // The old detail's order: video → branch → description →
            // parameters → prices → calendar (+ total) → manual.
            DetailMoreV2(moto: moto, branchInfo: w.branchInfo),
            const SizedBox(height: 20),
            DetailTripCardV2(
              key: _tripKey,
              moto: moto,
              selStart: w.selStart,
              selEnd: w.selEnd,
              hasDates: w.hasDates,
              dayCount: w.dayCount,
              listTotal: w.totalPrice,
              busy: w.busy,
              calendarExpanded: w.calendarExpanded,
              onToggleCalendar: w.onToggleCalendar,
              onRangeSelected: w.onRangeSelected,
              onStartSelected: w.onStartSelected,
              onReset: w.onReset,
              bookedAsync: w.bookedAsync,
            ),
            DetailManualSectionV2(moto: moto),
          ]),
        ),
      ],
      // G-152/G-153/G-154: the range problem (licence, overlap, length) also
      // in the dock — the banner in the date card is below the fold.
      dock: Consumer(
        builder: (context, ref, _) {
          final errs = w.hasDates ? bookingRangeErrors(context, ref, moto, w.selStart!, w.selEnd!) : const <String>[];
          return DetailDockV2(
            selStart: w.selStart,
            selEnd: w.selEnd,
            dayCount: w.dayCount,
            price: !w.busy && w.hasDates && w.totalPrice > 0 ? catMoney(w.totalPrice) : null,
            fromPrice: from,
            onPickDates: _pickDates,
            onReserve: w.onReserve,
            busy: w.busy,
            warning: errs.isEmpty ? null : errs.first,
          );
        },
      ),
    );
  }
}
