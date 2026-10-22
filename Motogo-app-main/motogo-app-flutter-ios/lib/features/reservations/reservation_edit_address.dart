import '../../core/booking_address_carry.dart' show AddrQuick;
import '../booking/widgets/address_picker.dart' show sameAddressLine, splitAddressLine;
import 'reservation_models.dart';

/// Adresy přistavení / odvozu při úpravě rezervace (majitel 2026-10-22:
/// „neměl by nikdy zákazník nic vyplňovat dvakrát“). Rezervace, která už
/// adresu má, ji ukáže vyplněnou (dřív „Klikni a zadej adresu“) a list
/// adresy nabídne adresu druhé strany a adresu z profilu jedním klepnutím.
/// Výpočet ceny ani ukládání se nemění: dokud zákazník adresu nezmění,
/// zůstává `_pickupAddrNew` / `_returnAddrNew` null (potvrzení stejné
/// adresy = tentýž text = beze změny, viz `EditPriceCalc._normAddr`).
/// Sdílí oba stromy appky i oba vzhledy.
class EditAddressCarry {
  /// Adresa uložená v rezervaci — jen strana, která je na adrese.
  final String? savedPickup;
  final String? savedReturn;

  /// Adresa strany, jak ji úprava teď drží (null = pobočka / nezadaná).
  final String? pickupNow;
  final String? returnNow;

  const EditAddressCarry._(this.savedPickup, this.savedReturn, this.pickupNow, this.returnNow);

  static String? _saved(String? method, String? address) {
    final a = (address ?? '').trim();
    return method == 'delivery' && a.isNotEmpty ? a : null;
  }

  factory EditAddressCarry.of(
    Reservation b, {
    required String pickupMethod,
    required String returnMethod,
    String? pickupNew,
    String? returnNew,
  }) {
    final sp = _saved(b.pickupMethod, b.pickupAddress);
    final sr = _saved(b.returnMethod, b.returnAddress);
    return EditAddressCarry._(
      sp,
      sr,
      pickupMethod == 'delivery' ? (pickupNew ?? sp) : null,
      returnMethod == 'delivery' ? (returnNew ?? sr) : null,
    );
  }

  /// Rychlé volby listu adresy strany [pickup]: adresa druhé strany (je-li
  /// na adrese) a adresa z profilu — bez té, kterou strana už má, a bez
  /// duplicit. [tr] = překlad klíče.
  List<AddrQuick> quick(String Function(String) tr,
      {required bool pickup, Map<String, dynamic>? profile}) {
    final mine = pickup ? pickupNow : returnNow;
    final out = <AddrQuick>[];
    bool known(String line) =>
        sameAddressLine(line, mine) || out.any((q) => sameAddressLine('${q.street}, ${q.city}', line));
    final other = pickup ? returnNow : pickupNow;
    if (other != null && !known(other)) {
      final (street, city) = splitAddressLine(other);
      out.add(AddrQuick(label: tr(pickup ? 'bkAddrSameReturn' : 'bkAddrSamePickup'), street: street, city: city));
    }
    String pv(String k) => (profile?[k] ?? '').toString().trim();
    final pc = pv('city'), ps = pv('street');
    if (pc.isNotEmpty && !known('$ps, $pc')) {
      out.add(AddrQuick(label: tr('bkAddrMine'), street: ps, city: pc, zip: pv('zip')));
    }
    return out;
  }
}
