import { useState } from 'react'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import Modal from '../components/ui/Modal'
import Button from '../components/ui/Button'

const CATEGORIES = [
  { value: 'rental', label: 'Pronájem' },
  { value: 'gear', label: 'Vybavení' },
  { value: 'experience', label: 'Zážitek' },
  { value: 'gift', label: 'Dárek' },
]

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}

function generateCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
  let code = 'MG'
  for (let i = 0; i < 6; i++) code += chars[Math.floor(Math.random() * chars.length)]
  return code
}

export function VoucherModal({ open, existing, onClose, onSaved }) {
  const isEdit = !!existing
  const [form, setForm] = useState(
    existing
      ? { code: existing.code || '', amount: existing.amount?.toString() || '', currency: existing.currency || 'CZK', category: existing.category || 'gift', buyer_name: existing.buyer_name || '', buyer_email: existing.buyer_email || '', valid_from: existing.valid_from || '', valid_until: existing.valid_until || '', description: existing.description || '' }
      : { code: generateCode(), amount: '', currency: 'CZK', category: 'gift', buyer_name: '', buyer_email: '', valid_from: new Date().toISOString().split('T')[0], valid_until: new Date(Date.now() + 365 * 86400000).toISOString().split('T')[0], description: '' }
  )
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      const payload = { code: form.code.trim().toUpperCase(), amount: Number(form.amount) || 0, currency: form.currency, category: form.category || null, buyer_name: form.buyer_name || null, buyer_email: form.buyer_email || null, valid_from: form.valid_from || null, valid_until: form.valid_until || null, description: form.description || null }
      if (isEdit) {
        const { error } = await debugAction('updateVoucher', 'VoucherModal', () => supabase.from('vouchers').update(payload).eq('id', existing.id), { voucherId: existing.id, payload })
        if (error) throw error
        await logAudit('voucher_updated', { code: payload.code })
      } else {
        const { error } = await debugAction('createVoucher', 'VoucherModal', () => supabase.from('vouchers').insert({ ...payload, status: 'active', created_by: user?.id }), { payload })
        if (error) throw error
        await logAudit('voucher_created', { code: payload.code, amount: payload.amount })
      }
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  async function logAudit(action, details) {
    try { const { data: { user } } = await supabase.auth.getUser(); await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, details }) } catch {}
  }

  if (!open) return null

  return (
    <Modal open noBackdropClose title={isEdit ? `Upravit: ${existing?.code}` : 'Nový dárkový poukaz'} onClose={onClose}>
      <div className="grid grid-cols-2 gap-3">
        <div className="col-span-2">
          <Label>Kód poukazu</Label>
          <div className="flex gap-2">
            <input value={form.code} onChange={e => set('code', e.target.value.toUpperCase())} className="flex-1 rounded-btn text-sm outline-none font-mono" style={inputStyle} placeholder="MGXXXXXX" disabled={isEdit} />
            {!isEdit && <button onClick={() => set('code', generateCode())} className="rounded-btn text-sm font-bold cursor-pointer" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>Generovat</button>}
          </div>
          {isEdit && <span className="text-sm" style={{ color: '#1a2e22' }}>Kód nelze měnit po vytvoření</span>}
        </div>
        <div><Label>Hodnota</Label><input type="number" value={form.amount} onChange={e => set('amount', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} placeholder="2000" /></div>
        <div><Label>Měna</Label><select value={form.currency} onChange={e => set('currency', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}><option value="CZK">CZK</option><option value="EUR">EUR</option></select></div>
        <div><Label>Kategorie</Label><select value={form.category} onChange={e => set('category', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>{CATEGORIES.map(c => <option key={c.value} value={c.value}>{c.label}</option>)}</select></div>
        <div><Label>Jméno kupujícího</Label><input value={form.buyer_name} onChange={e => set('buyer_name', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} placeholder="Jan Novák" /></div>
        <div className="col-span-2"><Label>Email kupujícího</Label><input type="email" value={form.buyer_email} onChange={e => set('buyer_email', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} placeholder="jan@email.cz" /></div>
        <div><Label>Platnost od</Label><input type="date" value={form.valid_from} onChange={e => set('valid_from', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div><Label>Platnost do</Label><input type="date" value={form.valid_until} onChange={e => set('valid_until', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} /></div>
        <div className="col-span-2"><Label>Popis / poznámka</Label><textarea value={form.description} onChange={e => set('description', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ ...inputStyle, minHeight: 60, resize: 'vertical' }} placeholder="Dárkový poukaz k narozeninám…" /></div>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.code || !form.amount}>{saving ? 'Ukládám…' : isEdit ? 'Uložit změny' : 'Vytvořit poukaz'}</Button>
      </div>
    </Modal>
  )
}

export function RedeemModal({ voucher, onClose, onRedeem }) {
  const [form, setForm] = useState({ redeemed_for: '', booking_id: '' })
  const [saving, setSaving] = useState(false)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  return (
    <Modal open title={`Uplatnit poukaz: ${voucher.code}`} onClose={onClose}>
      <div className="mb-4 p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
        <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Hodnota: {Number(voucher.amount).toLocaleString('cs-CZ')} {voucher.currency}</span>
      </div>
      <div className="grid gap-3">
        <div><Label>Na co uplatněn</Label><input value={form.redeemed_for} onChange={e => set('redeemed_for', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} placeholder="Pronájem Honda CB500F, 3 dny…" /></div>
        <div><Label>ID rezervace (volitelné)</Label><input value={form.booking_id} onChange={e => set('booking_id', e.target.value)} className="w-full rounded-btn text-sm outline-none font-mono" style={inputStyle} placeholder="uuid…" /></div>
      </div>
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={() => { setSaving(true); onRedeem(form) }} disabled={saving}>{saving ? 'Uplatňuji…' : 'Potvrdit uplatnění'}</Button>
      </div>
    </Modal>
  )
}
