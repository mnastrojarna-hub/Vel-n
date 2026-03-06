import { useState, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import Card from '../components/ui/Card'
import Button from '../components/ui/Button'
import ConfirmDialog from '../components/ui/ConfirmDialog'
import Modal from '../components/ui/Modal'

export default function InventoryDetail() {
  const { id } = useParams()
  const navigate = useNavigate()
  const [item, setItem] = useState(null)
  const [movements, setMovements] = useState([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState(null)
  const [tab, setTab] = useState('Info')
  const [confirm, setConfirm] = useState(null)
  const [moveModal, setMoveModal] = useState(null)

  useEffect(() => { loadItem(); loadMovements() }, [id])

  async function loadItem() {
    setLoading(true)
    try {
      const { data, error: err } = await supabase
        .from('inventory')
        .select('*, suppliers(name)')
        .eq('id', id)
        .single()
      if (err) setError(err.message)
      else setItem(data)
    } catch (e) {
      setError(e.message)
    }
    setLoading(false)
  }

  async function loadMovements() {
    try {
      const { data } = await supabase
        .from('inventory_movements')
        .select('*')
        .eq('item_id', id)
        .order('created_at', { ascending: false })
      if (data) setMovements(data)
    } catch {
      setMovements([])
    }
  }

  async function handleSave() {
    setSaving(true); setError(null)
    const { name, sku, category, min_stock, unit_price } = item
    await debugAction('handleSave', 'InventoryDetail', async () => {
      const { error: err } = await supabase.from('inventory').update({ name, sku, category, min_stock, unit_price }).eq('id', id)
      if (err) setError(err.message)
      else await logAudit('inventory_updated', { item_id: id })
    }, { name, sku, category, min_stock, unit_price })
    setSaving(false)
  }

  async function handleDelete() {
    await debugAction('handleDelete', 'InventoryDetail', async () => {
      await supabase.from('inventory').delete().eq('id', id)
      await logAudit('inventory_deleted', { item_id: id })
      navigate('/sklady')
    }, { item_id: id })
  }

  async function handleMovement(type, quantity, note) {
    await debugAction('handleMovement', 'InventoryDetail', async () => {
      const mult = type === 'receipt' ? 1 : type === 'issue' ? -1 : 0
      const { data: { user } } = await supabase.auth.getUser()

      await supabase.from('inventory_movements').insert({
        item_id: id, type, quantity, note, performed_by: user?.id,
      })

      if (type === 'correction') {
        await supabase.from('inventory').update({ stock: quantity }).eq('id', id)
        setItem(i => ({ ...i, stock: quantity }))
      } else {
        const newStock = (item.stock || 0) + (mult * quantity)
        await supabase.from('inventory').update({ stock: newStock }).eq('id', id)
        setItem(i => ({ ...i, stock: newStock }))
      }

      await logAudit(`inventory_${type}`, { item_id: id, quantity })
      setMoveModal(null)
      loadMovements()
    }, { type, quantity, note })
  }

  async function logAudit(action, details) {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, details })
    } catch {}
  }

  const set = (k, v) => setItem(i => ({ ...i, [k]: v }))
  const fmt = (n) => (n || 0).toLocaleString('cs-CZ') + ' Kč'

  if (loading) return <div className="flex justify-center py-16"><div className="animate-spin rounded-full h-8 w-8 border-t-2 border-brand-gd" /></div>
  if (error && !item) return <div className="p-4 rounded-card" style={{ background: '#fee2e2', color: '#dc2626' }}>{error}</div>
  if (!item) return <div className="p-4" style={{ color: '#8aab99' }}>Položka nenalezena</div>

  const isLow = item.stock <= item.min_stock

  return (
    <div>
      <div className="flex items-center gap-3 mb-5">
        <button onClick={() => navigate('/sklady')} className="cursor-pointer" style={{ background: 'none', border: 'none', fontSize: 18, color: '#8aab99' }}>←</button>
        <h2 className="font-extrabold text-lg" style={{ color: '#0f1a14' }}>{item.name}</h2>
        <span className="text-xs font-mono" style={{ color: '#8aab99' }}>{item.sku}</span>
        <span className="inline-block rounded-btn text-[10px] font-extrabold tracking-wide uppercase"
          style={{ padding: '4px 10px', background: isLow ? '#fee2e2' : '#dcfce7', color: isLow ? '#dc2626' : '#1a8a18' }}>
          Sklad: {item.stock ?? 0}
        </span>
      </div>

      <div className="flex gap-2 mb-5">
        {['Info', 'Pohyby'].map(t => (
          <button key={t} onClick={() => setTab(t)} className="rounded-btn text-xs font-extrabold uppercase tracking-wide cursor-pointer"
            style={{ padding: '8px 18px', background: tab === t ? '#74FB71' : '#f1faf7', color: tab === t ? '#1a2e22' : '#4a6357', border: 'none', boxShadow: tab === t ? '0 4px 16px rgba(116,251,113,.35)' : 'none' }}>
            {t}
          </button>
        ))}
      </div>

      {tab === 'Info' && (
        <Card>
          <div className="grid grid-cols-2 gap-4">
            <Field label="Název" value={item.name} onChange={v => set('name', v)} />
            <Field label="SKU" value={item.sku} onChange={v => set('sku', v)} />
            <Field label="Kategorie" value={item.category} onChange={v => set('category', v)} />
            <Field label="Cena/ks (Kč)" value={item.unit_price} onChange={v => set('unit_price', v)} type="number" />
            <Field label="Minimum" value={item.min_stock} onChange={v => set('min_stock', v)} type="number" />
            <Field label="Dodavatel" value={item.suppliers?.name || '—'} disabled />
            <Field label="Aktuální stav" value={item.stock} disabled />
          </div>
          {error && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{error}</p>}
          <div className="flex gap-3 mt-6">
            <Button green onClick={handleSave} disabled={saving}>{saving ? 'Ukládám…' : 'Uložit'}</Button>
            <Button onClick={() => setMoveModal('receipt')} style={{ background: '#dcfce7', color: '#1a8a18' }}>+ Příjem</Button>
            <Button onClick={() => setMoveModal('issue')} style={{ background: '#fee2e2', color: '#dc2626' }}>− Výdej</Button>
            <Button onClick={() => setMoveModal('correction')}>Korekce</Button>
            <Button onClick={() => setConfirm('delete')} style={{ color: '#dc2626' }}>Smazat</Button>
          </div>
        </Card>
      )}

      {tab === 'Pohyby' && (
        <Card>
          {movements.length === 0 ? <p style={{ color: '#8aab99', fontSize: 13 }}>Žádné pohyby</p> : (
            <div className="space-y-3">
              {movements.map(m => (
                <div key={m.id} className="flex items-center gap-4 p-3 rounded-lg" style={{ background: '#f1faf7' }}>
                  <MovementBadge type={m.type} />
                  <div className="flex-1">
                    <span className="text-sm font-bold">{m.note || '—'}</span>
                    <span className="text-xs ml-3" style={{ color: '#8aab99' }}>
                      {m.created_at ? new Date(m.created_at).toLocaleDateString('cs-CZ') : '—'}
                    </span>
                  </div>
                  <span className="text-sm font-bold" style={{ color: m.type === 'receipt' ? '#1a8a18' : m.type === 'issue' ? '#dc2626' : '#4a6357' }}>
                    {m.type === 'receipt' ? '+' : m.type === 'issue' ? '−' : '='}{m.quantity}
                  </span>
                </div>
              ))}
            </div>
          )}
        </Card>
      )}

      {moveModal && <MovementModal type={moveModal} currentStock={item.stock} onSave={handleMovement} onClose={() => setMoveModal(null)} />}

      <ConfirmDialog open={confirm === 'delete'} title="Smazat položku?" message="Tato akce je nevratná." danger onConfirm={handleDelete} onCancel={() => setConfirm(null)} />
    </div>
  )
}

function Field({ label, value, onChange, type = 'text', disabled = false }) {
  return (
    <div>
      <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>{label}</label>
      <input type={type} value={value || ''} onChange={e => onChange?.(e.target.value)} disabled={disabled} className="w-full rounded-btn text-sm outline-none disabled:opacity-50" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }} />
    </div>
  )
}

function MovementBadge({ type }) {
  const map = {
    receipt: { label: 'Příjem', bg: '#dcfce7', color: '#1a8a18' },
    issue: { label: 'Výdej', bg: '#fee2e2', color: '#dc2626' },
    correction: { label: 'Korekce', bg: '#f3f4f6', color: '#6b7280' },
  }
  const s = map[type] || map.correction
  return (
    <span className="inline-block rounded-btn text-[10px] font-extrabold tracking-wide uppercase"
      style={{ padding: '4px 10px', background: s.bg, color: s.color }}>
      {s.label}
    </span>
  )
}

function MovementModal({ type, currentStock, onSave, onClose }) {
  const [quantity, setQuantity] = useState('')
  const [note, setNote] = useState('')
  const [saving, setSaving] = useState(false)

  const labels = { receipt: 'Příjem na sklad', issue: 'Výdej ze skladu', correction: 'Korekce stavu' }

  async function handleSubmit() {
    setSaving(true)
    await onSave(type, Number(quantity) || 0, note)
    setSaving(false)
  }

  return (
    <Modal open title={labels[type]} onClose={onClose}>
      <div className="space-y-3">
        {type === 'correction' && (
          <p className="text-xs" style={{ color: '#8aab99' }}>Aktuální stav: {currentStock}. Zadejte nový stav.</p>
        )}
        <div>
          <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>
            {type === 'correction' ? 'Nový stav' : 'Množství'}
          </label>
          <input type="number" value={quantity} onChange={e => setQuantity(e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        </div>
        <div>
          <label className="block text-[10px] font-extrabold uppercase tracking-wide mb-1" style={{ color: '#8aab99' }}>Poznámka</label>
          <input type="text" value={note} onChange={e => setNote(e.target.value)}
            className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }} />
        </div>
      </div>
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSubmit} disabled={saving || !quantity}>{saving ? 'Ukládám…' : 'Potvrdit'}</Button>
      </div>
    </Modal>
  )
}
