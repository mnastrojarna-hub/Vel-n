import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/booking/booking_models.dart';
import '../features/booking/booking_provider.dart';
import '../features/booking/booking_ui_helpers.dart';
import '../features/booking/map_launcher.dart';
import 'i18n/i18n_provider.dart';

/// Return-method selector section inside the booking form.
class BookingFormReturnSection extends ConsumerWidget {
  const BookingFormReturnSection({
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
      5,
      t(context).tr('returnMotorcycle'),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bookingRadio(
            t(context).tr('atBranch'),
            'Mezná 9, Mezná',
            t(context).free,
            draft.returnMethod == 'store',
            () => onUpd((d) => d.copyWith(returnMethod: 'store')),
          ),
          const SizedBox(height: 6),
          bookingRadio(
            t(context).tr('returnFromAddress'),
            t(context).tr('deliveryPriceInfo'),
            t(context).tr('deliveryFrom'),
            draft.returnMethod == 'delivery',
            () => onUpd((d) => d.copyWith(returnMethod: 'delivery')),
          ),
          if (draft.returnMethod == 'delivery') ...[
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
                onDistCalc: (km, fee) =>
                    ref.read(returnDelivFeeProvider.notifier).state = fee,
                onMapTap: (ctx) async {
                  final r = await launchMapPicker(ctx);
                  if (r == null) return;
                  onUpd((d) => d.copyWith(
                        returnCity: () => r.city,
                        returnAddress: () => r.address,
                      ));
                  ref.read(returnDelivFeeProvider.notifier).state = r.fee;
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
