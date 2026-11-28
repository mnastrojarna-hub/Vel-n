import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/booking/booking_models.dart';
import '../features/booking/booking_provider.dart';
import '../features/catalog/moto_model.dart' show Motorcycle;
import 'booking_rules.dart' show selfServiceDeliveryBlocked;
import 'feature_flags.dart' show selfServiceDeliveryEnabledProvider;

// ═══════════════════════════════════════════════════════════════════
// ADRESA PŘISTAVENÍ ↔ ODVOZU — bez dvojího zadávání (majitel 2026-10-22:
// „neměl by nikdy zákazník nic vyplňovat dvakrát“). Přistavení i odvoz na
// stejnou adresu (domů, hotel) je běžný případ: druhá strana adresu
// převezme i s cenou (stejná adresa i pobočka = stejná vzdálenost i cena)
// a zákazník ji jen případně změní. Sdílí oba stromy appky i oba vzhledy.
// ═══════════════════════════════════════════════════════════════════

/// Aktualizace draftu formuláře (`_upd` rezervačního formuláře).
typedef BookingDraftUpd = void Function(BookingDraft Function(BookingDraft));

String _n(String? s) => (s ?? '').trim().toLowerCase();

bool _filled(String? city) => (city ?? '').trim().isNotEmpty;

/// Adresa přistavení (i když je teď zvolená pobočka) — null = žádná.
bool hasPickupAddress(BookingDraft d) => _filled(d.pickupCity);
bool hasReturnAddress(BookingDraft d) => _filled(d.returnCity);

/// Přistavení i odvoz jsou na adresu a adresa je stejná.
bool handoverSameAddress(BookingDraft d) =>
    d.pickupMethod == 'delivery' &&
    d.returnMethod == 'delivery' &&
    hasPickupAddress(d) &&
    _n(d.pickupCity) == _n(d.returnCity) &&
    _n(d.pickupAddress) == _n(d.returnAddress);

BookingDraft _pickupToReturn(BookingDraft d) => d.copyWith(
      returnCity: () => d.pickupCity,
      returnAddress: () => d.pickupAddress,
      returnZip: () => d.pickupZip,
      returnLat: () => d.pickupLat,
      returnLng: () => d.pickupLng,
    );

BookingDraft _returnToPickup(BookingDraft d) => d.copyWith(
      pickupCity: () => d.returnCity,
      pickupAddress: () => d.returnAddress,
      pickupZip: () => d.returnZip,
      pickupLat: () => d.returnLat,
      pickupLng: () => d.returnLng,
    );

/// Kde sekce předání čtou a kam zapisují vzdálenost a cenu přistavení /
/// odvozu. Rezervační formulář = jeho čtyři providery ([HandoverFees.form],
/// výchozí); kalkulačka „Spočítat cenu“ (2026-11-27) = vlastní stav, aby
/// před REZERVOVAT nikdy nezměnila cenu rozpracované rezervace.
class HandoverFees {
  final double Function() pickupFee;
  final double Function() pickupKm;
  final double Function() returnFee;
  final double Function() returnKm;
  final void Function(double fee, double km) setPickup;
  final void Function(double fee, double km) setReturn;

  const HandoverFees({
    required this.pickupFee,
    required this.pickupKm,
    required this.returnFee,
    required this.returnKm,
    required this.setPickup,
    required this.setReturn,
  });

  factory HandoverFees.form(WidgetRef ref) => HandoverFees(
        pickupFee: () => ref.read(pickupDelivFeeProvider),
        pickupKm: () => ref.read(pickupDistKmProvider),
        returnFee: () => ref.read(returnDelivFeeProvider),
        returnKm: () => ref.read(returnDistKmProvider),
        setPickup: (fee, km) {
          ref.read(pickupDelivFeeProvider.notifier).state = fee;
          ref.read(pickupDistKmProvider.notifier).state = km;
        },
        setReturn: (fee, km) {
          ref.read(returnDelivFeeProvider.notifier).state = fee;
          ref.read(returnDistKmProvider.notifier).state = km;
        },
      );
}

/// Místo předání zvolené MIMO rezervační formulář (kalkulačka): způsob a
/// adresa obou stran — z [draft] platí jen pole `pickup*` / `return*`, tvar,
/// se kterým pracují sekce předání — a vzdálenost s cenou tak, jak je
/// formulář drží ve svých providerech. Do formuláře ho předává
/// `startBookingFromSelection(handover:)`.
class HandoverChoice {
  final BookingDraft draft;
  final double pickupFee;
  final double pickupKm;
  final double returnFee;
  final double returnKm;

  HandoverChoice({BookingDraft? draft, this.pickupFee = 0, this.pickupKm = 0, this.returnFee = 0, this.returnKm = 0})
      : draft = draft ?? BookingDraft();

  /// Místo předání z [d] (jen pole `pickup*` / `return*`) s danými cenami.
  factory HandoverChoice.of(BookingDraft d,
          {double pickupFee = 0, double pickupKm = 0, double returnFee = 0, double returnKm = 0}) =>
      HandoverChoice(
        draft: HandoverChoice(draft: d).applyTo(BookingDraft()),
        pickupFee: pickupFee,
        pickupKm: pickupKm,
        returnFee: returnFee,
        returnKm: returnKm,
      );

  /// Cena počítaná do celku — jako `priceBreakdownProvider`: jen u strany
  /// „na adresu“.
  double get pickupDue => draft.pickupMethod == 'delivery' ? pickupFee : 0;
  double get returnDue => draft.returnMethod == 'delivery' ? returnFee : 0;

  /// „Na adresu“ bez zadané adresy (cena se přičte až s adresou).
  bool get pickupNoAddress => draft.pickupMethod == 'delivery' && !hasPickupAddress(draft);
  bool get returnNoAddress => draft.returnMethod == 'delivery' && !hasReturnAddress(draft);

  HandoverChoice copyWith({BookingDraft? draft, double? pickupFee, double? pickupKm, double? returnFee, double? returnKm}) =>
      HandoverChoice(
        draft: draft ?? this.draft,
        pickupFee: pickupFee ?? this.pickupFee,
        pickupKm: pickupKm ?? this.pickupKm,
        returnFee: returnFee ?? this.returnFee,
        returnKm: returnKm ?? this.returnKm,
      );

  /// [d] s tímto místem předání; ostatní pole beze změny.
  BookingDraft applyTo(BookingDraft d) => d.copyWith(
        pickupMethod: draft.pickupMethod,
        returnMethod: draft.returnMethod,
        pickupAddress: () => draft.pickupAddress,
        pickupCity: () => draft.pickupCity,
        pickupZip: () => draft.pickupZip,
        pickupLat: () => draft.pickupLat,
        pickupLng: () => draft.pickupLng,
        returnAddress: () => draft.returnAddress,
        returnCity: () => draft.returnCity,
        returnZip: () => draft.returnZip,
        returnLat: () => draft.returnLat,
        returnLng: () => draft.returnLng,
      );

  List<Object?> get _key => [
        draft.pickupMethod, draft.pickupAddress, draft.pickupCity, draft.pickupZip, draft.pickupLat, draft.pickupLng,
        draft.returnMethod, draft.returnAddress, draft.returnCity, draft.returnZip, draft.returnLat, draft.returnLng,
        pickupFee, pickupKm, returnFee, returnKm,
      ];

  @override
  bool operator ==(Object other) => other is HandoverChoice && listEquals(_key, other._key);

  @override
  int get hashCode => Object.hashAll(_key);
}

/// Přistavení na adresu ani odvoz z adresy se u [moto] nenabízí
/// (samoobslužná pobočka, flag `self_service_delivery` vypnutý) — JEDNO
/// pravidlo pro rezervační formulář i kalkulačku. Volat z `build` (sleduje flag).
bool handoverDeliveryBlocked(WidgetRef ref, Motorcycle moto) => selfServiceDeliveryBlocked(
    branchType: moto.branchType,
    flagEnabled: ref.watch(selfServiceDeliveryEnabledProvider).valueOrNull ?? false);

void _copyFee(HandoverFees f, {required bool toReturn}) {
  if (toReturn) {
    f.setReturn(f.pickupFee(), f.pickupKm());
  } else {
    f.setPickup(f.returnFee(), f.returnKm());
  }
}

/// Volba „na adresu“ u přistavení ([pickup]) nebo odvozu: bez vlastní
/// adresy převezme adresu druhé strany, je-li ta na adrese. [fees] null =
/// providery formuláře.
void handoverToDelivery(WidgetRef ref, BookingDraftUpd onUpd, BookingDraft draft,
    {required bool pickup, HandoverFees? fees}) {
  final copy = pickup
      ? !hasPickupAddress(draft) && draft.returnMethod == 'delivery' && hasReturnAddress(draft)
      : !hasReturnAddress(draft) && draft.pickupMethod == 'delivery' && hasPickupAddress(draft);
  if (copy) _copyFee(fees ?? HandoverFees.form(ref), toReturn: !pickup);
  onUpd((d) {
    final m = pickup ? d.copyWith(pickupMethod: 'delivery') : d.copyWith(returnMethod: 'delivery');
    if (!copy) return m;
    return pickup ? _returnToPickup(m) : _pickupToReturn(m);
  });
}

/// Uložení adresy přistavení ([pickup]) nebo odvozu. Druhá strana na adrese
/// převezme novou adresu (i cenu, kterou už spočítal list adresy přes
/// `onDistCalc`) JEN dokud nemá vlastní adresu. Jakmile ji má (i převzatou),
/// každá strana zapisuje jen svou adresu — přistavení a odvoz na dvě různé
/// adresy musí jít zadat jako ve 4.1.3.
void handoverSaveAddress(WidgetRef ref, BookingDraftUpd onUpd, BookingDraft draft,
    {required bool pickup, required String city, required String addr, HandoverFees? fees}) {
  final otherDelivery = (pickup ? draft.returnMethod : draft.pickupMethod) == 'delivery';
  final otherCity = pickup ? draft.returnCity : draft.pickupCity;
  final follow = otherDelivery && !_filled(otherCity);
  if (follow) _copyFee(fees ?? HandoverFees.form(ref), toReturn: pickup);
  onUpd((d) {
    final m = pickup
        ? d.copyWith(pickupCity: () => city, pickupAddress: () => addr)
        : d.copyWith(returnCity: () => city, returnAddress: () => addr);
    if (!follow) return m;
    return pickup
        ? m.copyWith(returnCity: () => city, returnAddress: () => addr)
        : m.copyWith(pickupCity: () => city, pickupAddress: () => addr);
  });
}

/// Jedna rychlá volba v listu adresy (ulice, PSČ, obec).
class AddrQuick {
  final String label;
  final String street;
  final String city;
  final String zip;
  const AddrQuick({required this.label, required this.street, required this.city, this.zip = ''});

  String get line => [street, [zip, city].where((s) => s.isNotEmpty).join(' ')].where((s) => s.isNotEmpty).join(', ');

  /// Stejný tvar jako položka našeptávače → list ji zpracuje stejnou cestou
  /// (geokódování nejblíž pobočce, vzdálenost, cena, `onDistCalc`).
  Map<String, dynamic> get asSuggestion => {
        'name': street.isNotEmpty ? street : city,
        'label': line,
        'location': '',
        'position': null,
        'zip': zip,
        'regionalStructure': [
          {'type': 'regional.municipality', 'name': city},
        ],
        '_street': street,
        '_city': city,
      };
}

/// Rychlé volby pro list adresy: adresa druhé strany předání (je-li na
/// adrese) a adresa z profilu — bez duplicit a bez adresy, která už je
/// zadaná. [tr] = překlad klíče.
List<AddrQuick> handoverQuickOptions(
  String Function(String) tr,
  BookingDraft draft, {
  required bool pickup,
  Map<String, dynamic>? profile,
}) {
  final out = <AddrQuick>[];
  bool known(String street, String city) =>
      (_n(city) == _n(pickup ? draft.pickupCity : draft.returnCity) &&
          _n(street) == _n(pickup ? draft.pickupAddress : draft.returnAddress)) ||
      out.any((q) => _n(q.city) == _n(city) && _n(q.street) == _n(street));
  final oc = pickup ? draft.returnCity : draft.pickupCity;
  final oa = pickup ? draft.returnAddress : draft.pickupAddress;
  final oz = pickup ? draft.returnZip : draft.pickupZip;
  final otherOn = (pickup ? draft.returnMethod : draft.pickupMethod) == 'delivery';
  if (otherOn && _filled(oc) && !known(oa ?? '', oc!)) {
    out.add(AddrQuick(
        label: tr(pickup ? 'bkAddrSameReturn' : 'bkAddrSamePickup'),
        street: (oa ?? '').trim(),
        city: oc.trim(),
        zip: (oz ?? '').trim()));
  }
  String pv(String k) => (profile?[k] ?? '').toString().trim();
  final pc = pv('city'), ps = pv('street');
  if (pc.isNotEmpty && !known(ps, pc)) {
    out.add(AddrQuick(label: tr('bkAddrMine'), street: ps, city: pc, zip: pv('zip')));
  }
  return out;
}
