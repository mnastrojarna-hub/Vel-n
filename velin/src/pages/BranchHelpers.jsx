import { supabase } from '../lib/supabase'
import Card from '../components/ui/Card'

export const FALLBACK_ACCESSORY_TYPES = [
  { key: 'boots', label: 'Boty', sizes: ['36','37','38','39','40','41','42','43','44','45','46'], is_consumable: false },
  { key: 'helmet', label: 'Helmy', sizes: ['XS','S','M','L','XL','XXL'], is_consumable: false },
  { key: 'balaclava', label: 'Kukly', sizes: ['UNI'], is_consumable: true },
  { key: 'gloves', label: 'Rukavice', sizes: ['XS','S','M','L','XL','XXL'], is_consumable: false },
  { key: 'pants', label: 'Kalhoty', sizes: ['XS','S','M','L','XL','XXL'], is_consumable: false },
]

export async function loadAccessoryTypes() {
  const { data, error } = await supabase
    .from('accessory_types')
    .select('*')
    .eq('is_active', true)
    .order('sort_order')
  if (error || !data || data.length === 0) return FALLBACK_ACCESSORY_TYPES
  return data.map(t => ({
    key: t.key, label: t.label, sizes: t.sizes || [], is_consumable: !!t.is_consumable, id: t.id,
    price_czk: typeof t.price_czk === 'number' ? t.price_czk : 0,
    pricing_unit: t.pricing_unit || 'per_booking',
    audience: t.audience || 'adult',
  }))
}

export const MAX_MOTOS = 24

// Samoobslužná pobočka má VŽDY pevnou sestavu zón: 7 kójí na motorky
// + 1 šatna (dveře door_kind='accessories') + 1 venek (zóna bez dveří).
// Shodné s HW šablonou v BranchRpiHardwareDefaults.js a raspberry/motogo-box
// (config/brno-9zone.yaml: 8 zón = 7 kójí + šatna, zóna 9 = venek).
export const SELF_SERVICE_TYPE = 'samoobslužná'
export const SELF_SERVICE_MOTO_BAYS = 7
export const SELF_SERVICE_LAYOUT_NOTE = '7 kójí motorek + šatna + venek'

export function isSelfService(branch) {
  return (branch?.type || '') === SELF_SERVICE_TYPE
}

// Vozík vydává jen OBSLUŽNÁ pobočka (SQL `branch_is_self_service`, migrace
// 20260921b/c/d/e). Přesun motorky NA samoobslužnou pobočku proto rozbije
// každou její živou rezervaci, která veze vozík — web ani appka by takovou
// kombinaci zákazníkovi vůbec nenabídly. Velín obsluhu neblokuje (může mít
// důvod), ale MUSÍ se zeptat. Vrací počet dotčených rezervací.
export async function countTrailerBookings(supabase, motoIds) {
  const ids = (motoIds || []).filter(Boolean)
  if (!ids.length) return 0
  const today = new Date().toLocaleDateString('sv-SE')
  const { data, error } = await supabase
    .from('bookings')
    .select('id')
    .in('moto_id', ids)
    .not('trailer_moto_id', 'is', null)
    .in('status', ['pending', 'reserved', 'active'])
    // Dávno skončené rezervace, které nikdo nepřeklopil do 'completed', nejsou
    // „živé" — bez tohohle by varování strašilo i tam, kde není co řešit.
    .gte('end_date', today)
  // Chyba dotazu (RLS, síť, token) NESMÍ varování tiše vypnout — vrátíme -1
  // a volající se zeptá tak jako tak. Fail closed.
  if (error) return -1
  return (data || []).length
}

// Společné potvrzení pro všechna tři místa, odkud jde motorku přesunout
// (MotoActionModal, FleetBulkActionsModal, FleetDetailInfoTab).
// Vrací true = pokračovat.
// `target` může být objekt pobočky NEBO jen její id. Když objekt nenese `type`
// (většina selectů v repu tahá jen `branches(name)` / `branches(id, name)`),
// dohledáme ho — jinak by `isSelfService({name})` bylo tiše false a kontrola
// by se u těch volajících NIKDY nespustila (přesně to se stalo u „náhradní
// motorky" otevřené z výpisu flotily).
async function resolveBranch(supabase, target) {
  if (!target) return null
  const obj = typeof target === 'string' ? { id: target } : target
  if (typeof obj.type === 'string') return obj
  if (!obj.id) return obj
  const { data } = await supabase.from('branches').select('id, name, type').eq('id', obj.id).maybeSingle()
  return data ? { ...obj, ...data } : obj
}

export async function confirmTrailerBranchMove(supabase, target, motoIds) {
  const targetBranch = await resolveBranch(supabase, target)
  if (!isSelfService(targetBranch)) return true
  const n = await countTrailerBookings(supabase, motoIds)
  if (n === 0) return true
  if (n < 0) {
    return window.confirm(
      'Nepodařilo se ověřit, jestli některá živá rezervace veze vozík ' +
      `(chyba dotazu). Přesouváš motorku na SAMOOBSLUŽNOU pobočku „${targetBranch?.name || ''}“, ` +
      'která vozík nevydává.\n\nPřesun přesto provést?'
    )
  }
  return window.confirm(
    `Pozor: ${n === 1 ? '1 živá rezervace veze' : n + ' živých rezervací veze'} vozík ` +
    `a přesouváš motorku na SAMOOBSLUŽNOU pobočku „${targetBranch?.name || ''}“, ` +
    'která vozík nevydává (7 kójí + šatna, výdej 24/7 kódem bez obsluhy).\n\n' +
    'Přesun provést? Vozík u těch rezervací zůstane a bude ho potřeba vyřešit ručně.'
  )
}

// Kolik motorek se na pobočku vejde = kolik má kójí.
export function maxMotosForBranch(branch) {
  return isSelfService(branch) ? SELF_SERVICE_MOTO_BAYS : MAX_MOTOS
}

export const DETAIL_TABS = ['Info', 'Motorky & Koje', 'Příslušenství', 'Přístupové kódy', 'Samoobsluha', 'Zavírací období']

export function generateDoorCode() {
  return String(Math.floor(100000 + Math.random() * 900000))
}

export function generateBranchCode() {
  return String(Math.floor(100000 + Math.random() * 900000)).padStart(6, '0')
}

// Inventory helpers for branch accessories
export function accSku(type, size) { return `prislusenstvi-${type}-${size}` }

export async function fetchInventoryMap() {
  const { data } = await supabase
    .from('inventory')
    .select('id, sku, stock, name')
    .eq('category', 'prislusenstvi')
  const map = {}
  ;(data || []).forEach(i => { map[i.sku] = i })
  return map
}

export async function deductFromWarehouse(sku, qty, branchName) {
  const { data: inv } = await supabase
    .from('inventory').select('id, stock').eq('sku', sku).single()
  if (!inv || inv.stock < qty) return false
  await supabase.rpc('log_stock_movement', { p_item: inv.id, p_type: 'issue', p_qty: qty, p_note: `Výdej na pobočku ${branchName}` })
  await supabase.from('inventory').update({ stock: inv.stock - qty }).eq('id', inv.id)
  return true
}

export async function returnToWarehouse(sku, qty, branchName) {
  const { data: inv } = await supabase
    .from('inventory').select('id, stock').eq('sku', sku).single()
  if (!inv || qty <= 0) return
  await supabase.rpc('log_stock_movement', { p_item: inv.id, p_type: 'receipt', p_qty: qty, p_note: `Vráceno z pobočky ${branchName}` })
  await supabase.from('inventory').update({ stock: inv.stock + qty }).eq('id', inv.id)
}

// ─── Shared Components ────────────────────────────────────────────
function DRow({ label, value, mono }) {
  return (
    <div>
      <div className="text-sm font-extrabold uppercase tracking-wide mb-0.5" style={{ color: '#1a2e22' }}>{label}</div>
      <div className={`text-sm font-semibold ${mono ? 'font-mono' : ''}`} style={{ color: '#0f1a14' }}>{value || '—'}</div>
    </div>
  )
}

function FormField({ label, value, onChange, type = 'text', placeholder }) {
  return (
    <div>
      <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{label}</label>
      <input type={type} value={value} onChange={e => onChange(e.target.value)}
        placeholder={placeholder}
        className="w-full rounded-btn text-sm outline-none"
        style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }} />
    </div>
  )
}

function StatCard({ label, value, color }) {
  return (
    <Card>
      <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>{label}</div>
      <div className="text-xl font-extrabold" style={{ color }}>{value}</div>
    </Card>
  )
}

function SmallBtn({ children, color, onClick, disabled }) {
  return (
    <button onClick={disabled ? undefined : onClick} disabled={!!disabled}
      className="text-sm font-bold"
      style={{
        color, background: 'none', border: 'none', padding: '4px 6px',
        cursor: disabled ? 'not-allowed' : 'pointer',
        opacity: disabled ? 0.45 : 1,
      }}>
      {children}
    </button>
  )
}

function Spinner() {
  return (
    <div className="flex justify-center py-8">
      <div className="animate-spin rounded-full h-6 w-6 border-t-2 border-brand-gd" />
    </div>
  )
}

function EmptyState({ text }) {
  return (
    <div className="text-sm py-3 text-center" style={{ color: '#1a2e22', opacity: 0.5 }}>{text}</div>
  )
}

export { DRow, FormField, StatCard, SmallBtn, Spinner, EmptyState }
