export const UNAVAILABLE_REASONS = [
  { value: 'cleaning', label: 'Čištění / mytí' },
  { value: 'refueling', label: 'Tankování' },
  { value: 'transport', label: 'Přeprava mezi pobočkami' },
  { value: 'inspection', label: 'Kontrola / STK' },
  { value: 'photo', label: 'Focení / marketing' },
  { value: 'seasonal', label: 'Sezónní vyřazení' },
  { value: 'damage_wait', label: 'Čekání na díly / pojistku' },
  { value: 'long_term', label: 'Dlouhodobé vyřazení' },
  { value: 'other', label: 'Jiný důvod' },
]

export const SERVICE_CHECKLIST = [
  { group: 'Motor & olej', items: [
    { id: 'oil_change', label: 'Výměna oleje' },
    { id: 'oil_filter', label: 'Výměna olejového filtru' },
    { id: 'air_filter', label: 'Výměna vzduchového filtru' },
    { id: 'spark_plugs', label: 'Výměna svíček' },
    { id: 'coolant', label: 'Kontrola / výměna chladicí kapaliny' },
    { id: 'engine_noise', label: 'Neobvyklý zvuk motoru' },
  ]},
  { group: 'Brzdy & podvozek', items: [
    { id: 'brake_pads_front', label: 'Brzdové destičky přední' },
    { id: 'brake_pads_rear', label: 'Brzdové destičky zadní' },
    { id: 'brake_fluid', label: 'Výměna brzdové kapaliny' },
    { id: 'brake_discs', label: 'Kontrola brzdových kotoučů' },
    { id: 'suspension', label: 'Kontrola tlumičů / pružin' },
  ]},
  { group: 'Pneumatiky & kola', items: [
    { id: 'tire_front', label: 'Výměna přední pneumatiky' },
    { id: 'tire_rear', label: 'Výměna zadní pneumatiky' },
    { id: 'tire_pressure', label: 'Kontrola tlaku pneumatik' },
    { id: 'wheel_bearings', label: 'Kontrola ložisek kol' },
  ]},
  { group: 'Řetěz & převody', items: [
    { id: 'chain_adjust', label: 'Seřízení řetězu' },
    { id: 'chain_replace', label: 'Výměna řetězu + rozet' },
    { id: 'chain_lube', label: 'Promazání řetězu' },
  ]},
  { group: 'Elektrika & světla', items: [
    { id: 'battery', label: 'Kontrola / výměna baterie' },
    { id: 'lights', label: 'Kontrola světel' },
    { id: 'fuses', label: 'Kontrola pojistek' },
    { id: 'starter', label: 'Problém se startérem' },
  ]},
  { group: 'Ostatní', items: [
    { id: 'stk', label: 'Příprava na STK' },
    { id: 'clutch', label: 'Kontrola / seřízení spojky' },
    { id: 'cosmetic', label: 'Kosmetická oprava (lak, plasty)' },
    { id: 'accident_repair', label: 'Oprava po nehodě' },
    { id: 'other_repair', label: 'Jiná oprava' },
  ]},
]

// Stejný checklist jako seznam štítků po kategoriích — pro formuláře, které
// pracují jen se štítky (ServiceLogModal, AddServiceFromCalendar). JEDEN zdroj
// pravdy: nový úkon se přidá jen sem a objeví se ve všech servisních formulářích.
export const SERVICE_CHECKLIST_BY_CATEGORY = SERVICE_CHECKLIST.map(g => ({
  category: g.group, items: g.items.map(i => i.label),
}))

// Typy SOS události (SOS → URGENT servisní záznam, SOSServiceCard) — standardní
// štítky, ne „Jiné“: musí být ve známé množině, jinak by je editace záznamu přes
// Správu motorky (ServiceChecklistView) uložila jako vlastní úkon.
export const SOS_SERVICE_TYPES = [
  { id: 'sos_accident_major', label: 'Těžká nehoda' },
  { id: 'sos_accident_minor', label: 'Lehká nehoda' },
  { id: 'sos_breakdown', label: 'Porucha' },
  { id: 'sos_theft_damage', label: 'Poškození při krádeži' },
]

/** Všechny standardní štítky úkonů vč. SOS typů (co není v množině = vlastní úkon „Jiné“). */
export const SERVICE_CHECKLIST_LABELS = new Set([
  ...SERVICE_CHECKLIST.flatMap(g => g.items.map(i => i.label)),
  ...SOS_SERVICE_TYPES.map(i => i.label),
])
