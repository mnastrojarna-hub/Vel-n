import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/booking/booking_models.dart';
import '../features/booking/booking_provider.dart';

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

void _copyFee(WidgetRef ref, {required bool toReturn}) {
  if (toReturn) {
    ref.read(returnDelivFeeProvider.notifier).state = ref.read(pickupDelivFeeProvider);
    ref.read(returnDistKmProvider.notifier).state = ref.read(pickupDistKmProvider);
  } else {
    ref.read(pickupDelivFeeProvider.notifier).state = ref.read(returnDelivFeeProvider);
    ref.read(pickupDistKmProvider.notifier).state = ref.read(returnDistKmProvider);
  }
}

/// Volba „na adresu“ u přistavení ([pickup]) nebo odvozu: bez vlastní
/// adresy převezme adresu druhé strany, je-li ta na adrese.
void handoverToDelivery(WidgetRef ref, BookingDraftUpd onUpd, BookingDraft draft, {required bool pickup}) {
  final copy = pickup
      ? !hasPickupAddress(draft) && draft.returnMethod == 'delivery' && hasReturnAddress(draft)
      : !hasReturnAddress(draft) && draft.pickupMethod == 'delivery' && hasPickupAddress(draft);
  if (copy) _copyFee(ref, toReturn: !pickup);
  onUpd((d) {
    final m = pickup ? d.copyWith(pickupMethod: 'delivery') : d.copyWith(returnMethod: 'delivery');
    if (!copy) return m;
    return pickup ? _returnToPickup(m) : _pickupToReturn(m);
  });
}

/// Uložení adresy přistavení ([pickup]) nebo odvozu. Druhá strana na adrese,
/// která adresu nemá nebo měla stejnou jako dosud tahle, převezme novou
/// (cenu už spočítal list adresy přes `onDistCalc`).
void handoverSaveAddress(WidgetRef ref, BookingDraftUpd onUpd, BookingDraft draft,
    {required bool pickup, required String city, required String addr}) {
  final otherDelivery = (pickup ? draft.returnMethod : draft.pickupMethod) == 'delivery';
  final otherCity = pickup ? draft.returnCity : draft.pickupCity;
  final otherAddr = pickup ? draft.returnAddress : draft.pickupAddress;
  final myCity = pickup ? draft.pickupCity : draft.returnCity;
  final myAddr = pickup ? draft.pickupAddress : draft.returnAddress;
  final linked = !_filled(otherCity) || (_n(otherCity) == _n(myCity) && _n(otherAddr) == _n(myAddr));
  final follow = otherDelivery && linked;
  if (follow) _copyFee(ref, toReturn: pickup);
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
