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
import '../../../core/v2/states/mg_state_banner.dart';
import '../../../core/v2/states/mg_state_screen.dart';
import '../../../core/v2/tokens/mg_colors.dart';
import '../../catalog/moto_model.dart';
import '../booking_models.dart';
import 'booking_consents_v2.dart';
import 'booking_date_v2.dart';
import 'booking_dock_v2.dart';
import 'booking_express_v2.dart' show BookingChipButtonV2;
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
  final _consentKey = GlobalKey();
  final _warnKey = GlobalKey();
  final _timeKey = GlobalKey();
  final _sizesKey = GlobalKey();

  void _scrollTo(GlobalKey key) {
    final c = key.currentContext;
    if (c == null) return;
    MgPinnedBack.reveal(c, duration: MgMotion.of(context, MgMotion.sheet), curve: MgMotion.out);
  }

  /// Date card open (calendar) and in view — "Změnit termín" fixes.
  void _openDates() {
    widget.onOpenCalendar();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollTo(_dateKey);
    });
  }

  /// The error banner's working actions (navigation only).
  List<(String, VoidCallback)> _errActions(AppTranslations tr) => switch (widget.errKind) {
        // J2 / P2-03: the profile fix first (the one way on with no fitting
        // licence), also when the amber profile card is shown — that card
        // then drops its own copy, so the button stays once on the page and
        // the red card no longer points only to "another bike".
        BookingErrKind.licence => [
            (tr.tr('completeProfileBtn'), widget.onCompleteProfile),
            (tr.tr('pdPickOtherMoto'), widget.onBack),
          ],
        BookingErrKind.dates => [(tr.tr('psChangeDates'), _openDates)],
        BookingErrKind.time => [(tr.tr('v2BkFixTime'), () => _scrollTo(_timeKey))],
        null => const [],
      };

  /// First reason the CTA is locked — display only, the lock itself is the
  /// form's `canProceed` (the old form's hints next to its CTA: dates,
  /// availability, error, profile, sizes, consents).
  String? _blocker(AppTranslations tr) {
    final w = widget;
    if (w.canProceed) return null;
    final b = w.booked;
    final d = w.draft;
    if (!w.hasDates) return tr.tr('v2BkBlockDates');
    if (b != null && !b.hasValue && !b.hasError) return tr.tr('v2BkBlockAvail');
    if (b != null && !b.hasValue && b.hasError) return tr.tr('v2BkBlockAvailFail');
    if (w.rangeBusy) return tr.tr('v2BkBlockBusy');
    if (w.err != null) {
      return tr.tr(switch (w.errKind) {
        BookingErrKind.licence => 'coBkBlockLicence',
        BookingErrKind.dates => 'coBkBlockDatesBad',
        BookingErrKind.time => 'coBkBlockTime',
        null => 'v2BkBlockError',
      });
    }
    if (w.profileErr != null) return tr.tr('v2BkBlockProfile');
    if (w.missingSizes.isNotEmpty) return tr.tr('v2BkBlockSizes');
    if (!(d.consentVop && d.consentGdpr && (!w.isKids || d.consentKids))) return tr.tr('v2BkBlockConsent');
    return null;
  }

  /// Where the first blocker ([_blocker], same order) is shown / fixed —
  /// the dock's "Ukázat proč" scrolls there (J1). Display only.
  GlobalKey _blockerTarget() {
    final w = widget;
    final b = w.booked;
    if (!w.hasDates) return _dateKey;
    if (b != null && !b.hasValue && !b.hasError) return _dateKey;
    if (b != null && !b.hasValue && b.hasError) return _warnKey;
    if (w.rangeBusy) return _dateKey;
    if (w.err != null) return w.errKind == BookingErrKind.time ? _timeKey : _warnKey;
    if (w.profileErr != null) return _warnKey;
    // P2-05: missing sizes → the gear block with the size buttons itself
    // (the amber card at the bottom only names them).
    if (w.missingSizes.isNotEmpty) return _sizesKey;
    return _consentKey;
  }

  @override
  Widget build(BuildContext context) {
    final tr = t(context);
    final w = widget;
    final d = w.draft;
    final blocker = _blocker(tr);
    final booked = w.booked;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    var i = 0;
    Widget reveal(Widget child) => MgReveal(index: i++, sessionKey: 'booking-form', child: child);
    // The old form's order, every section open: moto card → date → time →
    // pickup → return → extras → price → promo → note → consents → hints.
    final sections = <Widget>[
      // Old `BookingFormMotoCard`: model, "od {price}", "Pobočka: {name},
      // {city}" (+ the branch type, disclosure rule).
      reveal(BookingRecapV2(moto: w.moto, withCity: true)),
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          BookingFormTimeSection(
            draft: d,
            onTimeChanged: w.onPickupTime,
            onReturnTimeChanged: w.onReturnTime,
            showReturn: !w.hideReturnTime,
            selfService: w.selfServiceAtBranch,
          ),
          // P2-01: the pickup-time error right where "Ukázat proč" lands
          // (the same text as the red card below, which stays).
          if (w.err != null && w.errKind == BookingErrKind.time)
            Padding(
              key: const ValueKey('bk-time-err'),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: MgStateBanner(tone: MgTone.err, icon: MgIcons.clock, title: w.err!),
            ),
        ]),
      ),
      BookingFormPickupSection(draft: d, onUpd: w.onUpd, branchLabel: w.branchLabel, deliveryBlocked: w.deliveryBlocked),
      BookingFormReturnSection(draft: d, onUpd: w.onUpd, branchLabel: w.branchLabel, deliveryBlocked: w.deliveryBlocked),
      KeyedSubtree(
        key: _sizesKey,
        child: BookingFormExtrasSection(
          draft: d,
          onUpd: w.onUpd,
          isKids: w.isKids,
          selfService: w.selfService,
          motoId: w.moto.id,
        ),
      ),
      BookingFormPriceSection(draft: d, bd: w.bd, dayCount: w.dayCount, pricedExtras: w.pricedExtras),
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
          errPrimaryFirst: w.errKind == BookingErrKind.licence,
          profileFixInErr: w.err != null && w.errKind == BookingErrKind.licence,
          profileErr: w.profileErr,
          bookedFailed: booked != null && booked.hasError && !booked.hasValue,
          onCompleteProfile: w.onCompleteProfile,
          onRetryBooked: w.onRetryBooked,
        ),
      ),
    ];
    return MgPage(
      overlapHero: false,
      pinnedBack: w.onBack,
      pinnedTitle: w.moto.model,
      sections: [
        // Hlavička a pod ní obsah vytažený o 24 px nahoru — kreslený PO
        // hlavičce, takže rekapitulace leží na jejím zaobleném okraji.
        BookingHeaderV2(bikeName: w.moto.model, onBack: w.onBack),
        Transform.translate(
          offset: const Offset(0, -24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: sections),
        ),
      ],
      dock: keyboard
          ? null
          : BookingDockV2(
              canProceed: w.canProceed,
              blocker: blocker,
              context2: w.hasDates ? [tr.tr('v2YourPrice'), bkDays(tr, w.dayCount)].join(' · ') : null,
              price: w.hasDates ? bkNb(bkMoney(w.bd.total)) : null,
              onProceed: w.onProceed,
              onTrailing: blocker == null ? null : () => _scrollTo(_blockerTarget()),
              trailingLabel: blocker == null ? null : tr.tr('coBkShowWhy'),
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
