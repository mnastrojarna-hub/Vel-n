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
  return data.map(t => ({ key: t.key, label: t.label, sizes: t.sizes || [], is_consumable: !!t.is_consumable, id: t.id }))
}

export const MAX_MOTOS = 24
export const DETAIL_TABS = ['Info', 'Motorky & Koje', 'Příslušenství', 'Přístupové kódy']

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

async function deductFromWarehouse(sku, qty, branchName) {
  const { data: inv } = await supabase
    .from('inventory').select('id, stock').eq('sku', sku).single()
  if (!inv || inv.stock < qty) return false
  const { data: { user } } = await supabase.auth.getUser()
  await supabase.from('inventory_movements').insert({
    item_id: inv.id, type: 'issue', quantity: qty,
    note: `Výdej na pobočku ${branchName}`, performed_by: user?.id,
  })
  await supabase.from('inventory').update({ stock: inv.stock - qty }).eq('id', inv.id)
  return true
}

async function returnToWarehouse(sku, qty, branchName) {
  const { data: inv } = await supabase
    .from('inventory').select('id, stock').eq('sku', sku).single()
  if (!inv || qty <= 0) return
  const { data: { user } } = await supabase.auth.getUser()
  await supabase.from('inventory_movements').insert({
    item_id: inv.id, type: 'receipt', quantity: qty,
    note: `Vráceno z pobočky ${branchName}`, performed_by: user?.id,
  })
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

function SmallBtn({ children, color, onClick }) {
  return (
    <button onClick={onClick} className="text-sm font-bold cursor-pointer"
      style={{ color, background: 'none', border: 'none', padding: '4px 6px' }}>
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
