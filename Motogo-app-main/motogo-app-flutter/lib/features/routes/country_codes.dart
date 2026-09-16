/// Sdílený číselník států pro filtry Tras i Míst.
///
/// PROČ: `routes.countries` je v DB volný `text[]` — seedy tam zapsaly jednou
/// ISO kód („CZ"), jindy český název („Česko"), a Velín ho ukládá přes
/// `split(',')` bez validace. Bez normalizace se pro jeden stát nabídnou DVA
/// chipy a zaškrtnutí jednoho nenajde trasy označené druhým. `countryIso2()`
/// proto všechno srovná na ISO-2 už při parsování modelu.
///
/// Katalogové body (`points_of_interest.country`) ISO mají, takže po
/// normalizaci sedí trasy i místa na stejný číselník.
library;

/// Státy připnuté na začátek filtru (v tomto pořadí). Zbytek se schová pod
/// rozbalovač „Další státy" — zadání uživatele z 16. 9. 2026.
const List<String> kPriorityCountries = [
  'CZ', 'SK', 'AT', 'HU', 'IT', 'HR', 'SI',
];

/// Vlajky — ISO-2 → emoji. Kód bez záznamu dostane neutrální vlaječku.
const Map<String, String> _flags = {
  'AD': '🇦🇩', 'AL': '🇦🇱', 'AT': '🇦🇹', 'BA': '🇧🇦', 'BE': '🇧🇪', 'BG': '🇧🇬',
  'BY': '🇧🇾', 'CH': '🇨🇭', 'CY': '🇨🇾', 'CZ': '🇨🇿', 'DE': '🇩🇪', 'DK': '🇩🇰',
  'EE': '🇪🇪', 'ES': '🇪🇸', 'FI': '🇫🇮', 'FR': '🇫🇷', 'GB': '🇬🇧', 'GR': '🇬🇷',
  'HR': '🇭🇷', 'HU': '🇭🇺', 'IE': '🇮🇪', 'IM': '🇮🇲', 'IS': '🇮🇸', 'IT': '🇮🇹',
  'LI': '🇱🇮', 'LT': '🇱🇹', 'LU': '🇱🇺', 'LV': '🇱🇻', 'MC': '🇲🇨', 'MD': '🇲🇩',
  'ME': '🇲🇪', 'MK': '🇲🇰', 'MT': '🇲🇹', 'NL': '🇳🇱', 'NO': '🇳🇴', 'PL': '🇵🇱',
  'PT': '🇵🇹', 'RO': '🇷🇴', 'RS': '🇷🇸', 'SE': '🇸🇪', 'SI': '🇸🇮', 'SK': '🇸🇰',
  'SM': '🇸🇲', 'TR': '🇹🇷', 'UA': '🇺🇦', 'VA': '🇻🇦', 'XK': '🇽🇰',
};

/// České názvy států — pro rozbalovací seznam „Další státy", kde samotný
/// dvoupísmenný kód nic neříká.
const Map<String, String> _namesCs = {
  'AD': 'Andorra', 'AL': 'Albánie', 'AT': 'Rakousko', 'BA': 'Bosna a Hercegovina',
  'BE': 'Belgie', 'BG': 'Bulharsko', 'BY': 'Bělorusko', 'CH': 'Švýcarsko',
  'CY': 'Kypr', 'CZ': 'Česko', 'DE': 'Německo', 'DK': 'Dánsko', 'EE': 'Estonsko',
  'ES': 'Španělsko', 'FI': 'Finsko', 'FR': 'Francie', 'GB': 'Spojené království',
  'GR': 'Řecko', 'HR': 'Chorvatsko', 'HU': 'Maďarsko', 'IE': 'Irsko',
  'IM': 'Ostrov Man', 'IS': 'Island', 'IT': 'Itálie', 'LI': 'Lichtenštejnsko',
  'LT': 'Litva', 'LU': 'Lucembursko', 'LV': 'Lotyšsko', 'MC': 'Monako',
  'MD': 'Moldavsko', 'ME': 'Černá Hora', 'MK': 'Severní Makedonie', 'MT': 'Malta',
  'NL': 'Nizozemsko', 'NO': 'Norsko', 'PL': 'Polsko', 'PT': 'Portugalsko',
  'RO': 'Rumunsko', 'RS': 'Srbsko', 'SE': 'Švédsko', 'SI': 'Slovinsko',
  'SK': 'Slovensko', 'SM': 'San Marino', 'TR': 'Turecko', 'UA': 'Ukrajina',
  'VA': 'Vatikán', 'XK': 'Kosovo',
};

/// Názvy (a jejich zlomky ze seedů) → ISO-2. Klíče jsou bez diakritiky
/// a malými písmeny, viz [_norm].
const Map<String, String> _nameToIso = {
  'cesko': 'CZ', 'ceska republika': 'CZ', 'czechia': 'CZ', 'czech republic': 'CZ',
  'slovensko': 'SK', 'slovakia': 'SK',
  'rakousko': 'AT', 'austria': 'AT', 'osterreich': 'AT',
  'madarsko': 'HU', 'hungary': 'HU',
  'italie': 'IT', 'italy': 'IT', 'italia': 'IT',
  'chorvatsko': 'HR', 'croatia': 'HR', 'hrvatska': 'HR',
  'slovinsko': 'SI', 'slovenia': 'SI',
  'nemecko': 'DE', 'germany': 'DE', 'deutschland': 'DE',
  'polsko': 'PL', 'poland': 'PL', 'polska': 'PL',
  'francie': 'FR', 'france': 'FR',
  'svycarsko': 'CH', 'switzerland': 'CH',
  'spanelsko': 'ES', 'spain': 'ES',
  'cerna hora': 'ME', 'montenegro': 'ME',
  'bosna a hercegovina': 'BA', 'bosna': 'BA',
  'severni makedonie': 'MK', 'makedonie': 'MK', 'severni': 'MK',
  'spojene kralovstvi': 'GB', 'velka britanie': 'GB', 'spojene': 'GB',
  'anglie': 'GB', 'skotsko': 'GB', 'wales': 'GB', 'england': 'GB', 'scotland': 'GB',
  'norsko': 'NO', 'norway': 'NO',
  'svedsko': 'SE', 'sweden': 'SE',
  'finsko': 'FI', 'finland': 'FI',
  'dansko': 'DK', 'denmark': 'DK',
  'nizozemsko': 'NL', 'holandsko': 'NL', 'netherlands': 'NL',
  'belgie': 'BE', 'belgium': 'BE',
  'lucembursko': 'LU', 'luxembourg': 'LU',
  'irsko': 'IE', 'ireland': 'IE',
  'portugalsko': 'PT', 'portugal': 'PT',
  'rumunsko': 'RO', 'romania': 'RO',
  'bulharsko': 'BG', 'bulgaria': 'BG',
  'srbsko': 'RS', 'serbia': 'RS',
  'recko': 'GR', 'greece': 'GR',
  'albanie': 'AL', 'albania': 'AL',
  'island': 'IS', 'iceland': 'IS',
  'estonsko': 'EE', 'litva': 'LT', 'lotyssko': 'LV',
  'moldavsko': 'MD', 'moldavie': 'MD',
  'ukrajina': 'UA', 'ukraine': 'UA',
  'turecko': 'TR', 'turkey': 'TR',
  'andorra': 'AD', 'lichtenstejnsko': 'LI', 'liechtenstein': 'LI',
  'malta': 'MT', 'kypr': 'CY', 'kosovo': 'XK', 'monako': 'MC',
  'san marino': 'SM', 'vatikan': 'VA', 'ostrov man': 'IM', 'isle of man': 'IM',
  'belorusko': 'BY',
};

const Map<String, String> _diacritics = {
  'á': 'a', 'č': 'c', 'ď': 'd', 'é': 'e', 'ě': 'e', 'í': 'i', 'ň': 'n',
  'ó': 'o', 'ř': 'r', 'š': 's', 'ť': 't', 'ú': 'u', 'ů': 'u', 'ý': 'y',
  'ž': 'z', 'ä': 'a', 'ö': 'o', 'ü': 'u', 'ß': 's', 'ł': 'l', 'ą': 'a',
  'ę': 'e', 'ś': 's', 'ź': 'z', 'ż': 'z', 'ć': 'c', 'ń': 'n', 'õ': 'o',
  'à': 'a', 'è': 'e', 'ì': 'i', 'ò': 'o', 'ù': 'u', 'â': 'a', 'ê': 'e',
};

String _norm(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().trim().split('')) {
    b.write(_diacritics[ch] ?? ch);
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ');
}

/// Srovná libovolnou hodnotu ze sloupce `countries` / `country` na ISO-2.
/// Vrací null pro prázdnou nebo nerozpoznanou hodnotu (ta se pak ve filtru
/// neobjeví — lepší než nabízet chip, který nic nenajde).
String? countryIso2(dynamic raw) {
  final s = raw?.toString().trim() ?? '';
  if (s.isEmpty) return null;
  if (s.length == 2) {
    final up = s.toUpperCase();
    return _flags.containsKey(up) ? up : up; // neznámý 2písmenný kód projde
  }
  return _nameToIso[_norm(s)];
}

/// Vlajka + kód, např. „🇨🇿 CZ" — kompaktní popisek chipu.
String countryChipLabel(String iso) => '${_flags[iso] ?? '🏳️'} $iso';

/// Vlajka + český název, např. „🇦🇹 Rakousko" — pro rozbalený seznam.
String countryFullLabel(String iso) =>
    '${_flags[iso] ?? '🏳️'} ${_namesCs[iso] ?? iso}';

/// Seřadí kódy tak, že [kPriorityCountries] jdou první (v daném pořadí)
/// a zbytek abecedně podle českého názvu.
({List<String> top, List<String> rest}) splitByPriority(Iterable<String> codes) {
  final set = codes.toSet();
  final top = kPriorityCountries.where(set.contains).toList();
  final rest = set.where((c) => !kPriorityCountries.contains(c)).toList()
    ..sort((a, b) => (_namesCs[a] ?? a).compareTo(_namesCs[b] ?? b));
  return (top: top, rest: rest);
}
