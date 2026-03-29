import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import Button from '../components/ui/Button'
import Badge from '../components/ui/Badge'
import Modal from '../components/ui/Modal'

const inputStyle = { padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0' }
function Label({ children }) {
  return <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{children}</label>
}

export function PromoModal({ existing, onClose, onSaved }) {
  const isEdit = !!existing
  const [form, setForm] = useState(
    existing
      ? {
          code: existing.code || '',
          discount_type: existing.type || 'percent',
          discount_value: existing.value?.toString() || '',
          valid_from: existing.valid_from || '',
          valid_to: existing.valid_to || '',
          usage_limit: existing.max_uses?.toString() || '',
          status: existing.active ? 'active' : 'inactive',
        }
      : { code: '', discount_type: 'percent', discount_value: '', valid_from: '', valid_to: '', usage_limit: '', status: 'active' }
  )
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    setSaving(true); setErr(null)
    try {
      const payload = {
        code: form.code.trim().toUpperCase(),
        type: form.discount_type,
        value: Number(form.discount_value) || 0,
        max_uses: form.usage_limit ? Number(form.usage_limit) : null,
        valid_from: form.valid_from || null,
        valid_to: form.valid_to || null,
        active: form.status === 'active',
      }

      if (isEdit) {
        const { error } = await debugAction('handleSave:update', 'PromoCodes', () => supabase.from('promo_codes').update(payload).eq('id', existing.id), { id: existing.id, payload })
        if (error) throw error
        await logAudit('promo_code_updated', { code: payload.code })
      } else {
        const { error } = await debugAction('handleSave:insert', 'PromoCodes', () => supabase.from('promo_codes').insert({ ...payload, used_count: 0 }), { payload })
        if (error) throw error
        await logAudit('promo_code_created', { code: payload.code })
      }
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  async function logAudit(action, details) {
    try {
      const { data: { user } } = await supabase.auth.getUser()
      await supabase.from('admin_audit_log').insert({ admin_id: user?.id, action, details })
    } catch {}
  }

  return (
    <Modal open title={isEdit ? `Upravit: ${existing.code}` : 'Nový promo kód'} onClose={onClose}>
      <div className="grid grid-cols-2 gap-3">
        <div className="col-span-2">
          <Label>Kód</Label>
          <input
            value={form.code}
            onChange={e => set('code', e.target.value.toUpperCase())}
            className="w-full rounded-btn text-sm outline-none font-mono"
            style={inputStyle}
            placeholder="LETO2026"
            disabled={isEdit}
          />
          {isEdit && <span className="text-sm" style={{ color: '#1a2e22' }}>Kód nelze měnit po vytvoření</span>}
        </div>
        <div>
          <Label>Typ slevy</Label>
          <select value={form.discount_type} onChange={e => set('discount_type', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            <option value="percent">Procenta (%)</option>
            <option value="fixed">Pevná částka (Kč)</option>
          </select>
        </div>
        <div>
          <Label>Hodnota slevy</Label>
          <input type="number" value={form.discount_value} onChange={e => set('discount_value', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} placeholder={form.discount_type === 'percent' ? '10' : '500'} />
        </div>
        <div>
          <Label>Platnost od</Label>
          <input type="date" value={form.valid_from} onChange={e => set('valid_from', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div>
          <Label>Platnost do</Label>
          <input type="date" value={form.valid_to} onChange={e => set('valid_to', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div>
          <Label>Limit použití</Label>
          <input type="number" value={form.usage_limit} onChange={e => set('usage_limit', e.target.value)} placeholder="Neomezeno" className="w-full rounded-btn text-sm outline-none" style={inputStyle} />
        </div>
        <div>
          <Label>Stav</Label>
          <select value={form.status} onChange={e => set('status', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={inputStyle}>
            <option value="active">Aktivní</option>
            <option value="inactive">Neaktivní</option>
          </select>
        </div>
      </div>

      {isEdit && existing.used_count > 0 && (
        <div className="mt-3 p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>
            Tento kód byl použit {existing.used_count}× z {existing.max_uses ?? '∞'} povolených.
          </span>
        </div>
      )}

      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.code || !form.discount_value}>
          {saving ? 'Ukládám…' : isEdit ? 'Uložit změny' : 'Vytvořit'}
        </Button>
      </div>
    </Modal>
  )
}

export function PromoDetailModal({ code, onClose, onEdit }) {
  const [usage, setUsage] = useState([])
  const [loadingUsage, setLoadingUsage] = useState(true)

  useEffect(() => {
    supabase.from('promo_code_usage')
      .select('*, profiles:customer_id(full_name, email)')
      .eq('promo_code_id', code.id)
      .order('used_at', { ascending: false })
      .limit(20)
      .then(({ data }) => { setUsage(data || []); setLoadingUsage(false) })
      .catch(() => { setUsage([]); setLoadingUsage(false) })
  }, [code.id])

  return (
    <Modal open title={`Detail: ${code.code}`} onClose={onClose}>
      <div className="grid grid-cols-2 gap-4">
        <DetailRow label="Kod" value={code.code} mono />
        <DetailRow label="Stav" value={code.active ? 'Aktivni' : 'Neaktivni'} />
        <DetailRow label="Typ slevy" value={code.type === 'percent' ? 'Procentualni' : 'Pevna castka'} />
        <DetailRow label="Hodnota" value={code.type === 'percent' ? `${code.value}%` : `${code.value?.toLocaleString('cs-CZ')} Kc`} />
        <DetailRow label="Platnost od" value={code.valid_from ? new Date(code.valid_from).toLocaleDateString('cs-CZ') : 'Neuvedeno'} />
        <DetailRow label="Platnost do" value={code.valid_to ? new Date(code.valid_to).toLocaleDateString('cs-CZ') : 'Neomezena'} />
        <DetailRow label="Pouzito" value={`${code.used_count ?? 0}x`} />
        <DetailRow label="Limit" value={code.max_uses ?? 'Neomezeno'} />
        <DetailRow label="Vytvoreno" value={code.created_at ? new Date(code.created_at).toLocaleString('cs-CZ') : '\u2014'} />
      </div>

      <div className="mt-5">
        <h4 className="text-sm font-extrabold uppercase tracking-widest mb-3" style={{ color: '#1a2e22' }}>Historie pouziti</h4>
        {loadingUsage ? (
          <div className="text-sm" style={{ color: '#1a2e22' }}>Nacitam...</div>
        ) : usage.length === 0 ? (
          <div className="text-sm" style={{ color: '#1a2e22' }}>Zatim nepouzito</div>
        ) : (
          <div className="space-y-2 max-h-48 overflow-auto">
            {usage.map(u => (
              <div key={u.id} className="flex items-center gap-3 p-2 rounded-lg text-sm" style={{ background: '#f1faf7' }}>
                <span className="font-bold">{u.profiles?.full_name || u.profiles?.email || 'Neznamy'}</span>
                <span style={{ color: '#1a2e22' }}>{u.used_at ? new Date(u.used_at).toLocaleString('cs-CZ') : ''}</span>
                <span className="ml-auto font-bold" style={{ color: '#1a8a18' }}>-{u.discount_applied?.toLocaleString('cs-CZ')} Kc</span>
              </div>
            ))}
          </div>
        )}
      </div>

      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zavrit</Button>
        <Button onClick={onEdit} style={{ background: '#2563eb', color: '#fff' }}>Upravit</Button>
      </div>
    </Modal>
  )
}

function DetailRow({ label, value, mono }) {
  return (
    <div>
      <div className="text-sm font-extrabold uppercase tracking-wide mb-0.5" style={{ color: '#1a2e22' }}>{label}</div>
      <div className={`text-sm font-semibold ${mono ? 'font-mono' : ''}`} style={{ color: '#0f1a14' }}>{value ?? '—'}</div>
    </div>
  )
}

export function SummaryCard({ label, value, color }) {
  return (
    <div className="p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
      <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>{label}</div>
      <div className="text-xl font-extrabold" style={{ color }}>{value}</div>
    </div>
  )
}

export function ActionBtn({ children, color, onClick }) {
  return (
    <button
      onClick={onClick}
      className="text-sm font-bold cursor-pointer"
      style={{ color, background: 'none', border: 'none', padding: '4px 6px' }}
    >
      {children}
    </button>
  )
}

export function CheckboxFilterGroup({ label, values, onChange, options }) {
  const toggle = val => {
    if (values.includes(val)) onChange(values.filter(v => v !== val))
    else onChange([...values, val])
  }
  return (
    <div className="flex items-center gap-1 flex-wrap rounded-btn"
      style={{ padding: '4px 10px', background: values.length > 0 ? '#e8fde8' : '#f1faf7', border: '1px solid #d4e8e0' }}>
      <span className="text-sm font-extrabold uppercase tracking-wide mr-1" style={{ color: '#1a2e22' }}>{label}:</span>
      {options.map(o => (
        <label key={o.value} className="flex items-center gap-1 cursor-pointer"
          style={{ padding: '3px 6px', borderRadius: 6, background: values.includes(o.value) ? '#74FB71' : 'transparent' }}>
          <input type="checkbox" checked={values.includes(o.value)} onChange={() => toggle(o.value)}
            className="accent-[#1a8a18]" style={{ width: 14, height: 14 }} />
          <span className="text-sm font-bold" style={{ color: '#1a2e22', whiteSpace: 'nowrap' }}>{o.label}</span>
        </label>
      ))}
    </div>
  )
}
