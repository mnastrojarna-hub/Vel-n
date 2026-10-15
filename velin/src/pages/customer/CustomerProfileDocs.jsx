// Karta „Doklady a oprávnění“ v Profilu zákazníka. Čísla a platnosti dokladů jsou
// editovatelné (ukládá je „Uložit změny“ v CustomerDetail — jen změněná pole); každý
// doklad jde celý odebrat (fotky + údaje v profilu, CustomerDocRemoveModal).
// Platnost OP / pasu (id_verified_until / passport_verified_until) je jen záznam
// do smlouvy — brána kódů k boxu ji neposuzuje.
import { useEffect, useState } from 'react'
import Card from '../../components/ui/Card'
import Badge from '../../components/ui/Badge'
import { kindOfDoc, loadVerificationDocs } from '../../lib/customerDocs'
import { C, fmtDate, SectionTitle, Field, Info } from './profileUi'
import CustomerDocRemoveModal from './CustomerDocRemoveModal'

function VerifyBadge({ verified, date }) {
  if (verified) {
    return (
      <span className="inline-flex items-center gap-1 rounded-full text-[11px] font-bold whitespace-nowrap" style={{ padding: '2px 9px', background: '#dcfce7', color: C.gdk }}>
        {'✓'} Ověřeno{date ? ` · ${date}` : ''}
      </span>
    )
  }
  return (
    <span className="inline-flex items-center gap-1 rounded-full text-[11px] font-bold whitespace-nowrap" style={{ padding: '2px 9px', background: '#f3f4f6', color: '#9ca3af' }}>
      {'✕'} Neověřeno
    </span>
  )
}

// footer: počet fotek v archivu + „Odebrat doklad“ (jen když je co odebrat)
function DocBox({ title, badge, children, photos, canRemove, onRemove }) {
  return (
    <div className="rounded-xl p-3.5 flex flex-col" style={{ background: C.g100, border: `1px solid ${C.g200}` }}>
      <div className="flex items-center justify-between gap-2 mb-2.5">
        <span className="text-xs font-extrabold uppercase tracking-wide" style={{ color: C.dark }}>{title}</span>
        {badge}
      </div>
      <div className="space-y-2.5 flex-1">{children}</div>
      <div className="flex items-center justify-between gap-2 mt-3 pt-2.5" style={{ borderTop: `1px solid ${C.g200}` }}>
        <span className="text-[11px] font-bold" style={{ color: C.muted }}>
          {photos == null ? '' : photos ? `Fotky v archivu: ${photos}` : 'Bez fotek v archivu'}
        </span>
        {canRemove && (
          <button type="button" onClick={onRemove}
            className="text-xs font-extrabold uppercase tracking-wide cursor-pointer max-lg:min-h-[40px] max-lg:px-2"
            style={{ background: 'none', border: 'none', color: C.red }}>
            Odebrat doklad
          </button>
        )}
      </div>
    </div>
  )
}

export default function CustomerProfileDocs({ customer, set, onPatched }) {
  const [docs, setDocs] = useState(null) // null = načítá se / nenačteno
  const [removing, setRemoving] = useState(null) // 'id' | 'passport' | 'dl'
  const groups = customer.license_group || []

  async function load() {
    try { setDocs(await loadVerificationDocs(customer.id)) } catch { setDocs(null) }
  }
  useEffect(() => { if (customer.id) load() }, [customer.id])

  const byKind = { id: [], passport: [], dl: [] }
  for (const d of docs || []) { const k = kindOfDoc(d); if (k) byKind[k].push(d) }
  const photos = (k) => (docs ? byKind[k].length : null)
  const any = (...v) => v.some(x => x != null && String(x).trim() !== '')
  const can = {
    id: byKind.id.length > 0 || any(customer.id_verified_at, customer.id_verified_until),
    passport: byKind.passport.length > 0 || any(customer.passport_verified_at, customer.passport_verified_until),
    dl: byKind.dl.length > 0 || any(customer.license_number, customer.license_expiry, customer.license_verified_at, customer.license_verified_until),
  }
  const box = (k) => ({ photos: photos(k), canRemove: can[k], onRemove: () => setRemoving(k) })

  async function removed(patch) {
    onPatched?.(patch)
    setRemoving(null)
    await load()
  }

  return (
    <Card className="lg:col-span-2">
      <SectionTitle>Doklady a oprávnění</SectionTitle>
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-3.5">
        <DocBox title="Doklad totožnosti" badge={<VerifyBadge verified={!!customer.id_verified_at} date={fmtDate(customer.id_verified_at)} />} {...box('id')}>
          <Field label="Číslo dokladu" value={customer.id_number} onChange={v => set('id_number', v)} />
          <Field label="Platnost do" value={customer.id_verified_until} onChange={v => set('id_verified_until', v)} type="date" />
        </DocBox>

        <DocBox title="Řidičský průkaz" badge={<VerifyBadge verified={!!customer.license_verified_at} date={fmtDate(customer.license_verified_at)} />} {...box('dl')}>
          <Field label="Číslo ŘP" value={customer.license_number} onChange={v => set('license_number', v)} />
          <div>
            <div className="text-[11px] font-bold uppercase tracking-wide mb-1" style={{ color: C.muted }}>Skupiny</div>
            <div className="flex flex-wrap gap-1">
              {groups.length > 0 ? groups.map(g => <Badge key={g} label={g} color={C.gdk} bg="#dcfce7" />) : <span className="text-sm" style={{ color: C.faint }}>{'—'}</span>}
            </div>
          </div>
          <Field label="Platnost ŘP do" value={customer.license_expiry} onChange={v => set('license_expiry', v)} type="date" />
        </DocBox>

        <DocBox title="Cestovní pas" badge={<VerifyBadge verified={!!customer.passport_verified_at} date={fmtDate(customer.passport_verified_at)} />} {...box('passport')}>
          <Info label="Ověřeno" value={fmtDate(customer.passport_verified_at)} />
          <Field label="Platnost do" value={customer.passport_verified_until} onChange={v => set('passport_verified_until', v)} type="date" />
        </DocBox>
      </div>

      {removing && (
        <CustomerDocRemoveModal kind={removing} customer={customer} docsByKind={byKind}
          onClose={() => setRemoving(null)} onRemoved={removed} />
      )}
    </Card>
  )
}
