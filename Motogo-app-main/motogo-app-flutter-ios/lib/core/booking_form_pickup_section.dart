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

/// Pickup-method selector section inside the booking form.
class BookingFormPickupSection extends ConsumerWidget {
  const BookingFormPickupSection({
    super.key,
    required this.draft,
    required this.onUpd,
    this.branchLabel,
    this.deliveryBlocked = false,
    this.fees,
    this.bare = false,
  });

  final BookingDraft draft;

  /// Adresa samoobslužné pobočky motorky z DB („Boudky, Velké Němčice“) —
  /// null (obslužná pobočka) = dosavadní adresa hlavní pobočky.
  final String? branchLabel;

  /// Samoobslužná pobočka bez přistavení (feature flag `self_service_delivery`
  /// vypnutý, 2026-09-28): volba na adresu zůstává vidět, ale zabalená a
  /// nejde vybrat — viz [BookingLockedOptionTile].
  final bool deliveryBlocked;

  /// Applies a mutation to the current [BookingDraft].
  final void Function(BookingDraft Function(BookingDraft) fn) onUpd;

  /// Kde se drží vzdálenost a cena — null = providery rezervačního formuláře
  /// (dosavadní chování); kalkulačka dává vlastní stav ([HandoverFees]).
  final HandoverFees? fees;

  /// Jen v2: stejné volby bez rámu karty (uvnitř kroku kalkulačky).
  final bool bare;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Obsluha sdílená starým i v2 vzhledem (těla beze změny, jen vytažená
    // z inline closur).
    void toStore() => onUpd((d) => d.copyWith(pickupMethod: 'store'));
    // Bez vlastní adresy převezme adresu druhé strany předání (2026-10-22).
    void toDelivery() => handoverToDelivery(ref, onUpd, draft, pickup: true, fees: fees);
    void openAddress() => showAddrBottomSheet(
        context,
        t(context).tr(MgV2.on(context) ? 'efoDelivAddrTitle' : 'pickupAddressLabel'),
        draft.pickupCity,
        draft.pickupAddress,
        (city, addr) => handoverSaveAddress(ref, onUpd, draft, pickup: true, city: city, addr: addr, fees: fees),
        quick: handoverQuickOptions(t(context).tr, draft,
            pickup: true, profile: ref.read(profileProvider).valueOrNull),
        onDistCalc: (km, fee) => (fees ?? HandoverFees.form(ref)).setPickup(fee, km),
        onMapTap: (ctx) => launchMapPicker(ctx),
      );
    // Vzdálenost a cena u adresy (čte se jen při zobrazené adrese, jako dřív).
    final f = fees;
    double distKm() => f != null ? f.pickupKm() : ref.watch(pickupDistKmProvider);
    double delivFee() => f != null ? f.pickupFee() : ref.watch(pickupDelivFeeProvider);
    // v2 vzhled (kill-switch app_v2_ui): stejné volby, zámek i adresa.
    if (MgV2.on(context)) {
      return BookingHandoverV2(
        bare: bare,
        title: t(context).tr('v2BkPickupTitle'),
        icon: MgIcons.moto,
        branchSub: branchLabel ?? 'Mezná 9, Pelhřimov',
        storeSelected: draft.pickupMethod == 'store',
        deliverySelected: draft.pickupMethod == 'delivery',
        deliveryTitle: t(context).tr('v2BkDeliveryTo'),
        onStore: toStore,
        onDelivery: toDelivery,
        locked: deliveryBlocked
            ? BookingLockedOptionTile(
                label: t(context).tr('v2BkDeliveryTo'),
                shortReason: t(context).tr('ssNoDeliveryShort'),
                info: t(context).tr('ssNoDeliveryInfo'),
              )
            : null,
        address: !deliveryBlocked && draft.pickupMethod == 'delivery'
            ? BkAddress(
                city: draft.pickupCity,
                address: draft.pickupAddress,
                onTap: openAddress,
                distKm: distKm(),
                delivFee: delivFee(),
              )
            : null,
      );
    }
    return bookingCard(
      4,
      t(context).tr('pickupMotorcycle'),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bookingRadio(
            t(context).tr('atBranch'),
            branchLabel ?? 'Mezná 9, Pelhřimov',
            t(context).free,
            draft.pickupMethod == 'store',
            toStore,
          ),
          const SizedBox(height: 6),
          if (deliveryBlocked)
            BookingLockedOptionTile(
              label: t(context).tr('deliveryToAddress'),
              shortReason: t(context).tr('ssNoDeliveryShort'),
              info: t(context).tr('ssNoDeliveryInfo'),
            )
          else
            bookingRadio(
              t(context).tr('deliveryToAddress'),
              t(context).tr('deliveryPriceInfo'),
              t(context).tr('deliveryFrom'),
              draft.pickupMethod == 'delivery',
              toDelivery,
            ),
          if (!deliveryBlocked && draft.pickupMethod == 'delivery') ...[
            const SizedBox(height: 10),
            bookingAddrTile(
              draft.pickupCity,
              draft.pickupAddress,
              openAddress,
              distKm: distKm(),
              delivFee: delivFee(),
              context: context,
            ),
          ],
        ],
      ),
    );
  }
}
