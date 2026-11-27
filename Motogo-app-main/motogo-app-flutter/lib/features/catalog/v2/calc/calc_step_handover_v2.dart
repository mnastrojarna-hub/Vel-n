import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/booking_address_carry.dart';
import '../../../../core/booking_form_pickup_section.dart';
import '../../../../core/booking_form_return_section.dart';
import '../../../../core/booking_rules.dart' show selfServiceBranchLabel;
import '../../../../core/i18n/i18n_provider.dart';
import '../../../booking/booking_entry.dart' show bookingEntryHandoverProvider;
import '../../../booking/booking_models.dart';
import '../../../booking/booking_validator.dart';
import '../../../booking/v2/booking_carry_v2.dart' show bookingSessionUid;
import '../../moto_model.dart';
import 'calc_parts_v2.dart';
import 'calc_state.dart';

/// What step ④ shows and the total counts for the chosen bike — every rule
/// is the booking form's own (owner 2026-11-27: "se stejnými pravidly jako
/// rezervace").
class CalcHandoverView {
  /// The form's rule [handoverDeliveryBlocked]: self-service branch → no
  /// delivery / collection (the options stay visible, locked).
  final bool blocked;

  /// The handover chosen here; untouched = what the booking form would open
  /// with ([bookingEntryHandoverProvider]: an unfinished booking keeps its
  /// place). Blocked → both sides at the branch, as the form normalizes it.
  final HandoverChoice shown;

  /// The form's own lead-time message (delivery needs 6 h) for the standard
  /// pickup time of a new booking, or null. Information only — the form
  /// enforces it with the chosen time.
  final String? leadWarning;

  const CalcHandoverView({required this.blocked, required this.shown, this.leadWarning});

  /// The form's hint key "delivery chosen, address missing" (fee 0 until an
  /// address is confirmed, as in the form), or null.
  String? get missingAddressKey =>
      shown.pickupNoAddress ? 'efoNoAddrCtx' : (shown.returnNoAddress ? 'efoNoRetAddrCtx' : null);
}

/// [CalcHandoverView] for [moto]; call from `build` (watches the flag and
/// the booking entry).
CalcHandoverView calcHandoverView(WidgetRef ref, CalcState st, Motorcycle moto, String lang) {
  final blocked = handoverDeliveryBlocked(ref, moto);
  final own = st.handover;
  var shown = own != null && own.validFor(moto.branchId, bookingSessionUid())
      ? own.choice
      : ref.watch(bookingEntryHandoverProvider(moto));
  final d = shown.draft;
  if (blocked && (d.pickupMethod == 'delivery' || d.returnMethod == 'delivery')) {
    shown = shown.copyWith(draft: d.copyWith(pickupMethod: 'store', returnMethod: 'store'));
  }
  return CalcHandoverView(
    blocked: blocked,
    shown: shown,
    leadWarning: shown.draft.pickupMethod == 'delivery'
        ? BookingValidator.checkPickupLeadTime(
            startDate: st.start, pickupTime: null, isDelivery: true, branchType: moto.branchType, lang: lang)
        : null,
  );
}

/// Step ④ of the calculator: the PLACE of pickup and return, chosen with
/// the booking form's own sections (`BookingFormPickupSection` /
/// `BookingFormReturnSection` — option rows, locked tile, address sheet with
/// suggestions, GPS and map, route and fee). The choice lives in
/// `calcStateProvider` only; the booking form's draft and fee providers are
/// written by REZERVOVAT (`startBookingFromSelection(handover:)`), never
/// here. The time, gear and sizes stay in the booking form.
class CalcStepHandoverV2 extends ConsumerWidget {
  final Motorcycle? moto;
  final CalcState st;

  /// [calcHandoverView] of this build; null = no bike chosen.
  final CalcHandoverView? view;

  const CalcStepHandoverV2({super.key, required this.moto, required this.st, required this.view});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = t(context);
    final m = moto;
    final v = view;
    final info = CalcHint(tr.tr('cdHandoverInfo'));
    if (m == null || v == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CalcHint(tr.tr('cdHandoverNoMoto')),
        const SizedBox(height: 8),
        info,
      ]);
    }
    final n = ref.read(calcStateProvider.notifier);
    final uid = bookingSessionUid();
    final seed = v.shown;
    // Every write starts from the CURRENT choice: the address sheet reports
    // the price, then the address, and the other side may take both over.
    void change(HandoverChoice Function(HandoverChoice) fn) =>
        n.updateHandover(fn, seed: seed, branchId: m.branchId, owner: uid);
    HandoverChoice cur() {
      final own = ref.read(calcStateProvider).handover;
      return own != null && own.validFor(m.branchId, uid) ? own.choice : seed;
    }

    void upd(BookingDraft Function(BookingDraft) fn) => change((c) => c.copyWith(draft: fn(c.draft)));
    final fees = HandoverFees(
      pickupFee: () => cur().pickupFee,
      pickupKm: () => cur().pickupKm,
      returnFee: () => cur().returnFee,
      returnKm: () => cur().returnKm,
      setPickup: (fee, km) => change((c) => c.copyWith(pickupFee: fee, pickupKm: km)),
      setReturn: (fee, km) => change((c) => c.copyWith(returnFee: fee, returnKm: km)),
    );
    // The form's normalizations for a choice made for another bike: another
    // branch / account → dropped; delivery not offered → back to the branch.
    final own = st.handover;
    if (own != null) {
      final od = own.choice.draft;
      if (!own.validFor(m.branchId, uid) ||
          (v.blocked && (od.pickupMethod == 'delivery' || od.returnMethod == 'delivery'))) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (n.mounted) n.normalizeHandover(branchId: m.branchId, owner: uid, blocked: v.blocked);
        });
      }
    }
    // As the form: the address of the bike's own (self-service) branch.
    final branchLabel = selfServiceBranchLabel(
        branchType: m.branchType, name: m.branchName, address: m.branchAddress, city: m.branchCity);
    final d = seed.draft;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      BookingFormPickupSection(
          draft: d, onUpd: upd, branchLabel: branchLabel, deliveryBlocked: v.blocked, fees: fees, bare: true),
      const SizedBox(height: 16),
      BookingFormReturnSection(
          draft: d, onUpd: upd, branchLabel: branchLabel, deliveryBlocked: v.blocked, fees: fees, bare: true),
      if (v.leadWarning != null) ...[
        const SizedBox(height: 12),
        CalcHint(v.leadWarning!, warn: true),
      ],
      const SizedBox(height: 12),
      info,
    ]);
  }
}
