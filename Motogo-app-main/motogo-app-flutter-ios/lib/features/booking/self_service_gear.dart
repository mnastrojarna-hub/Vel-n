/// Velikosti výbavy na SAMOOBSLUŽNÉ pobočce (`branches.type =
/// 'samoobslužná'`, zadání majitele 2026-10-10) — JEN dospělá výbava:
/// helma S–3XL; bunda, kalhoty a rukavice nejvýš 4XL (větší jen v Mezné).
/// Boty (čísla), kukla (UNI) a dětské řady (`YM`, „4–7 let“…) beze změny.
/// Filtruje se podle POŘADÍ velikostí, ne bílou listinou — hodnota, kterou
/// pořadí nezná, projde. Parita: kiosk `motogo_box/gear_limits.py`, edge
/// `submit-handover-protocol/gear.ts`, web `js/gear-ss-cap.js`.
library;

const Map<String, int> _sizeRank = {
  'XXS': 0, 'XS': 1, 'S': 2, 'M': 3, 'L': 4, 'XL': 5,
  '2XL': 6, 'XXL': 6, '3XL': 7, 'XXXL': 7, '4XL': 8, 'XXXXL': 8,
  '5XL': 9, '6XL': 10,
};

/// Spodní / horní mez dle druhu výbavy (klíč chybí = bez meze).
const Map<String, String> _selfServiceMin = {'helmet': 'S'};
const Map<String, String> _selfServiceMax = {
  'helmet': '3XL', 'jacket': '4XL', 'pants': '4XL', 'gloves': '4XL',
};

int? _rank(String? size) =>
    size == null ? null : _sizeRank[size.trim().toUpperCase()];

/// Smí se velikost [size] výbavy [type] (`helmet`/`jacket`/`pants`/`gloves`/
/// `boots`) nabídnout na samoobslužné pobočce? Prázdná velikost, čísla bot
/// a dětské popisky (pořadí je nezná) = ano. Jen pro dospělou výbavu.
bool selfServiceSizeAllowed(String type, String? size) {
  final r = _rank(size);
  if (r == null) return true;
  final lo = _rank(_selfServiceMin[type]);
  final hi = _rank(_selfServiceMax[type]);
  return (lo == null || r >= lo) && (hi == null || r <= hi);
}

/// Dospělá řada [sizes] zúžená pravidlem samoobsluhy (pořadí zachováno).
List<String> selfServiceGearSizes(String type, List<String> sizes) =>
    sizes.where((s) => selfServiceSizeAllowed(type, s)).toList(growable: false);
