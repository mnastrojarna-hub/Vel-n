import { useState } from 'react'
import { supabase } from '../lib/supabase'
import { debugAction } from '../lib/debugLog'
import Button from '../components/ui/Button'
import Modal from '../components/ui/Modal'
import { FormField, generateBranchCode } from './BranchHelpers'
import { autoTranslateRow } from '../lib/autoTranslate'

function BranchModal({ existing, onClose, onSaved }) {
  const isEdit = !!existing
  const [form, setForm] = useState({
    name: existing?.name || '',
    branch_code: existing?.branch_code || '',
    city: existing?.city || '',
    address: existing?.address || '',
    phone: existing?.phone || '',
    location: existing?.location || '',
    type: existing?.type || '',
    is_open: existing?.is_open ?? false,
    gps_lat: existing?.gps_lat || '',
    gps_lng: existing?.gps_lng || '',
    notes: existing?.notes || '',
    active: existing?.active !== false,
  })
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState(null)
  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  async function handleSave() {
    if (!form.name?.trim()) {
      setErr('Název pobočky je povinný.')
      return
    }
    setSaving(true); setErr(null)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      const payload = {
        name: form.name.trim(),
        branch_code: form.branch_code?.trim() || generateBranchCode(),
        city: form.city?.trim() || null,
        address: form.address?.trim() || null,
        phone: form.phone?.trim() || null,
        location: form.location?.trim() || null,
        type: form.type?.trim() || null,
        is_open: form.is_open,
        notes: form.notes?.trim() || null,
        gps_lat: form.gps_lat ? Number(form.gps_lat) : null,
        gps_lng: form.gps_lng ? Number(form.gps_lng) : null,
        active: form.active,
        updated_at: new Date().toISOString(),
      }
      const result = await debugAction(isEdit ? 'branches.update' : 'branches.create', 'BranchModal', () =>
        isEdit
          ? supabase.from('branches').update(payload).eq('id', existing.id).select().single()
          : supabase.from('branches').insert(payload).select().single()
      , payload)
      if (result?.error) {
        const msg = result.error.message || 'Neznámá chyba'
        throw new Error(msg + (result.error.code === '42501' ? ' — Zkontrolujte RLS politiky v Supabase.' : ''))
      }
      await supabase.from('admin_audit_log').insert({
        admin_id: user?.id,
        action: isEdit ? 'branch_updated' : 'branch_created',
        details: { name: form.name },
      })
      // Auto-překlad poznámky pro web (na pozadí)
      const branchId = result?.data?.id || existing?.id
      if (branchId && payload.notes) {
        autoTranslateRow({ table: 'branches', id: branchId, row: { notes: payload.notes } })
      }
      onSaved()
    } catch (e) { setErr(e.message) } finally { setSaving(false) }
  }

  return (
    <Modal open title={isEdit ? `Upravit: ${existing.name}` : 'Nová pobočka'} onClose={onClose} wide>
      <div className="grid grid-cols-2 gap-3">
        <FormField label="Název pobočky *" value={form.name} onChange={v => set('name', v)} />
        <FormField label="Kód pobočky" value={form.branch_code} onChange={v => set('branch_code', v)}
          placeholder="Automaticky generován pokud prázdný" />
        <FormField label="Město" value={form.city} onChange={v => set('city', v)} />
        <FormField label="Telefon" value={form.phone} onChange={v => set('phone', v)} />
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Umístění</label>
          <select value={form.location} onChange={e => set('location', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }}>
            <option value="">—</option>
            <option value="centrum">Centrum</option>
            <option value="předměstí">Předměstí</option>
            <option value="letiště">Letiště</option>
            <option value="turistická">Turistická</option>
          </select>
        </div>
        <div>
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Typ pobočky</label>
          <select value={form.type} onChange={e => set('type', e.target.value)} className="w-full rounded-btn text-sm outline-none" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }}>
            <option value="">—</option>
            <option value="samoobslužná">Samoobslužná (max 8 motorek)</option>
            <option value="obslužná">Obslužná — servisní místo (max 24 motorek)</option>
          </select>
        </div>
        <div className="col-span-2">
          <FormField label="Adresa" value={form.address} onChange={v => set('address', v)} />
        </div>
        <FormField label="GPS šířka" value={form.gps_lat} onChange={v => set('gps_lat', v)} type="number"
          placeholder="např. 49.7437" />
        <FormField label="GPS délka" value={form.gps_lng} onChange={v => set('gps_lng', v)} type="number"
          placeholder="např. 15.3386" />
        <div className="col-span-2">
          <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Poznámky</label>
          <textarea value={form.notes} onChange={e => set('notes', e.target.value)}
            className="w-full rounded-btn text-sm outline-none"
            style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', minHeight: 60, resize: 'vertical' }} />
        </div>
        <div className="col-span-2 flex items-center gap-4">
          <label className="flex items-center gap-2 cursor-pointer">
            <div onClick={() => set('is_open', !form.is_open)}
              className="rounded-btn font-extrabold text-sm cursor-pointer border-none"
              style={{
                padding: '6px 16px',
                background: form.is_open ? '#1a8a18' : '#dc2626',
                color: '#fff',
                userSelect: 'none',
              }}>
              {form.is_open ? 'OTEVŘENÁ — Nonstop' : 'ZAVŘENÁ'}
            </div>
          </label>
          <label className="flex items-center gap-2">
            <input type="checkbox" checked={form.active} onChange={e => set('active', e.target.checked)} />
            <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Pobočka je aktivní</span>
          </label>
        </div>
      </div>
      {err && <p className="mt-3 text-sm" style={{ color: '#dc2626', whiteSpace: 'pre-wrap' }}>{err}</p>}
      <div className="flex justify-end gap-3 mt-5">
        <Button onClick={onClose}>Zrušit</Button>
        <Button green onClick={handleSave} disabled={saving || !form.name?.trim()}>
          {saving ? 'Ukládám...' : isEdit ? 'Uložit změny' : 'Vytvořit'}
        </Button>
      </div>
    </Modal>
  )
}

export default BranchModal
