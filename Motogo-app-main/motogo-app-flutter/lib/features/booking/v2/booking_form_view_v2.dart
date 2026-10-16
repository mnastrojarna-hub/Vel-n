import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/booking_form_extras_section.dart';
import '../../../core/booking_form_pickup_section.dart';
import '../../../core/booking_form_price_section.dart';
import '../../../core/booking_form_promo_section.dart';
import '../../../core/booking_form_return_section.dart';
import '../../../core/booking_form_time_section.dart';
import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/chrome/mg_page.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/motion/mg_motion.dart';
import '../../../core/v2/states/mg_state_screen.dart';
import '../../../core/v2/states/mg_support_row.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../catalog/moto_model.dart';
import '../booking_models.dart';
import 'booking_consents_v2.dart';
import 'booking_date_v2.dart';
import 'booking_dock_v2.dart';
import 'booking_header_v2.dart';
import 'booking_note_v2.dart';
import 'booking_recap_v2.dart';
import 'booking_v2_parts.dart';
import 'booking_warning_v2.dart';

/// v2 view of the booking form `/booking` (PLAN §2.3.1, technique S): a
/// DUMB view — `_BDWState` keeps the draft writes (`_upd`), the silent
/// normalisations, the date / note state, the missing-sizes list, the
/// validation results and the `canProceed` rule, and hands values + its
/// own closures in here. The sections are the SAME widgets as before
/// (each draws its v2 look itself). Local UI state only: scroll targets.
class BookingFormV2View extends StatefulWidget {
  final Motorcycle moto;
  final BookingDraft draft;
  final PriceBreakdown bd;
  final List<SelectedExtra> pricedExtras;
  final String? err;
  final String? profileErr;
  final bool hasDates;
  final int dayCount;
  final bool isKids;
  final bool selfService;
  final bool selfServiceAtBranch;
  final bool hideReturnTime;
  final bool deliveryBlocked;
  final String? branchLabel;
  final List<String> missingSizes;
  final bool canProceed;
  final AsyncValue<List<BookedDateRange>>? booked;
  final bool calOpen;
  final bool noteOpen;
  final TextEditingController noteCtrl;
  final void Function(BookingDraft Function(BookingDraft)) onUpd;
  final VoidCallback onBack;
  final VoidCallback onOpenCalendar;
  final void Function(DateTime, DateTime) onDatesSelected;
  final VoidCallback onDatesReset;
  final VoidCallback onRetryBooked;
  final void Function(String) onPickupTime;
  final void Function(String) onReturnTime;
  final VoidCallback onToggleNote;
  final ValueChanged<String> onNoteChanged;
  final ValueChanged<bool> onVop;
  final ValueChanged<bool> onGdpr;
  final ValueChanged<bool> onKids;
  final VoidCallback onProceed;
  final VoidCallback onCompleteProfile;

  const BookingFormV2View({
    super.key,
    required this.moto,
    required this.draft,
    required this.bd,
    required this.pricedExtras,
    required this.err,
    required this.profileErr,
    required this.hasDates,
    required this.dayCount,
    required this.isKids,
    required this.selfService,
    required this.selfServiceAtBranch,
    required this.hideReturnTime,
    required this.deliveryBlocked,
    required this.branchLabel,
    required this.missingSizes,
    required this.canProceed,
    required this.booked,
    required this.calOpen,
    required this.noteOpen,
    required this.noteCtrl,
    required this.onUpd,
    required this.onBack,
    required this.onOpenCalendar,
    required this.onDatesSelected,
    required this.onDatesReset,
    required this.onRetryBooked,
    required this.onPickupTime,
    required this.onReturnTime,
    required this.onToggleNote,
    required this.onNoteChanged,
    required this.onVop,
    required this.onGdpr,
    required this.onKids,
    required this.onProceed,
    required this.onCompleteProfile,
  });

  @override
  State<BookingFormV2View> createState() => _BookingFormV2ViewState();
}

class _BookingFormV2ViewState extends State<BookingFormV2View> {
  final _dateKey = GlobalKey();
  final _gearKey = GlobalKey();
  final _priceKey = GlobalKey();
  final _consentKey = GlobalKey();
  final _warnKey = GlobalKey();

  void _scrollTo(GlobalKey key) {
    final c = key.currentContext;
    if (c == null) return;
    Scrollable.ensureVisible(c,
        duration: MgMotion.of(context, MgMotion.sheet), curve: MgMotion.out, alignment: 0.08);
  }

  /// First reason the CTA is locked (display only — the lock itself is the
  /// form's `canProceed`) and where it is fixed.
  (String, GlobalKey)? _blocker(AppTranslations tr) {
    final w = widget;
    if (w.canProceed) return null;
    final b = w.booked;
    final d = w.draft;
    if (!w.hasDates) return (tr.tr('v2BkBlockDates'), _dateKey);
    if (b != null && !b.hasValue && !b.hasError) return (tr.tr('v2BkBlockAvail'), _dateKey);
    if (b != null && !b.hasValue && b.hasError) return (tr.tr('v2BkBlockAvailFail'), _warnKey);
    if (w.err != null) return (tr.tr('v2BkBlockError'), _warnKey);
    if (w.profileErr != null) return (tr.tr('v2BkBlockProfile'), _warnKey);
    if (w.missingSizes.isNotEmpty) return (tr.tr('v2BkBlockSizes'), _gearKey);
    if (!(d.consentVop && d.consentGdpr && (!w.isKids || d.consentKids))) {
      return (tr.tr('v2BkBlockConsent'), _consentKey);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final w = widget;
    final d = w.draft;
    final step = !(w.hasDates && w.err == null) ? 0 : (w.missingSizes.isNotEmpty ? 1 : 2);
    final blocker = _blocker(tr);
    final booked = w.booked;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    var i = 0;
    Widget reveal(Widget child) => MgReveal(index: i++, sessionKey: 'booking-form', child: child);
    final sections = <Widget>[
        reveal(BookingRecapV2(moto: w.moto)),
        reveal(KeyedSubtree(
          key: _dateKey,
          child: BookingDateCardV2(
            start: d.startDate,
            end: d.endDate,
            hasDates: w.hasDates,
            dayCount: w.dayCount,
            basePrice: w.bd.basePrice,
            calOpen: w.calOpen,
            booked: booked,
            onOpenCalendar: w.onOpenCalendar,
            onRangeSelected: w.onDatesSelected,
            onReset: w.onDatesReset,
            onRetryBooked: w.onRetryBooked,
          ),
        )),
        reveal(BookingFormTimeSection(
          draft: d,
          onTimeChanged: w.onPickupTime,
          onReturnTimeChanged: w.onReturnTime,
          showReturn: !w.hideReturnTime,
          selfService: w.selfServiceAtBranch,
        )),
        reveal(BookingFormPickupSection(
            draft: d, onUpd: w.onUpd, branchLabel: w.branchLabel, deliveryBlocked: w.deliveryBlocked)),
        reveal(BookingFormReturnSection(
            draft: d, onUpd: w.onUpd, branchLabel: w.branchLabel, deliveryBlocked: w.deliveryBlocked)),
        reveal(KeyedSubtree(
          key: _gearKey,
          child: BookingFormExtrasSection(
            draft: d,
            onUpd: w.onUpd,
            isKids: w.isKids,
            selfService: w.selfService,
            motoId: w.moto.id,
          ),
        )),
        KeyedSubtree(
          key: _priceKey,
          child: BookingFormPriceSection(draft: d, bd: w.bd, dayCount: w.dayCount, pricedExtras: w.pricedExtras),
        ),
        BookingFormPromoSection(draft: d, onUpd: w.onUpd),
        BookingNoteCardV2(
          controller: w.noteCtrl,
          open: w.noteOpen,
          onToggle: w.onToggleNote,
          onChanged: w.onNoteChanged,
        ),
        KeyedSubtree(
          key: _consentKey,
          child: BookingConsentsV2(
            vop: d.consentVop,
            gdpr: d.consentGdpr,
            kids: d.consentKids,
            isKids: w.isKids,
            onVop: w.onVop,
            onGdpr: w.onGdpr,
            onKids: w.onKids,
          ),
        ),
        KeyedSubtree(
          key: _warnKey,
          child: BookingWarningsV2(
            missingSizes: w.missingSizes,
            err: w.err,
            profileErr: w.profileErr,
            bookedFailed: booked != null && booked.hasError && !booked.hasValue,
            onCompleteProfile: w.onCompleteProfile,
            onRetryBooked: w.onRetryBooked,
          ),
        ),
        const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 0), child: MgSupportRow()),
    ];
    return MgPage(
      overlapHero: false,
      pinnedBack: w.onBack,
      sections: [
        // Hlavička a pod ní obsah vytažený o 24 px nahoru — kreslený PO
        // hlavičce, takže rekapitulace leží na jejím zaobleném okraji.
        BookingHeaderV2(bikeName: w.moto.model, onBack: w.onBack, currentStep: step),
        Transform.translate(
          offset: const Offset(0, -24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: sections),
        ),
      ],
      dock: keyboard
          ? null
          : BookingDockV2(
              canProceed: w.canProceed,
              blocker: blocker?.$1,
              context2: w.hasDates ? '${tr.tr('v2YourPrice')} · ${bkDays(tr, w.dayCount)}' : null,
              price: w.hasDates ? bkNb(bkMoney(w.bd.total)) : null,
              onProceed: w.onProceed,
              trailingLabel: blocker != null ? tr.tr('v2BkFix') : (w.hasDates ? tr.tr('v2Breakdown') : null),
              onTrailing: blocker != null
                  ? () => _scrollTo(blocker.$2)
                  : (w.hasDates ? () => _scrollTo(_priceKey) : null),
            ),
    );
  }
}

/// No bike in the booking (old early return): T1 info with back (same
/// back as before) and "VYBRAT MOTORKU" (same target).
class BookingNoMotoV2 extends StatelessWidget {
  final VoidCallback onPick;
  final VoidCallback onBack;
  const BookingNoMotoV2({super.key, required this.onPick, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    return ColoredBox(
      color: MgColors.canvas,
      child: MgStateScreen(
        tone: MgTone.info,
        title: tr.tr('v2BkNoMotoTitle'),
        why: tr.tr('v2BkNoMotoWhy'),
        primary: MgStateAction(tr.tr('selectMotoBtn'), onPick),
        onClose: onBack,
        closeIsBack: true,
        support: false,
      ),
    );
  }
}
