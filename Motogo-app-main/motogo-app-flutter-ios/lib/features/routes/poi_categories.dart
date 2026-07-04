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
  PoiCat('sights', '⛪', 'poiCatSights'),
  PoiCat('nature', '🌳', 'poiCatNature'),
  PoiCat('other', '📍', 'poiCatOther'),
];

// „hrad" jen na začátku slova — jinak chytá „zahrada" i „přehrada".
final RegExp _reHrad = RegExp(r'\bhrad');

/// Známé klíče kategorií (pro validaci explicitní hodnoty z backendu).
const Set<String> kPoiCatKeys = {
  'food', 'castle', 'lookout', 'water', 'sights', 'nature', 'other'
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
const List<String> _kwLookout = [
  'rozhled', 'vyhlid', 'vyhled', 'vez', 'aussicht', 'panorama'
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
const List<String> _kwNature = [
  'jeskyn', 'jaskyn', 'propast', 'skal', 'prales', 'park', 'vrch', 'hora',
  'sedlo', 'prusmyk', 'priesmyk', 'soutesk', 'udol', 'dolin', 'pramen',
  'zahrad', 'steny', 'stena', 'kamen', 'ostrov', 'pleso', 'plesa', 'kopec',
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
String poiCategoryOf(RoutePoi p) {
  final explicit = p.category?.toLowerCase();
  if (explicit != null && kPoiCatKeys.contains(explicit)) return explicit;
  final byName = _catByText(poiFold(p.name), allowFood: true);
  if (byName != 'other') return byName;
  return _catByText(poiFold(p.description ?? ''), allowFood: false);
}

String _catByText(String n, {required bool allowFood}) {
  bool has(List<String> ks) => ks.any(n.contains);
  if (allowFood && has(_kwFood)) return 'food';
  if (_reHrad.hasMatch(n) || has(_kwCastle)) return 'castle';
  if (has(_kwLookout)) return 'lookout';
  if (has(_kwWater)) return 'water';
  if (has(_kwSights)) return 'sights';
  if (has(_kwNature)) return 'nature';
  return 'other';
}
