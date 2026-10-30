import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/v2/flag/v2_scope.dart';
import '../../../booking/booking_models.dart' show BookingDraft;
import '../../../booking/v2/booking_carry_v2.dart' show draftDatesFor, followDraftDates;
import '../../catalog_provider.dart';
import '../catalog_date_sheet_v2.dart' show catClearDates, catSetDates;

/// Date carry of the bike detail (owner 2026-10-22 „nic nevyplňovat
/// dvakrát“), moved out of `moto_detail_page.dart` (r2, file size): the
/// SAME rules, the page only calls these.

/// Start dates of the detail: v2 — the in-progress booking of THIS bike
/// wins, else the catalog filter (old look: the filter only, as before).
(DateTime?, DateTime?) detailStartDates(BuildContext context, WidgetRef ref, String motoId) {
  final filter = ref.read(catalogFilterProvider);
  final carried = MgV2.peek(context) ? draftDatesFor(ref, motoId) : null;
  return (carried?.$1 ?? filter.startDate, carried?.$2 ?? filter.endDate);
}

/// v2: dates changed in the booking form („Změnit“) for this bike → the
/// range the detail under it should show (null = nothing to follow).
(DateTime, DateTime)? detailFollowDraft(BookingDraft? prev, BookingDraft next, String motoId) =>
    followDraftDates(prev, next, motoId);

/// A range picked in the detail applies to the whole catalog (pager, Motorky
/// list, Home pill) — the same write as picking dates in Motorky.
void detailShareRange(WidgetRef ref, DateTime s, DateTime e) {
  final f = ref.read(catalogFilterProvider);
  if (f.startDate != s || f.endDate != e) catSetDates(ref, s, e);
}

/// A reset in the detail clears the catalog dates too.
void detailShareReset(WidgetRef ref) {
  final f = ref.read(catalogFilterProvider);
  if (f.startDate != null || f.endDate != null) catClearDates(ref);
}
