import { SERVICE_GROUPS, SERVICE_TASKS } from './serviceCatalog'

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

// Servisní checklist = katalog úkonů (serviceCatalog.js) ve tvaru skupin { group, items: [{ id, label }] }.
// JEDEN zdroj pravdy: nový úkon se přidá do serviceCatalog.js a objeví se ve všech servisních formulářích
// (ServiceLogModal, AddServiceFromCalendar, ServiceChecklistView, SOSServiceCard) i v servisní knize.
export const SERVICE_CHECKLIST = SERVICE_GROUPS.map(g => ({
  group: g.label, key: g.key, items: g.items.map(i => ({ id: i.id, label: i.label, kind: i.kind, only: i.only || null })),
}))

// Stejný checklist jako seznam štítků po kategoriích — pro formuláře, které
// pracují jen se štítky.
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

/** Všechny standardní štítky úkonů vč. historických aliasů a SOS typů (co není v množině = vlastní úkon „Jiné“). */
export const SERVICE_CHECKLIST_LABELS = new Set([
  ...SERVICE_TASKS.flatMap(t => [t.label, ...(t.aliases || [])]),
  ...SOS_SERVICE_TYPES.map(i => i.label),
])

/** štítek (vč. aliasu / SOS typu) → id úkonu; null = vlastní úkon */
export const SERVICE_LABEL_TO_ID = (() => {
  const m = {}
  for (const t of SERVICE_TASKS) { m[t.label] = t.id; for (const a of t.aliases || []) m[a] = t.id }
  for (const s of SOS_SERVICE_TYPES) m[s.label] = s.id
  return m
})()
