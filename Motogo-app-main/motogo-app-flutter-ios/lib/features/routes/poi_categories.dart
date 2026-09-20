import 'routes_model.dart';

/// Sdílená logika kategorií bodů zájmu (katalog všech POI + panel „v okolí"
/// v editoru trasy). Přednost má explicitní `category` z backendu; jinak se
/// odvodí heuristicky z názvu/popisu.

/// Definice kategorie bodů zájmu (klíč + emoji + i18n klíč popisku).
class PoiCat {
  final String key;
  final String emoji;
  final String i18nKey;
  const PoiCat(this.key, this.emoji, this.i18nKey);
}

const List<PoiCat> kPoiCats = [
  PoiCat('food', '🍽️', 'poiCatFood'),
  PoiCat('castle', '🏰', 'poiCatCastle'),
  PoiCat('lookout', '🗼', 'poiCatLookout'),
  PoiCat('water', '🌊', 'poiCatWater'),
  PoiCat('spring', '⛲', 'poiCatSpring'),
  PoiCat('sights', '⛪', 'poiCatSights'),
  PoiCat('nature', '🌳', 'poiCatNature'),
  PoiCat('military', '🪖', 'poiCatMilitary'),
  PoiCat('aviation', '✈️', 'poiCatAviation'),
  PoiCat('tech', '🏭', 'poiCatTech'),
  PoiCat('moto', '🏁', 'poiCatMoto'),
  PoiCat('other', '📍', 'poiCatOther'),
];

// „hrad" jen na začátku slova — jinak chytá „zahrada" i „přehrada".
final RegExp _reHrad = RegExp(r'\bhrad');

/// Známé klíče kategorií (pro validaci explicitní hodnoty z backendu).
const Set<String> kPoiCatKeys = {
  'food', 'castle', 'lookout', 'water', 'spring', 'sights', 'nature', 'other',
  'military', 'aviation', 'tech', 'moto'
};

// Klíčová slova (bez diakritiky, malá písmena). Kryjí i SK/PL/DE/AT varianty.
const List<String> _kwFood = [
  'restaur', 'hospod', 'hostin', 'pivovar', 'kavar', 'cafe', 'cukrar',
  'obcerstv', 'bistro', 'motorest', 'vinar', 'grill', 'pizz', 'krcma',
  'koliba', 'salas', 'bufet', 'gostiln', 'gasthof', 'gasthaus', 'brauhaus'
];
const List<String> _kwCastle = [
  'zamek', 'zamec', 'zamok', 'zricen', 'tvrz', 'palac', 'castle', 'schloss',
  'pevnost', 'hradisk', 'hradisc', 'burg', 'chateau', 'castel', 'citadel'
];
// Kategorie „Rozhledny a vrcholy" — kromě rozhleden sem patří i vrcholy a hory
// (zadání uživatele: vrcholy se mají hledat pohromadě s rozhlednami, ne
// v „Přírodě" mezi rybníky a sedly).
const List<String> _kwLookout = [
  'rozhled', 'vyhlid', 'vyhled', 'vez', 'aussicht', 'panorama',
  'vrch', 'hora', 'kopec'
];
// Studánky a prameny — vlastní kategorie (zadání uživatele 2026-09-20:
// „chybí studánky"). Kontroluje se PŘED vodou i přírodou, jinak by „Koňský
// pramen" spadl mezi rybníky a „Studánka U Tří lip" by neodpovídala ničemu
// (slovo „studánk" dřív nebylo v ŽÁDNÉM seznamu a končilo v „Ostatní").
const List<String> _kwSpring = [
  'studank', 'studanc', 'pramenist', 'pramenisk', 'kyselk', 'vyver',
  'zriedl', 'mineralni pramen', 'quelle', 'brunnen', 'zridlo', 'pramen'
];
const List<String> _kwWater = [
  'prehrad', 'priehrad', 'rybnik', 'jezer', 'jazer', 'vodopad', 'nadrz',
  'plaz', 'splav', 'soutok', 'see', 'loch', 'fjord', 'lago', 'jazior'
];
const List<String> _kwSights = [
  'kostel', 'klaster', 'klastor', 'kaple', 'kaplnk', 'katedral', 'bazilik',
  'poutni', 'pamatnik', 'pamatn', 'muzeum', 'muzej', 'museum', 'synagog',
  'mohyla', 'pomnik', 'betlem', 'krizov', 'rotund', 'namesti', 'namest',
  'hrobka', 'skanzen', 'radnice', 'chram', 'opatstv', 'sgrafit'
];
// Kategorie cílovky — kontrolují se PŘED castle (bunkr ať nespadne do hradů).
const List<String> _kwMilitary = [
  'bunkr', 'bunker', 'ropik', 'pechotni srub', 'delostreleck', 'opevnen',
  'fortifik', 'vojensk', 'militar', 'military', 'armadni', 'kasarn',
  'maginot', 'atlantikwall', 'bojist', 'battlefield', 'festungswerk'
];
const List<String> _kwAviation = [
  'letist', 'letisk', 'leteck', 'aviatik', 'aviation', 'flugplatz',
  'flughafen', 'airfield', 'airport', 'luftfahrt', 'hangar', 'aerodrom'
];
const List<String> _kwTech = [
  'technick', 'hornick', 'bergwerk', 'kopalni', 'elektrarn', 'kraftwerk',
  'uzkokolejk', 'zeleznicni muzeum', 'eisenbahnmuseum', 'viadukt', 'stola'
];
const List<String> _kwMoto = [
  'autodrom', 'zavodni okruh', 'racing', 'circuit', 'rennstreck',
  'motocyklov', 'automobilov', 'automuseum', 'veteran', 'motokros'
];
// Pozn.: 'vrch', 'hora' a 'kopec' se přesunuly do _kwLookout („Rozhledny
// a vrcholy"); tady zůstává jen to, co je opravdu příroda bez výhledu.
const List<String> _kwNature = [
  'jeskyn', 'jaskyn', 'propast', 'skal', 'prales', 'park',
  // 'pramen' se přesunul do _kwSpring („Studánky a prameny").
  'sedlo', 'prusmyk', 'priesmyk', 'soutesk', 'udol', 'dolin',
  'zahrad', 'steny', 'stena', 'kamen', 'ostrov', 'pleso', 'plesa',
  'klamm', 'kanon', 'rezerv', 'jezirk', 'diery'
];

/// Odstranění diakritiky pro porovnávání klíčových slov.
String poiFold(String s) {
  const from = 'áäàâčćďéěèêíìîïľĺňñóöòôřšśťúůüýžźż';
  const to = 'aaaaccdeeeeiiiillnnoooorsstuuuyzzz';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString();
}

/// Kategorie bodu zájmu. Přednost má explicitní `category` z backendu; jinak
/// se odvodí z NÁZVU (spolehlivé — „Zámek …", „Rozhledna …", „Restaurace …")
/// a teprve když název mlčí, z popisu. „Jídlo a pití" se z popisu NEODVOZUJE:
/// skoro každý popis zmiňuje kavárnu/restauraci poblíž, což dřív házelo hrady
/// a rozhledny do kategorie jídla (např. zámek Jindřichův Hradec).
/// Výsledky se cachují na instanci bodu — `poiCategoryOf` se volá pro KAŽDÝ
/// špendlík i popisek při každém překreslení mapy a bez cache to je pokaždé
/// dvojí `poiFold` (znak po znaku) plus ~90 `contains`. Stejný vzorec používá
/// `RoutePoi.searchBlob` (routes_model.dart).
final Expando<String> _poiCatCache = Expando<String>();

String poiCategoryOf(RoutePoi p) => _poiCatCache[p] ??= _computeCategory(p);

String _computeCategory(RoutePoi p) {
  final explicit = p.category?.toLowerCase();
  if (explicit != null && kPoiCatKeys.contains(explicit)) return explicit;
  final byName = _catByText(poiFold(p.name), allowFood: true);
  if (byName != 'other') return byName;
  return _catByText(poiFold(p.description ?? ''), allowFood: false);
}

/// Emoji kategorie bodu zájmu — použije se jako zástupný náhled, když bod
/// nemá fotku (místo obecného špendlíku 📍 ukáže 🏰 hrad, 🌊 vodu, 🗼 rozhlednu…).
String poiCatEmoji(RoutePoi p) {
  final k = poiCategoryOf(p);
  for (final c in kPoiCats) {
    if (c.key == k) return c.emoji;
  }
  return '📍';
}

String _catByText(String n, {required bool allowFood}) {
  bool has(List<String> ks) => ks.any(n.contains);
  if (allowFood && has(_kwFood)) return 'food';
  if (has(_kwMilitary)) return 'military';
  if (has(_kwAviation)) return 'aviation';
  if (has(_kwMoto)) return 'moto';
  if (has(_kwTech)) return 'tech';
  if (_reHrad.hasMatch(n) || has(_kwCastle)) return 'castle';
  // Studánky před rozhlednami i vodou: „Studánkový vrch" je kopec, ale
  // „Pramen Vltavy" ani „Zlatá studánka" nejsou ani rozhledna, ani rybník.
  if (has(_kwLookout)) return 'lookout';
  if (has(_kwSpring)) return 'spring';
  if (has(_kwWater)) return 'water';
  if (has(_kwSights)) return 'sights';
  if (has(_kwNature)) return 'nature';
  return 'other';
}
