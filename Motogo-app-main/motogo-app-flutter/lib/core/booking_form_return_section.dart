import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/booking/booking_models.dart';
import '../features/booking/booking_provider.dart';
import '../features/booking/booking_ui_helpers.dart';
import '../features/booking/map_launcher.dart';
import '../features/auth/auth_provider.dart' show profileProvider;
import 'booking_address_carry.dart';
import 'booking_form_locked_option.dart';
import 'i18n/i18n_provider.dart';
import 'v2/flag/v2_scope.dart';
import 'v2/icons/mg_icon.dart';
import '../features/booking/v2/sections/handover_v2.dart';

/// Return-method selector section inside the booking form.
class BookingFormReturnSection extends ConsumerWidget {
  const BookingFormReturnSection({
    super.key,
    required this.draft,
    required this.onUpd,
    this.branchLabel,
    this.deliveryBlocked = false,
  });

  final BookingDraft draft;

  /// Adresa samoobslužné pobočky motorky z DB („Boudky, Velké Němčice“) —
  /// null (obslužná pobočka) = dosavadní adresa hlavní pobočky.
  final String? branchLabel;

  /// Samoobslužná pobočka bez odvozu z adresy (feature flag
  /// `self_service_delivery` vypnutý, 2026-09-28): volba zůstává vidět,
  /// ale zabalená a nejde vybrat — viz [BookingLockedOptionTile].
  final bool deliveryBlocked;

  /// Applies a mutation to the current [BookingDraft].
  final void Function(BookingDraft Function(BookingDraft) fn) onUpd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Obsluha sdílená starým i v2 vzhledem (těla beze změny, jen vytažená
    // z inline closur).
    void toStore() => onUpd((d) => d.copyWith(returnMethod: 'store'));
    // Bez vlastní adresy převezme adresu druhé strany předání (2026-10-22).
    void toDelivery() => handoverToDelivery(ref, onUpd, draft, pickup: false);
    void openAddress() => showAddrBottomSheet(
        context,
        t(context).tr('returnAddressLabel'),
        draft.returnCity,
        draft.returnAddress,
        (city, addr) => handoverSaveAddress(ref, onUpd, draft, pickup: false, city: city, addr: addr),
        quick: handoverQuickOptions(t(context).tr, draft,
            pickup: false, profile: ref.read(profileProvider).valueOrNull),
        onDistCalc: (km, fee) {
          ref.read(returnDelivFeeProvider.notifier).state = fee;
          ref.read(returnDistKmProvider.notifier).state = km;
        },
        onMapTap: (ctx) => launchMapPicker(ctx),
      );
    // v2 vzhled (kill-switch app_v2_ui): stejné volby, zámek i adresa.
    if (MgV2.on(context)) {
      return BookingHandoverV2(
        title: t(context).tr('v2BkReturnTitle'),
        icon: MgIcons.flag,
        branchSub: branchLabel ?? 'Mezná 9, Pelhřimov',
        storeSelected: draft.returnMethod == 'store',
        deliverySelected: draft.returnMethod == 'delivery',
        deliveryTitle: t(context).tr('v2BkReturnFrom'),
        onStore: toStore,
        onDelivery: toDelivery,
        locked: deliveryBlocked
            ? BookingLockedOptionTile(
                label: t(context).tr('v2BkReturnFrom'),
                shortReason: t(context).tr('ssNoDeliveryShort'),
                info: t(context).tr('ssNoDeliveryInfo'),
              )
            : null,
        address: !deliveryBlocked && draft.returnMethod == 'delivery'
            ? BkAddress(
                city: draft.returnCity,
                address: draft.returnAddress,
                onTap: openAddress,
                distKm: ref.watch(returnDistKmProvider),
                delivFee: ref.watch(returnDelivFeeProvider),
                note: handoverSameAddress(draft) ? t(context).tr('bkAddrSamePickup') : null,
              )
            : null,
      );
    }
    return bookingCard(
      5,
      t(context).tr('returnMotorcycle'),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bookingRadio(
            t(context).tr('atBranch'),
            branchLabel ?? 'Mezná 9, Pelhřimov',
            t(context).free,
            draft.returnMethod == 'store',
            toStore,
          ),
          const SizedBox(height: 6),
          if (deliveryBlocked)
            BookingLockedOptionTile(
              label: t(context).tr('returnFromAddress'),
              shortReason: t(context).tr('ssNoDeliveryShort'),
              info: t(context).tr('ssNoDeliveryInfo'),
            )
          else
            bookingRadio(
              t(context).tr('returnFromAddress'),
              t(context).tr('deliveryPriceInfo'),
              t(context).tr('deliveryFrom'),
              draft.returnMethod == 'delivery',
              toDelivery,
            ),
          if (!deliveryBlocked && draft.returnMethod == 'delivery') ...[
            const SizedBox(height: 10),
            bookingAddrTile(
              draft.returnCity,
              draft.returnAddress,
              openAddress,
              distKm: ref.watch(returnDistKmProvider),
              delivFee: ref.watch(returnDelivFeeProvider),
              context: context,
            ),
          ],
        ],
      ),
    );
  }
}
