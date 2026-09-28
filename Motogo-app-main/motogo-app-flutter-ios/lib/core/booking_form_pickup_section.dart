import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/booking/booking_models.dart';
import '../features/booking/booking_provider.dart';
import '../features/booking/booking_ui_helpers.dart';
import '../features/booking/map_launcher.dart';
import 'booking_form_locked_option.dart';
import 'i18n/i18n_provider.dart';

/// Pickup-method selector section inside the booking form.
class BookingFormPickupSection extends ConsumerWidget {
  const BookingFormPickupSection({
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

  /// Samoobslužná pobočka bez přistavení (feature flag `self_service_delivery`
  /// vypnutý, 2026-09-28): volba na adresu zůstává vidět, ale zabalená a
  /// nejde vybrat — viz [BookingLockedOptionTile].
  final bool deliveryBlocked;

  /// Applies a mutation to the current [BookingDraft].
  final void Function(BookingDraft Function(BookingDraft) fn) onUpd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            () => onUpd((d) => d.copyWith(pickupMethod: 'store')),
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
              () => onUpd((d) => d.copyWith(pickupMethod: 'delivery')),
            ),
          if (!deliveryBlocked && draft.pickupMethod == 'delivery') ...[
            const SizedBox(height: 10),
            bookingAddrTile(
              draft.pickupCity,
              draft.pickupAddress,
              () => showAddrBottomSheet(
                context,
                t(context).tr('pickupAddressLabel'),
                draft.pickupCity,
                draft.pickupAddress,
                (city, addr) => onUpd((d) => d.copyWith(
                      pickupCity: () => city,
                      pickupAddress: () => addr,
                    )),
                onDistCalc: (km, fee) {
                  ref.read(pickupDelivFeeProvider.notifier).state = fee;
                  ref.read(pickupDistKmProvider.notifier).state = km;
                },
                onMapTap: (ctx) => launchMapPicker(ctx),
              ),
              distKm: ref.watch(pickupDistKmProvider),
              delivFee: ref.watch(pickupDelivFeeProvider),
              context: context,
            ),
          ],
        ],
      ),
    );
  }
}
