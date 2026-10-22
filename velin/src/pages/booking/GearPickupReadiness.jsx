import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Button from '../../components/ui/Button'
import { identityMissing } from '../../lib/docVerification'
import { bookingDocsVerdict } from '../../lib/docsGate'
import { gearDocsVerdict, gearSizeSummary } from '../../lib/bookingKind'
import AdminDocUploadModal from '../customer/AdminDocUploadModal'
import ElectronicProtocolModal from './ElectronicProtocolModal'

// Odbavení výpůjčky JEN výbavy na OBSLUŽNÉ pobočce (PickupReadiness → booking_kind 'gear'):
//   1) Doklad totožnosti — OP (líc + rub) nebo pas (OCR doplní číslo a datum narození).
//   2) Údaje — číslo dokladu totožnosti + datum narození (18+ k začátku výpůjčky).
//   3) Protokol — předávací protokol výbavy (velikosti, podpis) → označení vyzvednutí.
// Řidičský průkaz se u výbavy NEvyžaduje (rozhodnutí majitele 2026-10-23).

const VERIFICATION_TYPES = ['id_card', 'id_photo', 'passport', 'drivers_license', 'license_photo']
const inputStyle = { width: '100%', padding: '9px 12px', borderRadius: 10, border: '1px solid #b6dccb', fontSize: 14 }
const note = (border, bg, color) => ({ border: `1px solid ${border}`, background: bg, color, borderRadius: 10, padding: 10, fontSize: 13 })

function StepHead({ n, label, done }) {
  return (
    <div className="flex items-center gap-2 mb-2">
      <span style={{ width: 22, height: 22, borderRadius: 999, background: done ? '#15803d' : '#cbd5e1', color: '#fff', fontSize: 12, fontWeight: 800, display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>{done ? '✓' : n}</span>
      <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>{label}</span>
    </div>
  )
}

export default function GearPickupReadiness({ booking, onClose, onProtocolDone, verifiedCode = '' }) {
  const [loading, setLoading] = useState(true)
  const [vs, setVs] = useState(null)
  const [error, setError] = useState(null)
  const [showUpload, setShowUpload] = useState(false)
  const [showProtocol, setShowProtocol] = useState(false)
  const [idNo, setIdNo] = useState('')
  const [dob, setDob] = useState('')
  const [savingData, setSavingData] = useState(false)

  useEffect(() => { load(true) }, [booking?.id])

  // `initial` — spinner jen při prvním načtení (refresh po nahrání dokladu nesmí odmountovat modal focení)
  async function load(initial = false) {
    if (initial) setLoading(true)
    setError(null)
    try {
      const [docsRes, profRes] = await Promise.all([
        supabase.from('documents').select('id, user_id, type, file_path, metadata, created_at').eq('user_id', booking.user_id).in('type', VERIFICATION_TYPES).order('created_at', { ascending: false }),
        supabase.from('profiles').select('id, license_expiry, license_verified_until, license_group, date_of_birth, license_number, id_number, id_verified_at, license_verified_at, passport_verified_at').eq('id', booking.user_id).single(),
      ])
      const p = profRes.data || null
      const raw = await bookingDocsVerdict(docsRes.data || [], p || { id: booking.user_id }, { id: booking.id, start_date: booking.start_date, end_date: booking.end_date })
      setVs(gearDocsVerdict(raw))
      setIdNo(p?.id_number || '')
      setDob(p?.date_of_birth ? String(p.date_of_birth).slice(0, 10) : '')
    } catch (e) { setError(e.message) }
    setLoading(false)
  }

  if (!booking?.user_id) {
    return (
      <div className="space-y-3">
        <div style={note('#b45309', '#fffbeb', '#92400e')}>Výpůjčka nemá přiřazeného zákazníka — odbavte ručně přes detail rezervace.</div>
        <div className="flex justify-end"><Button onClick={onClose}>Zavřít</Button></div>
      </div>
    )
  }
  if (loading) return <div className="py-6 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>
  if (!vs) {
    return (
      <div className="space-y-3">
        <div style={note('#dc2626', '#fee2e2', '#dc2626')}>{error || 'Stav dokladů se nepodařilo načíst.'}</div>
        <div className="flex justify-end"><Button onClick={onClose}>Zavřít</Button></div>
      </div>
    )
  }

  const docsOk = !!vs.hasIdentity
  const dataOk = !!vs.idNumberFilled && !!vs.ageOk
  const ready = docsOk && dataOk && vs.allOk

  async function saveData() {
    setSavingData(true); setError(null)
    const upd = {}
    if (idNo.trim()) upd.id_number = idNo.trim()
    if (dob) upd.date_of_birth = dob
    try {
      const { error: e } = await supabase.from('profiles').update(upd).eq('id', booking.user_id)
      if (e) throw e
      await load()
    } catch (e) { setError('Uložení údajů selhalo: ' + e.message) }
    setSavingData(false)
  }

  if (showProtocol) {
    return (
      <ElectronicProtocolModal open type="handover_protocol" bookingId={booking.id} verifiedCode={verifiedCode}
        onClose={() => setShowProtocol(false)} onSaved={() => onProtocolDone?.()} />
    )
  }

  return (
    <div className="space-y-4">
      {error && <div style={note('#dc2626', '#fee2e2', '#dc2626')}>{error}</div>}
      <div style={note('#0e7490', '#ecfeff', '#164e63')}>
        <strong>Výpůjčka jen výbavy</strong>{gearSizeSummary(booking) ? ` (${gearSizeSummary(booking)})` : ''}. Stačí doklad totožnosti
        (OP líc + rub nebo pas) a věk 18+ — řidičský průkaz se nevyžaduje. Pak zákazník podepíše předávací protokol výbavy.
      </div>

      <div className="p-3 rounded-card" style={{ background: '#f8faf9', border: '1px solid #eef5f1' }}>
        <StepHead n={1} label="Doklad totožnosti (OP / pas)" done={docsOk} />
        {docsOk ? (
          <div className="text-sm" style={{ color: '#15803d' }}>✓ Doklad totožnosti nahrán.</div>
        ) : (
          <div className="space-y-2">
            <div className="text-sm" style={{ color: '#1a2e22' }}>• {identityMissing(vs) || 'Chybí OP (líc a rub) nebo pas'}</div>
            <Button green onClick={() => setShowUpload(true)}>+ Nahrát doklad</Button>
          </div>
        )}
      </div>

      <div className="p-3 rounded-card" style={{ background: '#f8faf9', border: '1px solid #eef5f1' }}>
        <StepHead n={2} label="Údaje (číslo dokladu + datum narození)" done={dataOk} />
        {dataOk ? (
          <div className="text-sm" style={{ color: '#15803d' }}>✓ Číslo dokladu vyplněné, zákazníkovi je 18+.</div>
        ) : (
          <div className="space-y-2">
            {!vs.idNumberFilled && <div style={note('#b45309', '#fffbeb', '#92400e')}>Není vyplněné číslo dokladu totožnosti (OP/pas).</div>}
            {!vs.ageOk && <div style={note('#b45309', '#fffbeb', '#92400e')}>{vs.dateOfBirth ? 'Zákazníkovi k začátku výpůjčky není 18 let — ověřte datum narození.' : 'Není vyplněné datum narození.'}</div>}
            <div>
              <label className="text-xs font-bold" style={{ color: '#1a2e22' }}>Číslo dokladu totožnosti (OP/pas)</label>
              <input value={idNo} onChange={e => setIdNo(e.target.value)} style={inputStyle} placeholder="číslo OP nebo pasu" />
            </div>
            <div>
              <label className="text-xs font-bold" style={{ color: '#1a2e22' }}>Datum narození</label>
              <input type="date" value={dob} onChange={e => setDob(e.target.value)} style={inputStyle} />
            </div>
            <div className="flex justify-end"><Button green disabled={savingData} onClick={saveData}>{savingData ? 'Ukládám…' : 'Uložit údaje'}</Button></div>
          </div>
        )}
      </div>

      <div className="p-3 rounded-card" style={{ background: '#f8faf9', border: '1px solid #eef5f1' }}>
        <StepHead n={3} label="Předávací protokol výbavy" done={false} />
        {ready ? (
          <div className="space-y-2">
            <Button green onClick={() => setShowProtocol(true)}>✍️ Otevřít předávací protokol (elektronicky)</Button>
            <div>
              <Button onClick={() => {
                if (window.confirm('Potvrdit, že byl s klientem vyplněn a podepsán TIŠTĚNÝ předávací protokol výbavy? Výpůjčka se aktivuje (předání) a zaznamená se čas.')) onProtocolDone?.()
              }}>🖨️ Potvrdit tištěný protokol</Button>
              <p className="text-xs mt-1" style={{ color: '#64748b' }}>Použijte, když protokol vyplňujete na papír — bez elektronického podpisu.</p>
            </div>
          </div>
        ) : (
          <div className="text-sm" style={{ color: '#b45309' }}>Nejprve doplňte doklad totožnosti a údaje výše.</div>
        )}
      </div>

      <div className="flex justify-end"><Button onClick={onClose}>Zavřít</Button></div>

      {showUpload && (
        <AdminDocUploadModal userId={booking.user_id} bookingId={booking.id} onClose={() => setShowUpload(false)} onUploaded={load} />
      )}
    </div>
  )
}
