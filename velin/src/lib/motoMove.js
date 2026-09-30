// Přesun motorky mezi pobočkami (Velín) — VÝHRADNĚ přes RPC admin_move_motorcycle / admin_move_motorcycles (2026-09-29).
// Pravidlo majitele: přesun mezi OBSLUŽNOU a SAMOOBSLUŽNOU pobočkou (i „bez pobočky“ → samoobslužná) jen
// s aktuálním stavem tachometru — ze samoobslužné pobočky se stav předvyplní dalšímu zákazníkovi do protokolu
// a je spodní mezí pro stav zadaný na kiosku při vrácení. Bez stavu přesun neproběhne (DB strážce 20260929h).
// Kódy chyb RPC: supabase/migrations/20260929g_moto_move_odometer.sql. Odebrání pobočky (→ NULL) jde dál přímo.
import { supabase } from './supabase'
import { SELF_SERVICE_TYPE } from '../pages/BranchHelpers'
import { fetchActiveBookings } from '../components/fleet/bookingGuard'

export const isSelfType = t => t === SELF_SERVICE_TYPE
export const unitLabel = u => (u === 'mh' ? 'MH' : 'km')
export const fmtKm = (n, u) => `${Number(n).toLocaleString('cs-CZ')} ${unitLabel(u)}`
const fmtD = d => (d ? new Date(d).toLocaleDateString('cs-CZ') : '—')

// Typy poboček (id → type) čerstvě z DB — objekty motorek ve Velíně typ pobočky často nenesou.
// NULL pobočka i NULL typ = obslužná (1:1 s SQL branch_is_self_service).
async function loadBranchTypes(ids) {
  const list = [...new Set(ids.filter(Boolean))]
  if (!list.length) return {}
  const { data, error } = await supabase.from('branches').select('id, type').in('id', list)
  if (error) throw new Error('Nepodařilo se ověřit typ pobočky: ' + error.message)
  return Object.fromEntries((data || []).map(b => [b.id, b.type]))
}

// Čerstvý stav motorek z DB (pobočka, nájezd, jednotka) — objekt ze seznamu / formuláře detailu může být
// zastaralý (kiosk mezitím zapsal stav při vrácení) nebo rozeditovaný (neuložený „Nájezd“). Nápověda v okně
// = poslední známý stav v DB. Chyba dotazu → předané objekty (rozhoduje stejně DB v RPC).
async function freshMotos(motos) {
  const { data, error } = await supabase.from('motorcycles')
    .select('id, model, spz, branch_id, mileage, tracking_unit').in('id', motos.map(m => m.id))
  if (error || !data) return motos
  const byId = Object.fromEntries(data.map(r => [r.id, r]))
  return motos.map(m => ({ ...m, ...(byId[m.id] || {}) }))
}

// Srozumitelná hláška k výsledku RPC ({ error, last, unit, purchase_km, model, spz }).
export function moveErrorText(res) {
  const who = res?.model ? ` (${res.model}${res.spz ? ' ' + res.spz : ''})` : ''
  switch (res?.error) {
    case 'forbidden': return 'Přesun motorky smí provést jen administrátor.'
    case 'missing_inputs': return 'Chybí motorka nebo cílová pobočka.'
    case 'branch_not_found': return 'Cílová pobočka neexistuje.'
    case 'moto_not_found': return 'Motorka nenalezena.'
    case 'km_required':
    case 'moto_move_requires_odometer':
      return `Přesun mezi obslužnou a samoobslužnou pobočkou vyžaduje aktuální stav tachometru${who}.`
    case 'invalid_km': return 'Neplatný stav tachometru — zadejte celé číslo 0–9 999 999.'
    case 'km_below_purchase':
      return `Stav je nižší než stav při koupi motorky (${fmtKm(res.purchase_km || 0, res.unit)}) — takovou hodnotu nelze zadat.`
    case 'km_below_last': return `Zadaný stav je NIŽŠÍ než poslední evidovaný (${fmtKm(res.last || 0, res.unit)}).`
    case 'km_jump':
      return `Zadaný stav je o víc než ${res.unit === 'mh' ? '500 MH' : '20 000 km'} vyšší než poslední evidovaný (${fmtKm(res.last || 0, res.unit)}) — není to překlep?`
    case 'rpc_missing': return 'Databáze zatím nezná přesun se stavem tachometru (migrace 20260929g) — přesun zkuste po nasazení.'
    default: return res?.error || 'Přesun motorky se nezdařil.'
  }
}

// Jedno volání RPC: 1 motorka = admin_move_motorcycle, víc = admin_move_motorcycles (vše, nebo nic).
// readings = { [moto_id]: { km, force } }. Vrací { ok: true, data } nebo { ok: false, error, moto_id, last, unit, … }.
export async function callMove({ motoIds, branchId, readings = {}, note = null }) {
  const rd = id => readings[id] || {}
  const { data, error } = motoIds.length === 1
    ? await supabase.rpc('admin_move_motorcycle', {
        p_moto_id: motoIds[0], p_branch_id: branchId, p_km: rd(motoIds[0]).km ?? null, p_force: !!rd(motoIds[0]).force, p_note: note,
      })
    : await supabase.rpc('admin_move_motorcycles', {
        p_branch_id: branchId, p_note: note,
        p_items: motoIds.map(id => ({ moto_id: id, km: rd(id).km ?? null, force: !!rd(id).force })),
      })
  if (error) return { ok: false, error: error.code === 'PGRST202' ? 'rpc_missing' : (error.message || 'rpc_error') }
  if (data?.ok) return { ok: true, data }
  const fail = data?.failed || data || {}
  return { ...fail, moto_id: fail.moto_id || (motoIds.length === 1 ? motoIds[0] : null), ok: false }
}

// Motorku na probíhajícím pronájmu nelze přesunout mezi režimy — stav tachometru teď nikdo neodečte.
async function assertNotOnRental(motos) {
  const active = await fetchActiveBookings(motos.map(m => m.id))
  if (!active.length) return
  const byId = Object.fromEntries(motos.map(m => [m.id, m]))
  const lines = active.map(b => `• ${byId[b.moto_id]?.model || ''} ${byId[b.moto_id]?.spz || ''} — ${b.profiles?.full_name || '?'}, ${fmtD(b.start_date)} – ${fmtD(b.end_date)}`)
  throw new Error('Přesun nelze provést — motorka je u zákazníka (probíhající pronájem), stav tachometru teď nelze odečíst. ' +
    'Přesun mezi obslužnou a samoobslužnou pobočkou proveďte až po vrácení.\n\n' + lines.join('\n'))
}

/**
 * Přesune motorky na pobočku. Mezi obslužnou ↔ samoobslužnou se zeptá na stav tachometru
 * (askOdometer z useOdometerPrompt — okno samo volá RPC a řeší „Opravdu?“ / chyby).
 * @param motos [{ id, … }] — pobočku, nájezd a jednotku si funkce načte čerstvě z DB
 * @returns výsledek RPC; null = zrušeno v okně stavu tachometru (nic se nepřesunulo); chyba = throw
 */
export async function moveMotos({ motos: given, branchId, branchName = '', askOdometer, note = null }) {
  const motos = await freshMotos(given)
  const types = await loadBranchTypes([branchId, ...motos.map(m => m.branch_id)])
  const toSelf = isSelfType(types[branchId])
  let needing = motos.filter(m => m.branch_id !== branchId && isSelfType(types[m.branch_id]) !== toSelf)
  const submit = readings => callMove({ motoIds: motos.map(m => m.id), branchId, readings, note })
  if (!needing.length) {
    const res = await submit({})
    if (res.ok) return res.data
    // DB vidí přesun mezi režimy, Velín ne (typ pobočky se mezitím změnil) → zeptat se na stav té motorky
    needing = res.error === 'km_required' ? motos.filter(m => m.id === res.moto_id) : []
    if (!needing.length) throw new Error(moveErrorText(res))
  }
  await assertNotOnRental(needing)
  return askOdometer({ motos: needing, branchName, submit })
}
