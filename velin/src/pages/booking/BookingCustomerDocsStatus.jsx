import { useState, useEffect } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import Card from '../../components/ui/Card'
import Badge from '../../components/ui/Badge'

const VERIFICATION_TYPES = ['drivers_license', 'license_photo', 'id_card', 'id_photo', 'passport']

function MotoGroups(license_group) {
  return (license_group || []).some(g => ['A', 'A2', 'A1', 'AM'].includes(g))
}

function SideStatus({ docs, label }) {
  // docs is the subset for one document type — split into front/back
  const front = docs.find(d => d?.metadata?.side === 'front')
  const back = docs.find(d => d?.metadata?.side === 'back')
  const noSide = docs.filter(d => !d?.metadata?.side)
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
          {noSide.length > 0 && <span style={{ color: '#5a6b63' }}>+{noSide.length} bez označení strany</span>}
        </>
      )}
    </div>
  )
}

export default function BookingCustomerDocsStatus({ userId }) {
  const [loading, setLoading] = useState(true)
  const [profile, setProfile] = useState(null)
  const [verificationDocs, setVerificationDocs] = useState([])

  useEffect(() => { if (userId) loadStatus() }, [userId])

  async function loadStatus() {
    setLoading(true)
    try {
      const [docsRes, profRes] = await Promise.all([
        supabase.from('documents').select('id, type, file_path, metadata, created_at').eq('user_id', userId).in('type', VERIFICATION_TYPES).order('created_at', { ascending: false }),
        supabase.from('profiles').select('id, license_expiry, license_group').eq('id', userId).single(),
      ])
      setVerificationDocs(docsRes.data || [])
      setProfile(profRes.data || null)
    } catch {}
    setLoading(false)
  }

  if (!userId) return null
  if (loading) {
    return (
      <Card>
        <div className="text-sm" style={{ color: '#5a6b63' }}>Načítám stav dokladů…</div>
      </Card>
    )
  }

  const licenseDocs = verificationDocs.filter(d => d.type === 'drivers_license' || d.type === 'license_photo')
  const idCardDocs = verificationDocs.filter(d => d.type === 'id_card' || d.type === 'id_photo')
  const passportDocs = verificationDocs.filter(d => d.type === 'passport')
  const hasLicense = licenseDocs.length > 0
  const hasIdentity = idCardDocs.length > 0 || passportDocs.length > 0
  const licenseValid = profile?.license_expiry ? new Date(profile.license_expiry) > new Date() : false
  const licenseGroupFilled = profile?.license_group && profile.license_group.length > 0
  const hasMotoGroup = licenseGroupFilled && MotoGroups(profile.license_group)
  const allOk = hasLicense && hasIdentity && licenseValid && licenseGroupFilled && hasMotoGroup
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
          <Badge label={hasLicense ? 'ŘP nahrán' : 'ŘP chybí'} color={hasLicense ? '#1a8a18' : '#dc2626'} bg={hasLicense ? '#dcfce7' : '#fee2e2'} />
          <Badge label={hasIdentity ? 'Doklad totožnosti nahrán' : 'OP/Pas chybí'} color={hasIdentity ? '#1a8a18' : '#dc2626'} bg={hasIdentity ? '#dcfce7' : '#fee2e2'} />
        </div>
      </div>

      {anyManual && (
        <div className="p-2 mb-3 rounded-lg text-sm" style={{ background: '#fef3c7', border: '1px solid #fcd34d', color: '#92400e' }}>
          ⚠️ Některé fotky byly nahrány ručně (Mindee OCR selhal) — zkontrolujte je v detailu zákazníka.
        </div>
      )}

      <div className="space-y-1">
        <SideStatus docs={licenseDocs} label="Řidičský průkaz" />
        {idCardDocs.length > 0 && <SideStatus docs={idCardDocs} label="Občanský průkaz" />}
        {passportDocs.length > 0 && <SideStatus docs={passportDocs} label="Pas" />}
        {idCardDocs.length === 0 && passportDocs.length === 0 && (
          <div className="text-xs" style={{ color: '#dc2626' }}><strong>OP / Pas:</strong> nenahráno</div>
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
