import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/booking/booking_models.dart';
import '../features/booking/booking_provider.dart';
import '../features/booking/booking_ui_helpers.dart';
import '../features/booking/map_launcher.dart';
import 'booking_form_locked_option.dart';
import 'i18n/i18n_provider.dart';

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
            () => onUpd((d) => d.copyWith(returnMethod: 'store')),
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
              () => onUpd((d) => d.copyWith(returnMethod: 'delivery')),
            ),
          if (!deliveryBlocked && draft.returnMethod == 'delivery') ...[
            const SizedBox(height: 10),
            bookingAddrTile(
              draft.returnCity,
              draft.returnAddress,
              () => showAddrBottomSheet(
                context,
                t(context).tr('returnAddressLabel'),
                draft.returnCity,
                draft.returnAddress,
                (city, addr) => onUpd((d) => d.copyWith(
                      returnCity: () => city,
                      returnAddress: () => addr,
                    )),
                onDistCalc: (km, fee) {
                  ref.read(returnDelivFeeProvider.notifier).state = fee;
                  ref.read(returnDistKmProvider.notifier).state = km;
                },
                onMapTap: (ctx) => launchMapPicker(ctx),
              ),
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
