import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/booking/booking_models.dart';
import '../features/booking/booking_provider.dart';
import '../features/booking/booking_ui_helpers.dart';
import '../features/booking/map_launcher.dart';
import 'i18n/i18n_provider.dart';

/// Pickup-method selector section inside the booking form.
class BookingFormPickupSection extends ConsumerWidget {
  const BookingFormPickupSection({
    super.key,
    required this.draft,
    required this.onUpd,
  });

  final BookingDraft draft;

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
            'Mezná 9, Mezná',
            t(context).free,
            draft.pickupMethod == 'store',
            () => onUpd((d) => d.copyWith(pickupMethod: 'store')),
          ),
          const SizedBox(height: 6),
          bookingRadio(
            t(context).tr('deliveryToAddress'),
            t(context).tr('deliveryPriceInfo'),
            t(context).tr('deliveryFrom'),
            draft.pickupMethod == 'delivery',
            () => onUpd((d) => d.copyWith(pickupMethod: 'delivery')),
          ),
          if (draft.pickupMethod == 'delivery') ...[
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
                onMapTap: (ctx) async {
                  final r = await launchMapPicker(ctx);
                  if (r == null) return;
                  onUpd((d) => d.copyWith(
                        pickupCity: () => r.city,
                        pickupAddress: () => r.address,
                      ));
                  ref.read(pickupDelivFeeProvider.notifier).state = r.fee;
                  ref.read(pickupDistKmProvider.notifier).state = r.km;
                },
              ),
              distKm: ref.watch(pickupDistKmProvider),
              delivFee: ref.watch(pickupDelivFeeProvider),
            ),
          ],
        ],
      ),
    );
  }
}
