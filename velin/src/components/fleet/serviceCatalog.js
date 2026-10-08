// Katalog servisních úkonů — JEDINÝ zdroj pravdy pro checklisty ve všech servisních
// formulářích, servisní knihu i automatické hlídání intervalů (maintenance_schedules.task_key).
// DB kopie: tabulka `service_task_catalog` (seed generuje `velin/scripts/gen-service-catalog-sql.mjs`
// z tohoto souboru — po změně katalogu seed přegenerovat do nové migrace).
//
// Položka: { id, label, kind: replace|check|adjust|repair|other, km?, months?, hours?, track?, only?, implies?, aliases? }
//  - `track: true`  = součást „základního standardu“: pro každou motorku vznikne plán (interval km/měsíce;
//                     u motorek s tracking_unit=mh je `km` v motohodinách), výrobcem předepsaná hodnota má přednost
//  - `only`         = jen pro pohon chain|shaft|belt, chlazení liquid, hydraulickou spojku hydraulic, nebo hours (mh)
//  - `implies`      = odškrtnutí úkonu splní i tyto plány (sada brzd = destičky + kotouč)
//  - `aliases`      = dřívější štítky stejného úkonu (historické záznamy v maintenance_log.items)
//  - `moto`         = interval se bere z karty motorky: oil|tire|full
// Štítky (label) se ukládají do maintenance_log.items — NEPŘEJMENOVÁVAT bez alias.

export const SERVICE_GROUPS = [
  { key: 'engine', label: 'Motor & olej', items: [
    { id: 'oil_change', label: 'Výměna oleje', kind: 'replace', km: 10000, months: 12, track: true, moto: 'oil', aliases: ['Výměna motorového oleje'] },
    { id: 'oil_filter', label: 'Výměna olejového filtru', kind: 'replace', km: 10000, months: 12, track: true, moto: 'oil' },
    { id: 'air_filter', label: 'Výměna vzduchového filtru', kind: 'replace', km: 20000, months: 24, track: true },
    { id: 'air_filter_clean', label: 'Čištění vzduchového filtru', kind: 'check', km: 5000 },
    { id: 'spark_plugs', label: 'Výměna svíček', kind: 'replace', km: 20000, months: 24, track: true },
    { id: 'valve_clearance', label: 'Kontrola / seřízení ventilových vůlí', kind: 'check', km: 24000, track: true },
    { id: 'timing_check', label: 'Kontrola / dopnutí rozvodů', kind: 'check', km: 24000, track: true },
    { id: 'throttle_sync', label: 'Synchronizace škrticích klapek / karburátorů', kind: 'adjust', km: 24000 },
    { id: 'fuel_filter', label: 'Výměna palivového filtru', kind: 'replace', km: 40000, months: 48 },
    { id: 'fuel_system', label: 'Oprava palivové soustavy (čerpadlo, vstřikování, karburátor)', kind: 'repair' },
    { id: 'engine_noise', label: 'Neobvyklý zvuk motoru', kind: 'repair' },
    { id: 'oil_leak', label: 'Únik oleje — diagnostika / oprava', kind: 'repair' },
    { id: 'exhaust', label: 'Oprava / výměna výfuku', kind: 'repair' },
    { id: 'gearbox_oil', label: 'Výměna převodového oleje (skútr / dvoutakt)', kind: 'replace', km: 10000, months: 24, track: true, only: 'belt' },
  ] },
  { key: 'cooling', label: 'Chlazení', items: [
    { id: 'coolant_change', label: 'Výměna chladicí kapaliny', kind: 'replace', km: 40000, months: 36, track: true, only: 'liquid', implies: ['coolant_check'], aliases: ['Kontrola / výměna chladicí kapaliny'] },
    { id: 'coolant_check', label: 'Kontrola hladiny a stavu chladicí kapaliny', kind: 'check', km: 6000, only: 'liquid' },
    { id: 'radiator', label: 'Čištění chladiče / kontrola ventilátoru', kind: 'check', months: 12, only: 'liquid' },
    { id: 'cooling_repair', label: 'Oprava chlazení (termostat, čerpadlo, hadice)', kind: 'repair', only: 'liquid' },
  ] },
  { key: 'brakes', label: 'Brzdy', items: [
    { id: 'brake_pads_check', label: 'Kontrola brzdových destiček', kind: 'check', km: 5000, months: 6, track: true },
    { id: 'brake_pads_front', label: 'Brzdové destičky přední', kind: 'replace', implies: ['brake_pads_check'], aliases: ['Výměna brzdových destiček přední'] },
    { id: 'brake_pads_rear', label: 'Brzdové destičky zadní', kind: 'replace', implies: ['brake_pads_check'], aliases: ['Výměna brzdových destiček zadní'] },
    { id: 'brake_discs', label: 'Kontrola brzdových kotoučů', kind: 'check', km: 10000 },
    { id: 'brake_disc_front', label: 'Výměna brzdového kotouče přední', kind: 'replace' },
    { id: 'brake_disc_rear', label: 'Výměna brzdového kotouče zadní', kind: 'replace' },
    { id: 'brake_set_front', label: 'Výměna brzdové sady přední (destičky + kotouč)', kind: 'replace', implies: ['brake_pads_front', 'brake_disc_front'] },
    { id: 'brake_set_rear', label: 'Výměna brzdové sady zadní (destičky + kotouč)', kind: 'replace', implies: ['brake_pads_rear', 'brake_disc_rear'] },
    { id: 'brake_fluid', label: 'Výměna brzdové kapaliny', kind: 'replace', months: 24, track: true },
    { id: 'brake_lines', label: 'Výměna brzdových hadic', kind: 'replace', months: 48 },
    { id: 'brake_caliper', label: 'Servis brzdového třmenu (pístky, čištění)', kind: 'repair' },
    { id: 'abs_check', label: 'Kontrola / diagnostika ABS', kind: 'check' },
  ] },
  { key: 'chassis', label: 'Podvozek & řízení', items: [
    { id: 'suspension_check', label: 'Kontrola tlumičů / pružin', kind: 'check', months: 12, track: true },
    { id: 'fork_oil', label: 'Výměna oleje v přední vidlici', kind: 'replace', km: 30000, months: 36, track: true },
    { id: 'fork_seals', label: 'Přetěsnění přední vidlice (simerinky)', kind: 'repair' },
    { id: 'shock_service', label: 'Servis / přetěsnění zadního tlumiče', kind: 'repair' },
    { id: 'shock_replace', label: 'Výměna zadního tlumiče', kind: 'replace' },
    { id: 'steering_bearings', label: 'Kontrola / výměna ložisek řízení', kind: 'check', km: 24000 },
    { id: 'swingarm_bearings', label: 'Kontrola / mazání ložisek kyvné vidlice', kind: 'check', km: 24000 },
    { id: 'linkage_lube', label: 'Mazání čepů zadního odpružení', kind: 'adjust', km: 12000 },
    { id: 'wheel_bearings', label: 'Kontrola ložisek kol', kind: 'check', km: 20000, aliases: ['Kontrola / výměna ložisek kol'] },
    { id: 'wheel_bearings_replace', label: 'Výměna ložisek kol', kind: 'replace' },
    { id: 'side_stand', label: 'Kontrola / mazání stojánku', kind: 'check', months: 12 },
  ] },
  { key: 'tires', label: 'Pneumatiky & kola', items: [
    { id: 'tire_check', label: 'Kontrola stavu / dezénu pneumatik', kind: 'check', km: 3000 },
    { id: 'tire_pressure', label: 'Kontrola tlaku pneumatik', kind: 'check' },
    { id: 'tire_front', label: 'Výměna přední pneumatiky', kind: 'replace', track: true, moto: 'tire' },
    { id: 'tire_rear', label: 'Výměna zadní pneumatiky', kind: 'replace', track: true, moto: 'tire' },
    { id: 'wheel_balance', label: 'Vyvážení kol', kind: 'adjust' },
    { id: 'wheel_spokes', label: 'Kontrola / dotažení drátů kol', kind: 'check', km: 10000 },
    { id: 'valve_stems', label: 'Výměna ventilků', kind: 'replace' },
  ] },
  { key: 'drive', label: 'Řetěz / kardan / řemen', items: [
    { id: 'chain_adjust', label: 'Seřízení řetězu', kind: 'adjust', km: 1000, track: true, only: 'chain', aliases: ['Dopnutí / seřízení řetězu'] },
    { id: 'chain_lube', label: 'Promazání řetězu', kind: 'adjust', only: 'chain' },
    { id: 'chain_clean', label: 'Čištění řetězu', kind: 'adjust', only: 'chain' },
    { id: 'chain_check', label: 'Kontrola opotřebení řetězu a rozet', kind: 'check', km: 5000, only: 'chain' },
    { id: 'chain_kit', label: 'Výměna řetězu + rozet', kind: 'replace', km: 25000, track: true, only: 'chain', implies: ['chain_adjust', 'chain_check'], aliases: ['Výměna řetězové sady'] },
    { id: 'final_drive_oil', label: 'Výměna oleje v kardanu / rozvodovce', kind: 'replace', km: 20000, months: 24, track: true, only: 'shaft' },
    { id: 'final_drive_check', label: 'Kontrola kardanu (vůle, únik oleje)', kind: 'check', km: 10000, only: 'shaft' },
    { id: 'belt_check', label: 'Kontrola / napnutí řemenu', kind: 'check', km: 10000, only: 'belt' },
    { id: 'belt_replace', label: 'Výměna hnacího řemenu (CVT / rozvodový)', kind: 'replace', km: 24000, months: 48, track: true, only: 'belt' },
    { id: 'cvt_service', label: 'Servis variátoru (válečky, spojka)', kind: 'repair', km: 12000, only: 'belt' },
  ] },
  { key: 'clutch', label: 'Spojka & převodovka', items: [
    { id: 'clutch', label: 'Kontrola / seřízení spojky', kind: 'check', km: 6000, months: 12, track: true },
    { id: 'clutch_cable', label: 'Výměna lanka spojky', kind: 'replace' },
    { id: 'clutch_plates', label: 'Výměna spojkových lamel', kind: 'replace' },
    { id: 'clutch_fluid', label: 'Výměna kapaliny hydraulické spojky', kind: 'replace', months: 24, only: 'hydraulic' },
    { id: 'gearbox_issue', label: 'Problém s řazením — diagnostika / oprava', kind: 'repair' },
  ] },
  { key: 'electrics', label: 'Elektrika & světla', items: [
    { id: 'battery', label: 'Kontrola / výměna baterie', kind: 'check', months: 6, track: true, aliases: ['Kontrola / dobití baterie'] },
    { id: 'battery_replace', label: 'Výměna baterie', kind: 'replace', months: 36, implies: ['battery'] },
    { id: 'charging', label: 'Kontrola dobíjení (alternátor, regulátor)', kind: 'check', months: 12 },
    { id: 'lights', label: 'Kontrola světel', kind: 'check' },
    { id: 'bulb', label: 'Výměna žárovky / LED', kind: 'replace' },
    { id: 'fuses', label: 'Kontrola pojistek', kind: 'check' },
    { id: 'starter', label: 'Problém se startérem', kind: 'repair' },
    { id: 'wiring', label: 'Oprava elektroinstalace / konektorů', kind: 'repair' },
    { id: 'horn', label: 'Kontrola klaksonu', kind: 'check' },
    { id: 'diagnostics', label: 'Diagnostika řídicí jednotky (čtení chyb)', kind: 'check' },
    { id: 'software_update', label: 'Aktualizace softwaru řídicí jednotky', kind: 'other' },
  ] },
  { key: 'body', label: 'Karoserie & ovládání', items: [
    { id: 'windscreen', label: 'Výměna plexi / větrného štítu', kind: 'replace' },
    { id: 'plastics', label: 'Oprava / výměna plastů a kapotáže', kind: 'repair' },
    { id: 'mirrors', label: 'Výměna / seřízení zrcátek', kind: 'repair' },
    { id: 'levers', label: 'Výměna páček (brzda / spojka)', kind: 'replace' },
    { id: 'handlebar', label: 'Výměna / seřízení řídítek', kind: 'repair' },
    { id: 'grips', label: 'Výměna gripů / rukojetí', kind: 'replace' },
    { id: 'footpegs', label: 'Výměna stupaček / řadicí páky', kind: 'replace' },
    { id: 'seat', label: 'Oprava / výměna sedla', kind: 'repair' },
    { id: 'luggage', label: 'Oprava / montáž kufrů a nosičů', kind: 'repair' },
    { id: 'cables_lube', label: 'Mazání lanek a čepů', kind: 'adjust', months: 6 },
    { id: 'key_lock', label: 'Zámky / klíče / imobilizér', kind: 'repair' },
    { id: 'cosmetic', label: 'Kosmetická oprava (lak, plasty)', kind: 'repair' },
    { id: 'accident_repair', label: 'Oprava po nehodě', kind: 'repair' },
  ] },
  { key: 'other', label: 'Kontroly & ostatní', items: [
    { id: 'full_service', label: 'Kompletní servis / velká prohlídka', kind: 'check', km: 20000, months: 24, track: true, moto: 'full', implies: ['oil_change', 'oil_filter', 'general_inspection', 'brake_pads_check', 'clutch', 'suspension_check', 'battery', 'chain_adjust', 'coolant_check', 'tire_check', 'tire_pressure', 'lights'] },
    { id: 'general_inspection', label: 'Celková kontrola stroje (před / po sezóně)', kind: 'check', months: 6, track: true, implies: ['brake_pads_check', 'tire_check', 'tire_pressure', 'lights', 'battery', 'suspension_check', 'chain_adjust'] },
    { id: 'stk', label: 'Příprava na STK', kind: 'other', implies: ['lights', 'tire_check', 'brake_pads_check'] },
    { id: 'winter_storage', label: 'Zazimování / odzimování', kind: 'other' },
    { id: 'test_ride', label: 'Zkušební jízda', kind: 'check' },
    { id: 'wash', label: 'Mytí a konzervace', kind: 'other' },
    { id: 'recall', label: 'Svolávací akce výrobce', kind: 'other' },
    { id: 'other_repair', label: 'Jiná oprava', kind: 'repair' },
  ] },
]

/** Všechny položky v jednom poli (s klíčem skupiny). */
export const SERVICE_TASKS = SERVICE_GROUPS.flatMap(g => g.items.map(i => ({ ...i, group: g.key, groupLabel: g.label })))
export const TASK_BY_ID = Object.fromEntries(SERVICE_TASKS.map(t => [t.id, t]))
/** štítek (i historický alias) → id */
export const TASK_ID_BY_LABEL = (() => {
  const m = {}
  for (const t of SERVICE_TASKS) { m[t.label] = t.id; for (const a of t.aliases || []) m[a] = t.id }
  return m
})()
export const taskIdForLabel = (label) => TASK_ID_BY_LABEL[(label || '').trim()] || null
export const taskLabel = (id) => TASK_BY_ID[id]?.label || id

/** Platí položka pro motorku? (pohon / chlazení / hodiny) */
export function taskAppliesTo(task, moto) {
  if (!task?.only) return true
  const dt = moto?.drivetrain || null
  if (task.only === 'chain' || task.only === 'shaft' || task.only === 'belt') return dt ? dt === task.only : task.only === 'chain'
  if (task.only === 'liquid') return !/vzduch|air/i.test(moto?.engine_type || '') // bez údaje = kapalina
  if (task.only === 'hydraulic') return false
  if (task.only === 'hours') return moto?.tracking_unit === 'mh'
  return true
}
