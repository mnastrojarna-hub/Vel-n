// Číselník kategorií bodů zájmu — JEDEN zdroj pravdy pro celý Velín.
//
// Musí sedět s:
//   * CHECK constraintem `points_of_interest_category_check`
//     (supabase/migrations/20260920e_poi_spring_category_and_recategorize.sql),
//   * `kPoiCats` v obou stromech appky
//     (Motogo-app-main/motogo-app-flutter{,-ios}/lib/features/routes/poi_categories.dart).
// Nový klíč se musí doplnit na všech třech místech naráz, jinak ho buď DB
// odmítne (chyba 23514), nebo ho appka zahodí do „Ostatní".

export const POI_CATS = {
  food:     '🍽️ Jídlo a pití',
  castle:   '🏰 Hrady a zámky',
  lookout:  '🗼 Rozhledny a vrcholy',
  water:    '🌊 Voda',
  spring:   '⛲ Studánky a prameny',
  sights:   '⛪ Památky',
  nature:   '🌳 Příroda',
  military: '🪖 Vojenství',
  aviation: '✈️ Letectví',
  tech:     '🏭 Technika',
  moto:     '🏁 Motorismus',
  other:    '📍 Ostatní',
}

export const POI_CAT_KEYS = Object.keys(POI_CATS)

export const catLabel = (k) => POI_CATS[k] || k || '—'

// Prefixy sloupce `source` ze seed migrací. Filtr ve Velíně je hledá přes
// `like(source, '<prefix>%')`, takže MUSÍ pokrýt všechny reálné hodnoty —
// dřív chyběly 'wikidata-cs-' (7 191 řádků) a 'wikidata-hills-cz-sk-' (3 295),
// tedy 27,8 % katalogu bylo přes filtr nedosažitelných.
export const POI_SOURCES = [
  ['all', 'Všechny zdroje'],
  ['curated-', 'Ruční (curated)'],
  ['wikidata-batch', 'Wikidata CZ/SK/PL/AT'],
  ['wikidata-cs-', 'Wikidata CZ (cs dávky)'],
  ['wikidata-eu-', 'Wikidata Evropa'],
  ['wikidata-cilovka', 'Wikidata cílovka (military/aviation/tech/moto)'],
  ['wikidata-hills-cz-sk-', 'Wikidata hory a rozhledny CZ/SK'],
  ['wikidata-nature-cz-sk-', 'Wikidata příroda a technika CZ/SK'],
  ['velin-', 'Založeno ve Velíně'],
]

export const POI_COUNTRIES = [
  'CZ', 'SK', 'PL', 'AT', 'DE', 'FR', 'IT', 'ES', 'GB', 'NL', 'BE', 'CH',
  'SI', 'HR', 'HU', 'RO', 'RS', 'GR', 'PT', 'IE', 'DK', 'SE', 'NO', 'FI',
]

/** Má bod fotku tak, jak ji vidí appka? (RPC get_pois_catalog posílá
 *  `coalesce(image_url, images[1])`, takže samotné image_url nestačí.) */
export const poiPhoto = (p) => p?.image_url || (Array.isArray(p?.images) ? p.images[0] : null) || null
