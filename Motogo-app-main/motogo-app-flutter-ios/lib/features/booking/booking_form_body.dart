import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../catalog/moto_model.dart';
import 'booking_models.dart';
import 'booking_provider.dart';
import 'widgets/address_picker.dart';
import 'widgets/booking_consents_cta.dart';
import 'widgets/booking_date_section.dart';
import 'widgets/booking_form_header.dart';
import 'widgets/booking_license_section.dart';
import 'widgets/booking_moto_section.dart';
import 'widgets/booking_section_wrapper.dart';
import 'widgets/booking_time_section.dart';
import 'widgets/extras_selector.dart';
import 'widgets/price_summary.dart';
import 'widgets/promo_code_input.dart';

/// Full booking form body — rendered inside Consumer in router.dart.
/// This is NOT booking_form_screen.dart (which causes green blank screen).
class BookingFormBody extends ConsumerStatefulWidget {
  const BookingFormBody({super.key});
  @override
  ConsumerState<BookingFormBody> createState() => _BookingFormBodyState();
}

class _BookingFormBodyState extends ConsumerState<BookingFormBody> {
  bool _calOpen = false;

  void _upd(BookingDraft Function(BookingDraft) fn) {
    final d = ref.read(bookingDraftProvider);
    ref.read(bookingDraftProvider.notifier).state = fn(d);
  }

  @override
  Widget build(BuildContext context) {
    final moto = ref.watch(bookingMotoProvider)!;
    final draft = ref.watch(bookingDraftProvider);
    final bd = ref.watch(priceBreakdownProvider);
    final err = ref.watch(bookingValidationErrorProvider);
    final hasDates = draft.startDate != null && draft.endDate != null;
    final dc = hasDates ? draft.dayCount : 0;
    final isKids = moto.licenseRequired == 'N';

    return Container(
      color: MotoGoColors.bg,
      child: SafeArea(
        child: Column(children: [
          BookingFormHeader(moto: moto, draft: draft),
          Expanded(
            child: SingleChildScrollView(
              child: Column(children: [
                bookingMotoSection(moto),
                bookingDateSection(
                  draft: draft,
                  hasDates: hasDates,
                  dc: dc,
                  bd: bd,
                  calOpen: _calOpen,
                  onOpenCal: () => setState(() => _calOpen = true),
                  onRangeSelected: (s, e) {
                    _upd((d) => d.copyWith(
                        startDate: () => s, endDate: () => e));
                    setState(() => _calOpen = false);
                  },
                  onReset: () => _upd((d) => d.copyWith(
                      startDate: () => null, endDate: () => null)),
                ),
                bookingTimeSection(
                  draft: draft,
                  onTimeSelected: (t) =>
                      _upd((d) => d.copyWith(pickupTime: () => t)),
                ),
                bookingLicenseSection(context, err),
                _pickupSection(draft),
                _returnSection(draft),
                _extrasSection(draft, moto),
                // Price summary
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: PriceSummaryCard(
                      breakdown: bd, extras: draft.extras),
                ),
                _promoSection(draft),
                bookingConsentsSection(
                  draft: draft,
                  isKids: isKids,
                  onConsentVop: (v) =>
                      _upd((d) => d.copyWith(consentVop: v)),
                  onConsentGdpr: (v) =>
                      _upd((d) => d.copyWith(consentGdpr: v)),
                  onConsentKids: (v) =>
                      _upd((d) => d.copyWith(consentKids: v)),
                ),
                bookingCtaButton(
                  draft: draft,
                  isKids: isKids,
                  validationErr: err,
                  context: context,
                ),
                const SizedBox(height: 100),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // 5 VYZVEDNUTÍ
  // ═══════════════════════════════════════════════

  Widget _pickupSection(BookingDraft draft) {
    return bookingSecWrapper(5, 'VYZVEDNUTÍ MOTORKY', AddressPickerWidget(
      label: 'Vyzvednutí',
      method: draft.pickupMethod,
      onMethodChanged: (m) => _upd((d) => d.copyWith(pickupMethod: m)),
      onAddressChanged: (a) => _upd((d) => d.copyWith(
            pickupAddress: () => a.street,
            pickupCity: () => a.city,
            pickupZip: () => a.zip,
            pickupLat: () => a.lat,
            pickupLng: () => a.lng,
          )),
      onDeliveryFeeChanged: (f) =>
          ref.read(pickupDelivFeeProvider.notifier).state = f,
    ));
  }

  // ═══════════════════════════════════════════════
  // 6 VRÁCENÍ
  // ═══════════════════════════════════════════════

  Widget _returnSection(BookingDraft draft) {
    return bookingSecWrapper(6, 'VRÁCENÍ MOTORKY', AddressPickerWidget(
      label: 'Vrácení',
      method: draft.returnMethod,
      onMethodChanged: (m) => _upd((d) => d.copyWith(returnMethod: m)),
      onAddressChanged: (a) => _upd((d) => d.copyWith(
            returnAddress: () => a.street,
            returnCity: () => a.city,
            returnZip: () => a.zip,
            returnLat: () => a.lat,
            returnLng: () => a.lng,
          )),
      onDeliveryFeeChanged: (f) =>
          ref.read(returnDelivFeeProvider.notifier).state = f,
    ));
  }

  // ═══════════════════════════════════════════════
  // 7 VÝBAVA
  // ═══════════════════════════════════════════════

  Widget _extrasSection(BookingDraft draft, Motorcycle moto) {
    return bookingSecWrapper(7, 'VÝBAVA A DOPLŇKY', ExtrasSelector(
      catalog: defaultExtras,
      selected: draft.extras,
      onChanged: (list) => _upd((d) => d.copyWith(extras: list)),
      isDelivery: draft.pickupMethod == 'delivery' ||
          draft.returnMethod == 'delivery',
      helmetSize: draft.helmetSize,
      jacketSize: draft.jacketSize,
      pantsSize: draft.pantsSize,
      bootsSize: draft.bootsSize,
      glovesSize: draft.glovesSize,
      onHelmetSizeChanged: (s) =>
          _upd((d) => d.copyWith(helmetSize: () => s)),
      onJacketSizeChanged: (s) =>
          _upd((d) => d.copyWith(jacketSize: () => s)),
      onPantsSizeChanged: (s) =>
          _upd((d) => d.copyWith(pantsSize: () => s)),
      onBootsSizeChanged: (s) =>
          _upd((d) => d.copyWith(bootsSize: () => s)),
      onGlovesSizeChanged: (s) =>
          _upd((d) => d.copyWith(glovesSize: () => s)),
      passengerHelmetSize: draft.passengerHelmetSize,
      passengerJacketSize: draft.passengerJacketSize,
      passengerPantsSize: draft.passengerPantsSize,
      onPassengerHelmetSizeChanged: (s) =>
          _upd((d) => d.copyWith(passengerHelmetSize: () => s)),
      onPassengerJacketSizeChanged: (s) =>
          _upd((d) => d.copyWith(passengerJacketSize: () => s)),
      onPassengerPantsSizeChanged: (s) =>
          _upd((d) => d.copyWith(passengerPantsSize: () => s)),
    ));
  }

  // ═══════════════════════════════════════════════
  // PROMO CODE
  // ═══════════════════════════════════════════════

  Widget _promoSection(BookingDraft draft) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
            )
          ],
        ),
        child: PromoCodeInput(
          appliedCodes: draft.discounts,
          onCodeApplied: (d) =>
              _upd((dr) => dr.copyWith(discounts: [...dr.discounts, d])),
          onCodeRemoved: (code) => _upd((dr) => dr.copyWith(
                discounts:
                    dr.discounts.where((x) => x.code != code).toList(),
              )),
        ),
      ),
    );
  }
}
