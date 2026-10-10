import { useState, useEffect } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import Card from '../../components/ui/Card'
import Badge from '../../components/ui/Badge'
import { docSide, isMarkerPath, isRealDocFile } from '../../lib/docVerification'
import { bookingDocsVerdict } from '../../lib/docsGate'

const VERIFICATION_TYPES = ['drivers_license', 'license_photo', 'id_card', 'id_photo', 'passport']

function SideStatus({ docs, label }) {
  // docs is the subset for one document type — split into front/back (jen skutečné soubory,
  // strana z metadata.side / názvu souboru; rub = jiný soubor než líc — jako backend)
  const real = docs.filter(d => isRealDocFile(d))
  // Pas = jedna datová strana: stačí JAKÝKOLI skutečný soubor (i bez označení strany) — jako backend
  const isPass = label === 'Pas'
  const front = real.find(d => docSide(d) === 'front') || (isPass ? real[0] : undefined)
  const back = isPass ? undefined : real.find(d => docSide(d) === 'back' && d.file_path !== front?.file_path)
  const noSide = real.filter(d => d !== front && docSide(d) !== 'front' && docSide(d) !== 'back')
  const markers = docs.filter(d => isMarkerPath(d?.file_path)).length
  const okBadge = (st) => st === 'ok' ? '✅ OK' : st === 'failed' ? '⚠️ ručně' : '📷'
  return (
    <div className="text-xs" style={{ color: '#1a2e22' }}>
      <strong>{label}:</strong>{' '}
      {docs.length === 0 ? (
        <span style={{ color: '#dc2626' }}>nenahráno</span>
      ) : (
        <>
          {front
            ? <span style={{ marginRight: 6 }}>líc {okBadge(front.metadata?.mindee_status)}</span>
            : <span style={{ color: '#b45309', marginRight: 6 }}>líc chybí</span>}
          {back
            ? <span style={{ marginRight: 6 }}>rub {okBadge(back.metadata?.mindee_status)}</span>
            : label !== 'Pas'
              ? <span style={{ color: '#b45309', marginRight: 6 }}>rub chybí</span>
              : null}
          {noSide.length > 0 && <span style={{ color: '#5a6b63', marginRight: 6 }}>+{noSide.length} bez označení strany</span>}
          {markers > 0 && <span style={{ color: '#dc2626' }}>+{markers} záznam bez fotky</span>}
        </>
      )}
    </div>
  )
}

export default function BookingCustomerDocsStatus({ userId, bookingId }) {
  const [loading, setLoading] = useState(true)
  const [profile, setProfile] = useState(null)
  const [verificationDocs, setVerificationDocs] = useState([])
  // Verdikt = backend get_docs_gate_checklist pro rezervaci (záloha klient) — lib/docsGate
  const [vs, setVs] = useState(null)

  useEffect(() => { if (userId) loadStatus() }, [userId, bookingId])

  async function loadStatus() {
    setLoading(true)
    try {
      const promises = [
        supabase.from('documents').select('id, user_id, type, file_path, metadata, created_at').eq('user_id', userId).in('type', VERIFICATION_TYPES).order('created_at', { ascending: false }),
        supabase.from('profiles').select('id, license_expiry, license_verified_until, license_group, date_of_birth, license_number, id_number, id_verified_at, license_verified_at, passport_verified_at').eq('id', userId).single(),
      ]
      if (bookingId) {
        promises.push(supabase.from('bookings').select('id, start_date, end_date, motorcycles!moto_id(license_required, license_groups)').eq('id', bookingId).single())
      }
      const [docsRes, profRes, bkRes] = await Promise.all(promises)
      setVerificationDocs(docsRes.data || [])
      setProfile(profRes.data || null)
      setVs(await bookingDocsVerdict(docsRes.data || [], profRes.data || { id: userId }, bkRes?.data || (bookingId ? { id: bookingId } : null)))
    } catch {}
    setLoading(false)
  }

  if (!userId) return null
  if (loading || !vs) {
    return (
      <Card>
        <div className="text-sm" style={{ color: '#5a6b63' }}>{loading ? 'Načítám stav dokladů…' : 'Stav dokladů se nepodařilo načíst.'}</div>
      </Card>
    )
  }

  // Dětská motorka — doklady nepotřeba
  if (vs.isChildMoto) {
    return (
      <Card>
        <div className="flex items-center justify-between gap-3 mb-3 flex-wrap">
          <h3 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>
            Doklady totožnosti zákazníka
          </h3>
        </div>
        <div className="p-3 rounded-lg" style={{ background: '#dcfce7', border: '1px solid #86efac' }}>
          <div className="flex items-center gap-2 flex-wrap">
            <span style={{ fontSize: 16 }}>🧒</span>
            <span className="text-sm font-bold" style={{ color: '#1a8a18' }}>
              Dětská motorka — doklady nepotřeba, kódy k boxu uvolněny automaticky
            </span>
          </div>
          <div className="text-xs mt-2" style={{ color: '#1a2e22' }}>
            Tato motorka má <code>license_required = 'N'</code>, takže pro její zapůjčení nejsou potřeba OP/pas ani ŘP.
            Pokud si stejný zákazník později rezervuje motorku vyžadující ŘP, systém ho standardně vyzve k nahrání dokladů.
          </div>
        </div>
      </Card>
    )
  }

  const {
    licensePhotos: licenseDocs, idCardPhotos: idCardDocs, passportPhotos: passportDocs,
    hasLicense, hasIdentity, allOk, licFront, licBack, idFront, idBack, passportOk,
    licenseOcrVerified, idOcrVerified, licenseTypedOnly, identityTypedOnly,
  } = vs
  const missing = Array.isArray(vs.missing) ? vs.missing : []
  const licPart = licFront || licBack
  const idPart = idFront || idBack
  const anyManual = verificationDocs.some(d => d?.metadata?.mindee_status === 'failed')

  const okCount = verificationDocs.filter(d => d?.metadata?.mindee_status === 'ok').length
  const failCount = verificationDocs.filter(d => d?.metadata?.mindee_status === 'failed').length
  const total = verificationDocs.length

  return (
    <Card>
      <div className="flex items-center justify-between gap-3 mb-3 flex-wrap">
        <h3 className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>
          Doklady totožnosti zákazníka
        </h3>
        <Link
          to={`/zakaznici/${userId}`}
          className="rounded-btn text-sm font-extrabold uppercase tracking-wide cursor-pointer"
          style={{ padding: '6px 14px', background: '#74FB71', color: '#1a2e22', textDecoration: 'none' }}
        >
          Spravovat doklady →
        </Link>
      </div>

      <div className="p-3 rounded-lg mb-3" style={{ background: allOk ? '#dcfce7' : '#fef3c7', border: `1px solid ${allOk ? '#86efac' : '#fcd34d'}` }}>
        <div className="flex items-center gap-2 flex-wrap">
          <span style={{ fontSize: 16 }}>{allOk ? '✅' : '⚠️'}</span>
          <span className="text-sm font-bold" style={{ color: allOk ? '#1a8a18' : '#b45309' }}>
            {allOk ? 'Doklady ověřeny — kódy k boxu mohou být uvolněny' : 'Doklady neúplné — kódy k boxu NELZE uvolnit'}
          </span>
          <Badge
            label={hasLicense ? 'ŘP líc + rub nahrán' : licPart ? `ŘP: líc ${licFront ? '✓' : '✗'} · rub ${licBack ? '✓' : '✗'}` : licenseOcrVerified ? 'ŘP jen OCR — chybí fotky' : licenseTypedOnly ? 'ŘP zadán ručně — neověřen' : 'ŘP chybí'}
            color={hasLicense ? '#1a8a18' : (licPart || licenseTypedOnly) ? '#b45309' : '#dc2626'} bg={hasLicense ? '#dcfce7' : (licPart || licenseTypedOnly) ? '#fef3c7' : '#fee2e2'} />
          <Badge
            label={hasIdentity ? (passportOk ? 'Pas nahrán' : 'OP líc + rub nahrán') : idPart ? `OP: líc ${idFront ? '✓' : '✗'} · rub ${idBack ? '✓' : '✗'}` : idOcrVerified ? 'Doklad totožnosti jen OCR — chybí fotky' : identityTypedOnly ? 'Doklad zadán ručně — neověřen' : 'OP/Pas chybí'}
            color={hasIdentity ? '#1a8a18' : (idPart || identityTypedOnly) ? '#b45309' : '#dc2626'} bg={hasIdentity ? '#dcfce7' : (idPart || identityTypedOnly) ? '#fef3c7' : '#fee2e2'} />
        </div>
        {!allOk && missing.length > 0 && (
          <ul className="text-xs mt-2 space-y-0.5" style={{ color: '#92400e' }}>
            {missing.map(m => <li key={m}>• {m}</li>)}
          </ul>
        )}
        {(licenseOcrVerified || idOcrVerified) && (!hasLicense || !hasIdentity) && (
          <div className="text-xs mt-2" style={{ color: '#1a2e22' }}>
            Čísla dokladů přečtená přes OCR fotky NENAHRAZUJÍ — pro kódy k boxu je potřeba OP (líc + rub) nebo pas a ŘP (líc + rub).
          </div>
        )}
        {(licenseTypedOnly || identityTypedOnly) && (
          <div className="text-xs mt-2 font-bold" style={{ color: '#b45309' }}>
            ⚠️ Čísla dokladů jsou zadaná jen ručně — NENÍ nahraná fotka. Pro uvolnění kódů je potřeba nahrát fotky dokladů (OP líc + rub nebo pas, ŘP líc + rub).
          </div>
        )}
        {vs.source === 'client' && (
          <div className="text-xs mt-2" style={{ color: '#5a6b63' }}>Kontrola na serveru nedostupná — stav spočítán ve Velíně.</div>
        )}
      </div>

      {anyManual && (
        <div className="p-2 mb-3 rounded-lg text-sm" style={{ background: '#fef3c7', border: '1px solid #fcd34d', color: '#92400e' }}>
          ⚠️ Některé fotky byly nahrány ručně (Mindee OCR selhal) — zkontrolujte je v detailu zákazníka.
        </div>
      )}

      <div className="space-y-1">
        {licenseDocs.length > 0
          ? <SideStatus docs={licenseDocs} label="Řidičský průkaz" />
          : licenseOcrVerified
            ? <div className="text-xs" style={{ color: '#b45309' }}><strong>Řidičský průkaz:</strong> fotky nenahrány · číslo {profile?.license_number ? `(${profile.license_number}) ` : ''}jen přečtené přes OCR (nestačí)</div>
            : licenseTypedOnly
              ? <div className="text-xs" style={{ color: '#b45309' }}><strong>Řidičský průkaz:</strong> číslo {profile?.license_number ? `(${profile.license_number}) ` : ''}zadáno jen ručně — neověřeno (chybí OCR i fotka)</div>
              : <div className="text-xs" style={{ color: '#dc2626' }}><strong>Řidičský průkaz:</strong> nenahráno ani číslo v profilu</div>}
        {idCardDocs.length > 0 && <SideStatus docs={idCardDocs} label="Občanský průkaz" />}
        {passportDocs.length > 0 && <SideStatus docs={passportDocs} label="Pas" />}
        {idCardDocs.length === 0 && passportDocs.length === 0 && (
          idOcrVerified
            ? <div className="text-xs" style={{ color: '#b45309' }}><strong>OP / Pas:</strong> fotka nenahrána · číslo {profile?.id_number ? `(${profile.id_number}) ` : ''}jen přečtené přes OCR (nestačí)</div>
            : identityTypedOnly
              ? <div className="text-xs" style={{ color: '#b45309' }}><strong>OP / Pas:</strong> číslo {profile?.id_number ? `(${profile.id_number}) ` : ''}zadáno jen ručně — neověřeno (chybí OCR i fotka)</div>
              : <div className="text-xs" style={{ color: '#dc2626' }}><strong>OP / Pas:</strong> nenahráno ani číslo v profilu</div>
        )}
      </div>

      {total > 0 && (
        <div className="text-xs mt-2" style={{ color: '#5a6b63' }}>
          Celkem skenů: <strong>{total}</strong>
          {' '}• Mindee OK: <strong style={{ color: okCount > 0 ? '#1a8a18' : '#5a6b63' }}>{okCount}</strong>
          {' '}• Manuálně: <strong style={{ color: failCount > 0 ? '#b45309' : '#5a6b63' }}>{failCount}</strong>
        </div>
      )}
    </Card>
  )
}
