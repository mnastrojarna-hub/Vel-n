import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalog/catalog_provider.dart' show catalogFilterProvider;
import '../../catalog/moto_model.dart' show BookedDateRange;
import '../../catalog/v2/calc/calc_state.dart' show calcStateProvider;
import '../../catalog/v2/catalog_date_sheet_v2.dart' show catSetDates;
import '../../reservations/reservation_models.dart' show Reservation;
import '../../reservations/reservation_provider.dart' show reservationsProvider;
import '../booking_models.dart' show BookingDraft;
import '../booking_provider.dart';
import 'booking_carry_v2.dart' show bookingEntryFilterProvider;

// ═══════════════════════════════════════════════════════════════════
// v2 rezervační formulář ↔ zbytek appky (jen Android v2, CLAUDE.md
// pravidlo 6). Nic z toho nemění rezervaci, cenu ani odeslání.
// ═══════════════════════════════════════════════════════════════════

/// Termín změněný ve formuláři („Změnit“) platí i tam, kam se zákazník
/// vrátí: seznam Motorek a Domů (filtr katalogu — stejný zápis jako výběr
/// termínu v Motorkách, Domů ho převezme), kalkulačka se stejnou motorkou.
/// Další REZERVOVAT odkudkoli tak nese tenhle termín (majitel 2026-10-22:
/// „nikdy nic nevyplňovat dvakrát“). Vstupní filtr = nový termín: detail
/// motorky dál bere termín draftu a Domů po zaplacení pozná termín hotové
/// rezervace.
void bookingFormShareDates(WidgetRef ref, String? motoId, DateTime s, DateTime e) {
  final f = ref.read(catalogFilterProvider);
  if (f.startDate != s || f.endDate != e) catSetDates(ref, s, e);
  ref.read(bookingEntryFilterProvider.notifier).state = (s, e);
  final calc = ref.read(calcStateProvider);
  if (motoId != null && calc.motoId == motoId && (calc.start != s || calc.end != e)) {
    ref.read(calcStateProvider.notifier).setRange(s, e);
  }
}

/// Termín draftu zasahuje do dne, který kalendář motorky ukazuje obsazený
/// (cizí rezervace, servis, zavřená pobočka) — DB by rezervaci odmítla až
/// při platbě. Vlastní rozdělaný koncept téže motorky (pending + nezaplaceno)
/// se nepočítá: platba ho nahradí (`_ownOverlappingDraft`, stejná výjimka
/// jako `BookingValidator.checkOverlap`). Neznámá obsazenost / rezervace =
/// false (rozhodne jako dřív platba).
bool bookingRangeBusy({
  required List<BookedDateRange>? booked,
  required List<Reservation>? own,
  required String? motoId,
  required DateTime? start,
  required DateTime? end,
}) {
  if (booked == null || own == null || motoId == null || start == null || end == null) return false;
  DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
  bool mine(BookedDateRange r) => own.any((x) =>
      x.motoId == motoId &&
      x.status == 'pending' &&
      x.paymentStatus == 'unpaid' &&
      day(x.startDate) == day(r.start) &&
      day(x.endDate) == day(r.end));
  final others = booked.where((r) => !mine(r)).toList();
  if (others.isEmpty) return false;
  for (var d = day(start); !d.isAfter(day(end)); d = DateTime(d.year, d.month, d.day + 1)) {
    if (others.any((r) => r.containsDate(d))) return true;
  }
  return false;
}

/// [bookingRangeBusy] pro draft formuláře ([booked] = jeho watch obsazenosti).
bool bookingDraftRangeBusy(WidgetRef ref, BookingDraft d, AsyncValue<List<BookedDateRange>>? booked) =>
    bookingRangeBusy(
      booked: booked?.valueOrNull,
      own: ref.watch(reservationsProvider).valueOrNull,
      motoId: d.motoId,
      start: d.startDate,
      end: d.endDate,
    );

/// Co blokuje rezervaci ve validační hlášce formuláře → kde se to opraví.
enum BookingErrKind { licence, dates, time }

/// Druh chyby `bookingValidationErrorProvider` (stejné pořadí jako on).
BookingErrKind? bookingErrKind(WidgetRef ref) {
  if (ref.watch(licenseValidationProvider) != null) return BookingErrKind.licence;
  if (ref.watch(overlapValidationProvider) != null || ref.watch(rentalLengthValidationProvider) != null) {
    return BookingErrKind.dates;
  }
  if (ref.watch(pickupLeadTimeValidationProvider) != null) return BookingErrKind.time;
  return null;
}
