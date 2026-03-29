import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import Card from '../components/ui/Card'
import Button from '../components/ui/Button'
import Badge from '../components/ui/Badge'

function SectionTitle({ children }) {
  return <h3 className="text-sm font-extrabold uppercase tracking-widest mb-4" style={{ color: '#1a2e22' }}>{children}</h3>
}

function Field({ label, value, onChange, type = 'text', disabled = false }) {
  return (
    <div>
      <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{label}</label>
      <input type={type} value={value || ''} onChange={e => onChange?.(e.target.value)} disabled={disabled} className="w-full rounded-btn text-sm outline-none disabled:opacity-50" style={{ padding: '8px 12px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#0f1a14' }} />
    </div>
  )
}

function ConsentRow({ label, checked, onChange }) {
  return (
    <div className="flex items-center gap-3 p-2 rounded-lg" style={{ background: '#f1faf7' }}>
      <input type="checkbox" checked={checked} onChange={e => onChange(e.target.checked)} className="w-4 h-4 cursor-pointer" />
      <span className="text-sm font-bold" style={{ color: '#0f1a14' }}>{label}</span>
      <span className="text-xs ml-auto" style={{ color: checked ? '#1a8a18' : '#dc2626' }}>{checked ? 'Ano' : 'Ne'}</span>
    </div>
  )
}

function GearSizes({ gearSizes }) {
  if (!gearSizes || (typeof gearSizes === 'object' && Object.keys(gearSizes).length === 0)) return <span style={{ color: '#1a2e22', fontSize: 13 }}>{'\u2014'}</span>
  if (typeof gearSizes === 'object' && !Array.isArray(gearSizes)) {
    return (<div className="grid grid-cols-2 gap-2">{Object.entries(gearSizes).map(([k, v]) => (<div key={k} className="flex items-center gap-2 p-2 rounded-lg" style={{ background: '#f1faf7' }}><span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>{k}</span><span className="text-sm font-bold" style={{ color: '#0f1a14' }}>{String(v)}</span></div>))}</div>)
  }
  return <span className="text-sm" style={{ color: '#1a2e22' }}>{JSON.stringify(gearSizes)}</span>
}

function PlatformSection({ userId }) {
  const [sources, setSources] = useState(null)
  useEffect(() => {
    if (!userId) return
    supabase.from('bookings').select('booking_source').eq('user_id', userId)
      .then(({ data }) => { if (!data) return; setSources(new Set(data.map(b => b.booking_source).filter(Boolean))) }).catch(() => {})
  }, [userId])
  if (!sources || sources.size === 0) return null
  const hasApp = sources.has('app'), hasWeb = sources.has('web')
  return (
    <Card><SectionTitle>Platforma</SectionTitle>
      <div className="flex items-center gap-3">
        {hasApp && <span className="inline-flex items-center gap-1.5 rounded-btn text-sm font-extrabold uppercase tracking-wide" style={{ padding: '6px 14px', background: '#dcfce7', color: '#16a34a' }}>APP</span>}
        {hasWeb && <span className="inline-flex items-center gap-1.5 rounded-btn text-sm font-extrabold uppercase tracking-wide" style={{ padding: '6px 14px', background: '#dbeafe', color: '#2563eb' }}>WEB</span>}
        <span className="text-sm" style={{ color: '#6b7280' }}>{hasApp && hasWeb ? 'Zakaznik pouziva aplikaci i web' : hasApp ? 'Zakaznik pouziva mobilni aplikaci' : 'Zakaznik pouziva web'}</span>
      </div>
    </Card>
  )
}

export default function ProfileTab({ customer, set, error, saving, onSave, onDelete, onBlock }) {
  return (
    <div className="space-y-5">
      <Card><SectionTitle>Osobni udaje</SectionTitle>
        <div className="grid grid-cols-2 gap-4">
          <Field label="Jmeno" value={customer.full_name} onChange={v => set('full_name', v)} />
          <Field label="Email" value={customer.email} disabled />
          <Field label="Telefon" value={customer.phone} onChange={v => set('phone', v)} />
          <Field label="Datum narozeni" value={customer.date_of_birth} onChange={v => set('date_of_birth', v)} type="date" />
          <Field label="Jazyk" value={customer.language} disabled />
          <Field label="Registrace" value={customer.created_at?.slice(0, 10)} disabled />
        </div>
      </Card>
      <Card><SectionTitle>Adresa</SectionTitle>
        <div className="grid grid-cols-2 gap-4">
          <div className="col-span-2"><Field label="Ulice" value={customer.street} onChange={v => set('street', v)} /></div>
          <Field label="Mesto" value={customer.city} onChange={v => set('city', v)} />
          <Field label="PSC" value={customer.zip} onChange={v => set('zip', v)} />
          <Field label="Zeme" value={customer.country || 'CZ'} onChange={v => set('country', v)} />
        </div>
      </Card>
      <PlatformSection userId={customer.id} />
      <Card><SectionTitle>Ridicak a zkusenosti</SectionTitle>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Ridicske skupiny</label>
            <div className="flex flex-wrap gap-1">
              {(customer.license_group && customer.license_group.length > 0) ? customer.license_group.map(g => <Badge key={g} label={g} color="#1a8a18" bg="#dcfce7" />) : <span style={{ color: '#1a2e22', fontSize: 13 }}>{'\u2014'}</span>}
            </div>
          </div>
          <Field label="Jezdecke zkusenosti" value={customer.riding_experience} onChange={v => set('riding_experience', v)} />
        </div>
      </Card>
      <Card><SectionTitle>Kontakt pro pripad nouze</SectionTitle>
        <div className="grid grid-cols-2 gap-4">
          <Field label="Jmeno" value={customer.emergency_contact} onChange={v => set('emergency_contact', v)} />
          <Field label="Telefon" value={customer.emergency_phone} onChange={v => set('emergency_phone', v)} />
        </div>
      </Card>
      <Card><SectionTitle>Vybaveni</SectionTitle><GearSizes gearSizes={customer.gear_sizes} /></Card>
      <Card><SectionTitle>Admin poznamky</SectionTitle>
        <Field label="Poznamky k zakaznikovi" value={customer.reliability_score?.notes} onChange={v => set('reliability_score', { ...customer.reliability_score, notes: v })} />
      </Card>
      <Card><SectionTitle>Souhlasy</SectionTitle>
        <div className="grid grid-cols-2 gap-3">
          <ConsentRow label="Marketingovy souhlas" checked={!!customer.marketing_consent} onChange={v => set('marketing_consent', v)} />
          <ConsentRow label="GDPR" checked={!!customer.consent_gdpr} onChange={v => set('consent_gdpr', v)} />
          <ConsentRow label="VOP" checked={!!customer.consent_vop} onChange={v => set('consent_vop', v)} />
          <ConsentRow label="Zpracovani dat" checked={!!customer.consent_data_processing} onChange={v => set('consent_data_processing', v)} />
          <ConsentRow label="Smlouva" checked={!!customer.consent_contract} onChange={v => set('consent_contract', v)} />
          <ConsentRow label="Email" checked={!!customer.consent_email} onChange={v => set('consent_email', v)} />
          <ConsentRow label="SMS" checked={!!customer.consent_sms} onChange={v => set('consent_sms', v)} />
          <ConsentRow label="WhatsApp" checked={!!customer.consent_whatsapp} onChange={v => set('consent_whatsapp', v)} />
          <ConsentRow label="Push" checked={!!customer.consent_push} onChange={v => set('consent_push', v)} />
          <ConsentRow label="Foto" checked={!!customer.consent_photo} onChange={v => set('consent_photo', v)} />
        </div>
      </Card>
      {error && <p className="text-sm" style={{ color: '#dc2626' }}>{error}</p>}
      <div className="flex gap-3">
        <Button green onClick={onSave} disabled={saving}>{saving ? 'Ukladam...' : 'Ulozit'}</Button>
        <Button onClick={onDelete} style={{ color: '#dc2626' }}>Smazat zakaznika</Button>
        <button onClick={onBlock} className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
          style={{ padding: '8px 16px', background: customer.is_blocked ? '#dcfce7' : '#7f1d1d', color: customer.is_blocked ? '#1a8a18' : '#fff', border: 'none' }}>
          {customer.is_blocked ? 'Odblokovat zakaznika' : 'Zablokovat zakaznika'}
        </button>
      </div>
    </div>
  )
}
