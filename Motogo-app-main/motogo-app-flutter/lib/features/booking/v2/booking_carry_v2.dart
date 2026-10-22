import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalog/catalog_provider.dart' show catalogFilterProvider;
import '../../catalog/moto_model.dart';
import '../booking_models.dart';
import '../booking_provider.dart' show bookingDraftProvider;

/// Rozpracovaná rezervace se při dalším vstupu do formuláře NEZAHAZUJE
/// (majitel 2026-10-22: „neměl by nikdy zákazník nic vyplňovat dvakrát“).
/// Jen v2 vzhled (Android, CLAUDE.md pravidlo 6) — starý vzhled zakládá
/// dál čerstvý draft beze změny.
///
/// [fresh] = draft, který by založil starý vstup (motorka, termín, velikosti
/// a „vlastní výbava“ z profilu). Vrací, co má formulář dostat:
/// * žádný rozpracovaný draft / už odeslaný ([submitted]) → [fresh];
/// * STEJNÁ motorka → celý rozpracovaný draft, jen nový termín (při změně
///   termínu se pouští vozík — kus byl přidělený na starý termín);
/// * JINÁ motorka → to, co na motorce nezávisí: čas vyzvednutí a návratu,
///   poznámka, slevové kódy, „vlastní výbava“, velikosti řidiče, souhlasy
///   VOP/GDPR. Místo předání (přistavení/odvoz i adresa) jen u stejné
///   pobočky, doplňky jen u stejné pobočky a stejného typu (dětská /
///   dospělá) — jinak se nabízí jiné řady velikostí. Vozík a souhlas
///   zákonného zástupce se vždy pouští. Zbytek srovnají normalizace
///   formuláře (dětská motorka, samoobsluha, velikosti mimo nabídku).
BookingDraft carryBookingDraft({
  required BookingDraft prev,
  required Motorcycle? prevMoto,
  required Motorcycle moto,
  required BookingDraft fresh,
  bool submitted = false,
}) {
  if (submitted || prev.motoId == null) return fresh;
  if (prev.motoId == moto.id) {
    final sameDates = prev.startDate == fresh.startDate && prev.endDate == fresh.endDate;
    return prev.copyWith(
      motoName: () => fresh.motoName,
      motoImage: () => fresh.motoImage,
      startDate: () => fresh.startDate,
      endDate: () => fresh.endDate,
      extras: sameDates ? null : _noTrailer(prev.extras),
      trailerMotoId: sameDates ? null : () => null,
    );
  }
  final pm = prevMoto != null && prevMoto.id == prev.motoId ? prevMoto : null;
  final sameBranch = pm != null && pm.branchId == moto.branchId;
  final sameSizing = sameBranch && (pm.licenseRequired == 'N') == (moto.licenseRequired == 'N');
  String? rider(String? draft, String? profile) => prev.ownGear ? null : (draft ?? profile);
  return fresh.copyWith(
    pickupTime: () => prev.pickupTime,
    returnTime: () => prev.returnTime,
    notes: () => prev.notes,
    discounts: List.of(prev.discounts),
    ownGear: prev.ownGear,
    helmetSize: () => rider(prev.helmetSize, fresh.helmetSize),
    glovesSize: () => rider(prev.glovesSize, fresh.glovesSize),
    jacketSize: () => rider(prev.jacketSize, fresh.jacketSize),
    pantsSize: () => rider(prev.pantsSize, fresh.pantsSize),
    consentVop: prev.consentVop,
    consentGdpr: prev.consentGdpr,
    pickupMethod: sameBranch ? prev.pickupMethod : 'store',
    returnMethod: sameBranch ? prev.returnMethod : 'store',
    pickupAddress: sameBranch ? () => prev.pickupAddress : null,
    pickupCity: sameBranch ? () => prev.pickupCity : null,
    pickupZip: sameBranch ? () => prev.pickupZip : null,
    pickupLat: sameBranch ? () => prev.pickupLat : null,
    pickupLng: sameBranch ? () => prev.pickupLng : null,
    returnAddress: sameBranch ? () => prev.returnAddress : null,
    returnCity: sameBranch ? () => prev.returnCity : null,
    returnZip: sameBranch ? () => prev.returnZip : null,
    returnLat: sameBranch ? () => prev.returnLat : null,
    returnLng: sameBranch ? () => prev.returnLng : null,
    extras: sameSizing ? _noTrailer(prev.extras) : null,
    bootsSize: sameSizing ? () => prev.bootsSize : null,
    passengerHelmetSize: sameSizing ? () => prev.passengerHelmetSize : null,
    passengerJacketSize: sameSizing ? () => prev.passengerJacketSize : null,
    passengerPantsSize: sameSizing ? () => prev.passengerPantsSize : null,
  );
}

/// true = jiná motorka z jiné pobočky: místo předání se vrátilo na pobočku,
/// ceny přistavení/odvozu z minulé adresy se musí vynulovat.
bool carryDropsDelivery(BookingDraft prev, Motorcycle? prevMoto, Motorcycle moto) =>
    prev.motoId != null &&
    prev.motoId != moto.id &&
    !(prevMoto != null && prevMoto.id == prev.motoId && prevMoto.branchId == moto.branchId);

List<SelectedExtra> _noTrailer(List<SelectedExtra> extras) =>
    extras.where((e) => e.id != 'extra-vozik').toList();

/// `lastConfirmedBookingProvider` v okamžiku, kdy vstup založil současný
/// draft. Jiná hodnota = mezitím se potvrdila (zaplatila) rezervace → draft
/// patří k ní a nový vstup začíná čerstvě (jinak by se přenesly už
/// uplatněné kódy, souhlasy a poznámka hotové rezervace).
final bookingDraftSeedMarkProvider = StateProvider<String?>((_) => null);

/// Data katalogového filtru při posledním vstupu do formuláře. Detail
/// motorky převezme termín z draftu (změněný ve formuláři „Změnit“) jen
/// dokud zákazník filtr mezitím nezměnil — novější volba vyhrává.
final bookingEntryFilterProvider = StateProvider<(DateTime?, DateTime?)?>((_) => null);

/// Termín rozpracované rezervace motorky [motoId] pro její detail (v2) —
/// i když ho zákazník změnil ve formuláři; null = nic rozpracovaného nebo
/// filtr katalogu se od vstupu do formuláře změnil (novější volba vyhrává).
(DateTime, DateTime)? draftDatesFor(WidgetRef ref, String motoId) {
  final d = ref.read(bookingDraftProvider);
  final s = d.startDate, e = d.endDate;
  if (d.motoId != motoId || s == null || e == null) return null;
  final f = ref.read(catalogFilterProvider);
  final atEntry = ref.read(bookingEntryFilterProvider);
  if (atEntry == null || atEntry.$1 != f.startDate || atEntry.$2 != f.endDate) return null;
  return (s, e);
}

/// Nový termín draftu motorky [motoId] (změna ve formuláři), jinak null.
(DateTime, DateTime)? followDraftDates(BookingDraft? prev, BookingDraft next, String motoId) {
  final s = next.startDate, e = next.endDate;
  if (next.motoId != motoId || s == null || e == null) return null;
  if (prev?.startDate == s && prev?.endDate == e) return null;
  return (s, e);
}
