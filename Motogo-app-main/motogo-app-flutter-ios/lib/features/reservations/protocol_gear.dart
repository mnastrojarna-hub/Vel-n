import 'package:flutter/foundation.dart';

import '../../core/i18n/i18n_provider.dart';
import '../../core/supabase_client.dart';
import '../booking/booking_models.dart';
import 'reservation_models.dart';

/// Pět druhů výbavy, které se v předávacím protokolu upravují a propisují
/// do `bookings.<key>_size` / `passenger_<key>_size` (edge
/// `submit-handover-protocol`, `form.accessories[]`).
const protocolGearKeys = ['helmet', 'jacket', 'pants', 'boots', 'gloves'];

/// České popisky pro PDF (dokument je VŽDY česky — appka jen vícejazyčně).
const _gearLabelCs = {
  'helmet': 'Helma', 'jacket': 'Bunda', 'pants': 'Kalhoty',
  'boots': 'Boty', 'gloves': 'Rukavice',
};

/// Jedna položka zapůjčené výbavy v protokolu: `key` × `who` určují sloupec
/// rezervace (`field`), velikost je upravitelná (chip/dropdown z číselníku).
class ProtocolGearItem {
  final String key; // helmet | jacket | pants | boots | gloves
  final String who; // rider | passenger
  String? size;
  bool checked;

  ProtocolGearItem({required this.key, required this.who, this.size, this.checked = true});

  String get field => who == 'passenger' ? 'passenger_${key}_size' : '${key}_size';

  /// Popisek do dokumentu (česky, jako dosud: „Helma (řidič)“).
  String get labelCs => '${_gearLabelCs[key] ?? key} (${who == 'passenger' ? 'spolujezdec' : 'řidič'})';

  /// Popisek v UI appky (jazyk zákazníka).
  String label(AppTranslations t) {
    final name = key == 'boots' ? t.tr('hpBoots') : t.tr(key);
    return '$name (${t.tr(who == 'passenger' ? 'hpPassenger' : 'hpRider')})';
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'who': who,
        'field': field,
        'label': labelCs,
        'size': size ?? '',
        'checked': checked,
      };
}

/// Výbava z rezervace — jen neprázdné velikosti (stejně jako `_kiosk_protocol`).
List<ProtocolGearItem> buildProtocolGear(Reservation r) {
  final out = <ProtocolGearItem>[];
  void add(String key, String who, String? size) {
    if (size != null && size.trim().isNotEmpty) {
      out.add(ProtocolGearItem(key: key, who: who, size: size.trim()));
    }
  }
  add('helmet', 'rider', r.helmetSize);
  add('jacket', 'rider', r.jacketSize);
  add('pants', 'rider', r.pantsSize);
  add('boots', 'rider', r.bootsSize);
  add('gloves', 'rider', r.glovesSize);
  add('helmet', 'passenger', r.passengerHelmetSize);
  add('jacket', 'passenger', r.passengerJacketSize);
  add('pants', 'passenger', r.passengerPantsSize);
  add('boots', 'passenger', r.passengerBootsSize);
  add('gloves', 'passenger', r.passengerGlovesSize);
  return out;
}

/// Číselník velikostí z `accessory_types` (policy „Public read“): jen 5 klíčů
/// výbavy, aktivní (`is_active` ≠ false — NULL bere jako aktivní stejně jako
/// kiosk `kiosk_sync_config.gear_sizes` a edge), `audience` dle motorky
/// (dětská = child/both, jinak adult/both). Když tabulka nic nevrátí (offline,
/// prázdné sizes), platí lokální seznamy [gearSizesFor] — dropdown nikdy
/// nezůstane prázdný.
Future<Map<String, List<String>>> loadProtocolGearSizes({required bool kids}) async {
  final out = <String, List<String>>{};
  try {
    final rows = await MotoGoSupabase.client
        .from('accessory_types')
        .select('key, sizes, is_active, audience')
        .inFilter('key', protocolGearKeys)
        .or('is_active.is.null,is_active.eq.true');
    for (final r in (rows as List)) {
      final m = r as Map<String, dynamic>;
      final aud = (m['audience'] as String?) ?? 'adult';
      if (aud != 'both' && aud != (kids ? 'child' : 'adult')) continue;
      final sizes = (m['sizes'] as List?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const <String>[];
      if (sizes.isNotEmpty) out[m['key'] as String] = sizes;
    }
  } catch (e) {
    debugPrint('[PROTOCOL] accessory_types load failed: $e');
  }
  for (final k in protocolGearKeys) {
    out.putIfAbsent(k, () => gearSizesFor(k, kids: kids));
  }
  return out;
}
