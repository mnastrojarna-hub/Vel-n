import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog_provider.dart' show bookedDatesProvider;
import '../moto_model.dart';
import 'detail/detail_dates_carry_v2.dart';

/// The bike whose detail should open on its date step — set by the card's
/// "Rezervovat" when there are no usable dates, read ONCE by that bike's
/// detail page (which then runs its own "VYBRAT TERMÍN").
final detailPickDatesRequestProvider = StateProvider<String?>((_) => null);

/// "Rezervovat" on the bike list card (owner 2026-11-27: "Detail = podívat
/// se na motorku; Rezervovat = hned vybrat termín v kalendáři"). It is the
/// detail's own primary button, pressed from the list — the same pieces,
/// nothing copied:
/// * the days the detail would open with ([detailStartDates]: the
///   in-progress booking of this bike, else the catalog dates),
/// * the detail's rule ([detailCanReserve] over [detailRangeBusy] — booked
///   days count only when this bike's calendar is already loaded, exactly
///   like a tap on the detail's button right after it opens),
/// * then [detailReserve] (`startBookingFromSelection`, where every booking
///   guard lives), or — no days / a busy range — the detail at its date
///   step through [openDetail] (the card's own open: sibling ids + push).
void bikeCardReserve(BuildContext context, WidgetRef ref, Motorcycle moto, VoidCallback openDetail) {
  final (s, e) = detailStartDates(context, ref, moto.id);
  final booked = ref.exists(bookedDatesProvider(moto.id))
      ? ref.read(bookedDatesProvider(moto.id))
      : const AsyncValue<List<BookedDateRange>>.loading();
  final busy = detailRangeBusy(ref, booked, moto.id, s, e, watch: false);
  if (detailCanReserve(s, busy)) {
    detailReserve(context, ref, moto, s!, e);
    return;
  }
  ref.read(detailPickDatesRequestProvider.notifier).state = moto.id;
  openDetail();
}
