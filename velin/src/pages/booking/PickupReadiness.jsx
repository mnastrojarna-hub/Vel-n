import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Button from '../../components/ui/Button'
import { computeDocVerification, MOTO_LICENSE_GROUPS } from '../../lib/docVerification'
import AdminDocUploadModal from '../customer/AdminDocUploadModal'
import ElectronicProtocolModal from './ElectronicProtocolModal'

// Kompletní odbavení odjezdu na OBSLUŽNÉ pobočce:
//   1) Údaje — doplnit chybějící/expirované údaje ŘP (platnost + skupiny).
//   2) Doklady — nahrát chybějící doklady (ŘP / OP / pas) přes OCR.
//   3) Protokol — podpis předávacího protokolu → označení vyzvednutí.
// Dětská motorka (license_required = 'N') doklady nevyžaduje — rovnou protokol.

const VERIFICATION_TYPES = ['drivers_license', 'license_photo', 'id_card', 'id_photo', 'passport']
const ALL_GROUPS = ['AM', 'A1', 'A2', 'A', 'B']
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

// `codePreVerified` — identita už byla ověřena kódem motorky při vyhledání
// rezervace (rychlé odbavení z Velína); protokol pak kód znovu nevyžaduje.
export default function PickupReadiness({ booking, onClose, onProtocolDone, codePreVerified = false }) {
  const [loading, setLoading] = useState(true)
  const [profile, setProfile] = useState(null)
  const [docs, setDocs] = useState([])
  const [licenseRequired, setLicenseRequired] = useState(null)
  const [showUpload, setShowUpload] = useState(false)
  const [showProtocol, setShowProtocol] = useState(false)
  const [error, setError] = useState(null)
  // Editace údajů dokladů (ŘP + číslo OP/pasu)
  const [licNo, setLicNo] = useState('')
  const [licExp, setLicExp] = useState('')
  const [groups, setGroups] = useState([])
  const [idNo, setIdNo] = useState('')
  const [savingData, setSavingData] = useState(false)

  useEffect(() => { load() }, [booking?.id])

  async function load() {
    setLoading(true); setError(null)
    try {
      const [docsRes, profRes, bkRes] = await Promise.all([
        supabase.from('documents').select('id, type, metadata, created_at').eq('user_id', booking.user_id).in('type', VERIFICATION_TYPES).order('created_at', { ascending: false }),
        supabase.from('profiles').select('id, license_expiry, license_group, license_number, id_number, id_verified_at, license_verified_at, passport_verified_at').eq('id', booking.user_id).single(),
        supabase.from('bookings').select('motorcycles!moto_id(license_required)').eq('id', booking.id).single(),
      ])
      setDocs(docsRes.data || [])
      const p = profRes.data || null
      setProfile(p)
      setLicenseRequired(bkRes?.data?.motorcycles?.license_required ?? null)
      setLicNo(p?.license_number || '')
      setLicExp(p?.license_expiry ? String(p.license_expiry).slice(0, 10) : '')
      setGroups(Array.isArray(p?.license_group) ? p.license_group : [])
      setIdNo(p?.id_number || '')
    } catch (e) { setError(e.message) }
    setLoading(false)
  }

  if (!booking?.user_id) {
    return (
      <div className="space-y-3">
        <div style={note('#b45309', '#fffbeb', '#92400e')}>Rezervace nemá přiřazeného zákazníka — odbavte ručně přes detail rezervace.</div>
        <div className="flex justify-end"><Button onClick={onClose}>Zavřít</Button></div>
      </div>
    )
  }
  if (loading) return <div className="py-6 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>

  const vs = computeDocVerification(docs, profile, licenseRequired)
  const isChild = vs.isChildMoto
  // Čísla dokladů (ŘP i OP/pas) jsou POVINNÁ — bez nich odbavení nepustí a operátor
  // je vyzván k doplnění (dřív se ptalo jen na platnost/skupiny ŘP, ne na číslo OP/pasu).
  const dataOk = isChild || (vs.licenseNumberFilled && vs.idNumberFilled && vs.licenseValid && vs.licenseGroupFilled && vs.hasMotoGroup)
  const docsOk = isChild || (vs.hasLicense && vs.hasIdentity)
  // Protokol (a tím odbavení) lze otevřít, až když jsou vyplněná čísla dokladů (dataOk)
  // i ověřené doklady (allOk) — jinak by šlo odbavit s prázdným číslem OP/pasu.
  const ready = isChild || (dataOk && vs.allOk)

  function toggleGroup(g) { setGroups(gs => gs.includes(g) ? gs.filter(x => x !== g) : [...gs, g]) }

  async function saveData() {
    setSavingData(true); setError(null)
    const upd = {}
    if (licNo.trim()) upd.license_number = licNo.trim()
    if (licExp) { upd.license_expiry = licExp; upd.license_verified_until = licExp }
    if (groups.length) upd.license_group = groups
    if (idNo.trim()) upd.id_number = idNo.trim()
    try {
      const { error: e } = await supabase.from('profiles').update(upd).eq('id', booking.user_id)
      if (e) throw e
      await load()
    } catch (e) { setError('Uložení údajů selhalo: ' + e.message) }
    setSavingData(false)
  }

  if (showProtocol) {
    return (
      <ElectronicProtocolModal
        open
        type="handover_protocol"
        bookingId={booking.id}
        codePreVerified={codePreVerified}
        onClose={() => setShowProtocol(false)}
        onSaved={() => onProtocolDone?.()}
      />
    )
  }

  return (
    <div className="space-y-4">
      {error && <div style={note('#dc2626', '#fee2e2', '#dc2626')}>{error}</div>}

      <div style={note('#2563eb', '#eff6ff', '#1e3a8a')}>
        <strong>Obslužná pobočka.</strong> {isChild
          ? 'Dětská motorka — doklady nejsou potřeba, stačí podepsat předávací protokol.'
          : 'Než zákazník podepíše předávací protokol, doplňte chybějící údaje a doklady.'}
      </div>

      {!isChild && (
        <>
          {/* 1) ÚDAJE ŘP */}
          <div className="p-3 rounded-card" style={{ background: '#f8faf9', border: '1px solid #eef5f1' }}>
            <StepHead n={1} label="Údaje dokladů (ŘP + číslo OP/pasu)" done={dataOk} />
            {dataOk ? (
              <div className="text-sm" style={{ color: '#15803d' }}>✓ Čísla dokladů, platnost i skupiny ŘP v pořádku ({(profile?.license_group || []).join(', ')}, platí do {profile?.license_expiry}).</div>
            ) : (
              <div className="space-y-2">
                {!vs.licenseNumberFilled && <div style={note('#b45309', '#fffbeb', '#92400e')}>Není vyplněné číslo ŘP.</div>}
                {!vs.idNumberFilled && <div style={note('#b45309', '#fffbeb', '#92400e')}>Není vyplněné číslo dokladu totožnosti (OP/pas).</div>}
                {!vs.licenseValid && <div style={note('#b45309', '#fffbeb', '#92400e')}>{profile?.license_expiry ? 'ŘP je expirovaný — ověřte a opravte platnost.' : 'Není vyplněná platnost ŘP.'}</div>}
                {(!vs.licenseGroupFilled || !vs.hasMotoGroup) && <div style={note('#b45309', '#fffbeb', '#92400e')}>Chybí skupina ŘP pro motorku (A/A2/A1/AM).</div>}
                <div>
                  <label className="text-xs font-bold" style={{ color: '#1a2e22' }}>Číslo ŘP</label>
                  <input value={licNo} onChange={e => setLicNo(e.target.value)} style={inputStyle} placeholder="číslo ŘP" />
                </div>
                <div>
                  <label className="text-xs font-bold" style={{ color: '#1a2e22' }}>Číslo dokladu totožnosti (OP/pas)</label>
                  <input value={idNo} onChange={e => setIdNo(e.target.value)} style={inputStyle} placeholder="číslo OP nebo pasu" />
                </div>
                <div>
                  <label className="text-xs font-bold" style={{ color: '#1a2e22' }}>Platnost ŘP do</label>
                  <input type="date" value={licExp} onChange={e => setLicExp(e.target.value)} style={inputStyle} />
                </div>
                <div>
                  <label className="text-xs font-bold" style={{ color: '#1a2e22' }}>Skupiny ŘP</label>
                  <div className="flex flex-wrap gap-2 mt-1">
                    {ALL_GROUPS.map(g => {
                      const on = groups.includes(g)
                      const moto = MOTO_LICENSE_GROUPS.includes(g)
                      return (
                        <button key={g} onClick={() => toggleGroup(g)}
                          className="rounded-btn text-sm font-bold cursor-pointer"
                          style={{ padding: '5px 12px', border: 'none', background: on ? '#74FB71' : '#f1faf7', color: '#1a2e22', boxShadow: on ? '0 3px 12px rgba(116,251,113,.35)' : 'none' }}>
                          {g}{moto ? ' 🏍️' : ''}
                        </button>
                      )
                    })}
                  </div>
                </div>
                <div className="flex justify-end"><Button green disabled={savingData} onClick={saveData}>{savingData ? 'Ukládám…' : 'Uložit údaje'}</Button></div>
              </div>
            )}
          </div>

          {/* 2) DOKLADY */}
          <div className="p-3 rounded-card" style={{ background: '#f8faf9', border: '1px solid #eef5f1' }}>
            <StepHead n={2} label="Doklady (ŘP + OP/pas)" done={docsOk} />
            {docsOk ? (
              <div className="text-sm" style={{ color: '#15803d' }}>✓ Doklady ověřeny.</div>
            ) : (
              <div className="space-y-2">
                <div className="text-sm" style={{ color: '#1a2e22' }}>
                  {!vs.hasLicense && <div>• Chybí ověřený řidičský průkaz</div>}
                  {!vs.hasIdentity && <div>• Chybí ověřený doklad totožnosti (OP/pas)</div>}
                </div>
                <Button green onClick={() => setShowUpload(true)}>+ Nahrát doklady</Button>
              </div>
            )}
          </div>
        </>
      )}

      {/* 3) PROTOKOL */}
      <div className="p-3 rounded-card" style={{ background: '#f8faf9', border: '1px solid #eef5f1' }}>
        <StepHead n={3} label="Předávací protokol" done={false} />
        {ready ? (
          <div className="space-y-2">
            <Button green onClick={() => setShowProtocol(true)}>✍️ Otevřít předávací protokol (elektronicky)</Button>
            <div>
              <Button onClick={() => {
                if (window.confirm('Potvrdit, že byl s klientem vyplněn a podepsán TIŠTĚNÝ předávací protokol? Rezervace se aktivuje (předání) a zaznamená se čas.')) onProtocolDone?.()
              }}>🖨️ Potvrdit tištěný protokol</Button>
              <p className="text-xs mt-1" style={{ color: '#64748b' }}>Použijte, když protokol vyplňujete na papír — bez elektronického podpisu.</p>
            </div>
          </div>
        ) : (
          <div className="text-sm" style={{ color: '#b45309' }}>Nejprve doplňte chybějící údaje a doklady výše.</div>
        )}
      </div>

      <div className="flex justify-end"><Button onClick={onClose}>Zavřít</Button></div>

      {showUpload && (
        <AdminDocUploadModal
          userId={booking.user_id}
          bookingId={booking.id}
          onClose={() => setShowUpload(false)}
          onUploaded={load}
        />
      )}
    </div>
  )
}
