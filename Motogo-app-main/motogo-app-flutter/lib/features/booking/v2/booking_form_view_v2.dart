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
import '../../../core/v2/icons/mg_icon.dart';
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
import 'booking_express_v2.dart';
import 'booking_header_v2.dart';
import 'booking_note_v2.dart';
import 'booking_recap_v2.dart';
import 'booking_sync_v2.dart' show BookingErrKind;
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

  /// The draft range contains a day the bike's calendar shows booked
  /// (`bookingDraftRangeBusy`) — the form keeps the calendar open and the
  /// CTA locked.
  final bool rangeBusy;

  /// What the validation error is about → where it is fixed (null = none).
  final BookingErrKind? errKind;
  final bool calOpen;
  final VoidCallback onCloseCalendar;
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
    this.rangeBusy = false,
    this.errKind,
    required this.calOpen,
    required this.onCloseCalendar,
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
  final _timeKey = GlobalKey();

  /// Express headers (CB-11, Booking board "Máme to připravené"): the
  /// "Termín a předání" cards (date, time, pickup, return) and the gear /
  /// extras section START OPEN for every customer (owner 2026-11-07
  /// "nic neomezit": the times, the delivery choice, the 12:00 tip and the
  /// extras incl. the free trailer stay visible at first glance, as in the
  /// old look); the customer may fold a section with its header. A section
  /// holding a blocker is always open (and stays open).
  bool _handover = true;
  bool _ready = true;

  static bool _handoverBlocked(BookingFormV2View w) {
    final d = w.draft;
    // A chosen delivery without its address is a required input (D7).
    bool noAddr(String? a, String? c) => (a ?? '').trim().isEmpty && (c ?? '').trim().isEmpty;
    return !w.hasDates ||
        w.rangeBusy ||
        w.calOpen ||
        w.errKind == BookingErrKind.dates ||
        w.errKind == BookingErrKind.time ||
        (d.pickupMethod == 'delivery' && noAddr(d.pickupAddress, d.pickupCity)) ||
        (d.returnMethod == 'delivery' && noAddr(d.returnAddress, d.returnCity));
  }

  static bool _readyBlocked(BookingFormV2View w) => w.missingSizes.isNotEmpty;

  @override
  void didUpdateWidget(covariant BookingFormV2View oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_handoverBlocked(widget)) _handover = true;
    if (_readyBlocked(widget)) _ready = true;
  }

  void _scrollTo(GlobalKey key) {
    final c = key.currentContext;
    if (c == null) return;
    MgPinnedBack.reveal(c, duration: MgMotion.of(context, MgMotion.sheet), curve: MgMotion.out);
  }

  /// Opens the collapsed express section holding [key] (if needed), then
  /// brings [key] into view — every "Doplnit" / fix action goes through it.
  void _reveal(GlobalKey key, {bool handover = false, bool ready = false}) {
    if ((handover && !_handover) || (ready && !_ready)) {
      setState(() {
        if (handover) _handover = true;
        if (ready) _ready = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollTo(key);
      });
    } else {
      _scrollTo(key);
    }
  }

  /// Date card open (calendar) and in view — "Změnit termín" fixes.
  void _openDates() {
    widget.onOpenCalendar();
    if (!_handover) setState(() => _handover = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollTo(_dateKey);
    });
  }

  /// Where the validation error is fixed: dates → the date card (open),
  /// pickup lead time → the time card, licence → the banner's own actions.
  VoidCallback _errFix() => switch (widget.errKind) {
        BookingErrKind.dates => _openDates,
        BookingErrKind.time => () => _reveal(_timeKey, handover: true),
        _ => () => _scrollTo(_warnKey),
      };

  /// The error banner's working actions (navigation only).
  List<(String, VoidCallback)> _errActions(AppTranslations tr) => switch (widget.errKind) {
        BookingErrKind.licence => [
            (tr.tr('pdPickOtherMoto'), widget.onBack),
            (tr.tr('completeProfileBtn'), widget.onCompleteProfile),
          ],
        BookingErrKind.dates => [(tr.tr('psChangeDates'), _openDates)],
        BookingErrKind.time => [(tr.tr('v2BkFixTime'), () => _reveal(_timeKey, handover: true))],
        null => const [],
      };

  /// First reason the CTA is locked (display only — the lock itself is the
  /// form's `canProceed`) and the action that takes the customer to the fix.
  (String, VoidCallback)? _blocker(AppTranslations tr) {
    final w = widget;
    if (w.canProceed) return null;
    final b = w.booked;
    final d = w.draft;
    if (!w.hasDates) return (tr.tr('v2BkBlockDates'), () => _reveal(_dateKey, handover: true));
    if (b != null && !b.hasValue && !b.hasError) return (tr.tr('v2BkBlockAvail'), () => _reveal(_dateKey, handover: true));
    if (b != null && !b.hasValue && b.hasError) return (tr.tr('v2BkBlockAvailFail'), () => _scrollTo(_warnKey));
    if (w.rangeBusy) return (tr.tr('v2BkBlockBusy'), _openDates);
    if (w.err != null) return (tr.tr('v2BkBlockError'), _errFix());
    if (w.profileErr != null) return (tr.tr('v2BkBlockProfile'), () => _scrollTo(_warnKey));
    if (w.missingSizes.isNotEmpty) return (tr.tr('v2BkBlockSizes'), () => _reveal(_gearKey, ready: true));
    if (!(d.consentVop && d.consentGdpr && (!w.isKids || d.consentKids))) {
      return (tr.tr('v2BkBlockConsent'), () => _scrollTo(_consentKey));
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
    final handoverBlocked = _handoverBlocked(w);
    final readyBlocked = _readyBlocked(w);
    final handoverCards = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KeyedSubtree(
        key: _dateKey,
        child: BookingDateCardV2(
          dayPrices: w.moto.prices,
          start: d.startDate,
          end: d.endDate,
          hasDates: w.hasDates,
          dayCount: w.dayCount,
          basePrice: w.bd.basePrice,
          calOpen: w.calOpen,
          busy: w.rangeBusy,
          booked: booked,
          onOpenCalendar: w.onOpenCalendar,
          onKeep: w.onCloseCalendar,
          onRangeSelected: w.onDatesSelected,
          onReset: w.onDatesReset,
          onRetryBooked: w.onRetryBooked,
        ),
      ),
      KeyedSubtree(
        key: _timeKey,
        child: BookingFormTimeSection(
          draft: d,
          onTimeChanged: w.onPickupTime,
          onReturnTimeChanged: w.onReturnTime,
          showReturn: !w.hideReturnTime,
          selfService: w.selfServiceAtBranch,
        ),
      ),
      BookingFormPickupSection(draft: d, onUpd: w.onUpd, branchLabel: w.branchLabel, deliveryBlocked: w.deliveryBlocked),
      BookingFormReturnSection(draft: d, onUpd: w.onUpd, branchLabel: w.branchLabel, deliveryBlocked: w.deliveryBlocked),
    ]);
    final sections = <Widget>[
        // CB-10: the recap is the trip (dates, times, place) — same values;
        // CB-11: its footer row opens "Termín a předání".
        reveal(BookingRecapV2(
          moto: w.moto,
          start: w.hasDates ? d.startDate : null,
          end: w.hasDates ? d.endDate : null,
          dayCount: w.dayCount,
          pickupTime: d.pickupTime,
          returnTime: w.hideReturnTime ? null : d.returnTime,
          half: w.bd.latePickupDiscount > 0,
          pickupDelivery: d.pickupMethod == 'delivery',
          onPickDates: _openDates,
          footer: BookingHandoverRowV2(
            open: _handover,
            ok: !handoverBlocked,
            onToggle: () => setState(() => _handover = handoverBlocked || !_handover),
          ),
        )),
        bkAnimatedSize(context, _handover ? handoverCards : const SizedBox(width: double.infinity)),
        reveal(BookingReadyCardV2(
          draft: d,
          bd: w.bd,
          open: _ready,
          gearOk: !readyBlocked,
          onToggle: () => setState(() => _ready = readyBlocked || !_ready),
        )),
        bkAnimatedSize(
          context,
          _ready
              ? KeyedSubtree(
                  key: _gearKey,
                  child: BookingFormExtrasSection(
                    draft: d,
                    onUpd: w.onUpd,
                    isKids: w.isKids,
                    selfService: w.selfService,
                    motoId: w.moto.id,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        KeyedSubtree(
          key: _priceKey,
          child: BookingFormPriceSection(draft: d, bd: w.bd, dayCount: w.dayCount, pricedExtras: w.pricedExtras),
        ),
        // Promo + note as two pills while nothing is entered (board);
        // an applied code, own vouchers or an open note show their card.
        BookingFormPromoSection(
          draft: d,
          onUpd: w.onUpd,
          express: true,
          expressNote: w.noteOpen || w.noteCtrl.text.trim().isNotEmpty
              ? null
              : BookingChipButtonV2(icon: MgIcons.doc, label: tr.tr('v2UxCbNoteChip'), onTap: w.onToggleNote),
        ),
        if (w.noteOpen || w.noteCtrl.text.trim().isNotEmpty)
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
            errActions: _errActions(tr),
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
      pinnedTitle: w.moto.model,
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
              // CB-16: "· ušetříš 1 585 Kč" = the price card's rank saving.
              context2: w.hasDates
                  ? [
                      tr.tr('v2YourPrice'),
                      bkDays(tr, w.dayCount),
                      if (w.bd.loyaltyDiscount > 0)
                        bkNb(tr.trArgs('v2UxCbDockSaves', {'amount': bkMoney(w.bd.loyaltyDiscount)})),
                    ].join(' · ')
                  : null,
              price: w.hasDates ? bkNb(bkMoney(w.bd.total)) : null,
              onProceed: w.onProceed,
              trailingLabel: blocker != null ? tr.tr('v2BkFix') : (w.hasDates ? tr.tr('v2Breakdown') : null),
              onTrailing: blocker != null
                  ? blocker.$2
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
