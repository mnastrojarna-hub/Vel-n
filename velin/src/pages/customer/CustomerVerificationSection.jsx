import { useState } from 'react'
import Card from '../../components/ui/Card'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import { supabase } from '../../lib/supabase'

function VerificationDocBadge({ doc }) {
  const status = doc?.metadata?.mindee_status
  if (status === 'ok') return <Badge label="Mindee OK" color="#1a8a18" bg="#dcfce7" />
  if (status === 'failed') return <Badge label="Ručně — zkontrolovat" color="#b45309" bg="#fef3c7" />
  // legacy bez metadata
  return <Badge label="Foto v archivu" color="#1a2e22" bg="#f1faf7" />
}

function VerificationDocsList({ docs }) {
  const [previewUrl, setPreviewUrl] = useState(null)
  const [previewDoc, setPreviewDoc] = useState(null)
  if (!docs || !docs.length) return null

  async function openPreview(doc) {
    const path = doc.file_path
    if (!path) { alert('Tento záznam nemá uloženou fotku.'); return }
    try {
      const { data, error } = await supabase.storage.from('documents').createSignedUrl(path, 60 * 5)
      if (error) throw error
      setPreviewUrl(data.signedUrl); setPreviewDoc(doc)
    } catch (e) { alert('Náhled selhal: ' + e.message) }
  }

  return (
    <div className="mt-3 space-y-2">
      {docs.map(d => (
        <div key={d.id} className="flex items-center gap-2 p-2 rounded-lg" style={{ background: '#fff', border: '1px solid #d4e8e0' }}>
          <span style={{ fontSize: 16 }}>{d.type === 'drivers_license' ? '🪪' : (d.type === 'passport' ? '🛂' : '🪪')}</span>
          <div className="flex-1 min-w-0">
            <div className="text-sm font-bold" style={{ color: '#1a2e22' }}>{d.name || d.type}</div>
            <div className="text-xs" style={{ color: '#5a6b63' }}>{d.created_at?.slice(0, 10)}</div>
          </div>
          <VerificationDocBadge doc={d} />
          <button onClick={() => openPreview(d)} className="text-sm font-bold cursor-pointer"
            style={{ color: '#2563eb', background: 'none', border: 'none' }}>Náhled fotky</button>
        </div>
      ))}
      {previewUrl && (
        <Modal open title={previewDoc?.name || 'Foto dokladu'} onClose={() => { setPreviewUrl(null); setPreviewDoc(null) }} wide>
          <div className="flex justify-center" style={{ background: '#0f1a14', padding: 12, borderRadius: 8 }}>
            <img src={previewUrl} alt="doklad" style={{ maxWidth: '100%', maxHeight: 600, borderRadius: 4 }} />
          </div>
          <div className="flex justify-end mt-3">
            <Button onClick={() => { setPreviewUrl(null); setPreviewDoc(null) }}>Zavřít</Button>
          </div>
        </Modal>
      )}
    </div>
  )
}

export default function CustomerVerificationSection({ vs, profile, verificationDocs }) {
  const licenseDocs = (verificationDocs || []).filter(d => d.type === 'drivers_license' || d.type === 'license_photo')
  const idDocs = (verificationDocs || []).filter(d => d.type === 'id_card' || d.type === 'passport' || d.type === 'id_photo')
  const anyManual = (verificationDocs || []).some(d => d.metadata?.mindee_status === 'failed')

  return (
    <Card>
      <h3 className="text-sm font-extrabold uppercase tracking-widest mb-4" style={{ color: '#1a2e22' }}>Overeni dokladu zakaznika</h3>
      {anyManual && (
        <div className="p-2 mb-3 rounded-lg" style={{ background: '#fef3c7', border: '1px solid #fcd34d', color: '#92400e', fontSize: 13 }}>
          ⚠️ Některé doklady byly nahrané ručně (Mindee OCR selhal) — zkontrolujte fotky a údaje v profilu.
        </div>
      )}
      <div className="space-y-3 mb-4">
        <div className="p-4 rounded-lg" style={{ background: '#f1faf7' }}>
          <div className="flex items-center gap-2 mb-2">
            <span style={{ fontSize: 14 }}>{vs.hasLicense ? '✅' : '❌'}</span>
            <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Ridicsky prukaz (RP)</span>
            <Badge label={vs.hasLicense ? 'Vyfoceno' : 'Chybi'} color={vs.hasLicense ? '#1a8a18' : '#dc2626'} bg={vs.hasLicense ? '#dcfce7' : '#fee2e2'} />
          </div>
          <div className="flex flex-wrap gap-2">
            <Badge
              label={vs.licenseValid ? `Platny do ${profile?.license_expiry}` : profile?.license_expiry ? `Expirovany (${profile.license_expiry})` : 'Platnost nevyplnena'}
              color={vs.licenseValid ? '#1a8a18' : '#dc2626'}
              bg={vs.licenseValid ? '#dcfce7' : '#fee2e2'}
            />
            <Badge
              label={vs.licenseGroupFilled ? `Skupiny: ${(profile?.license_group || []).join(', ')}` : 'Skupiny nevyplneny'}
              color={vs.licenseGroupFilled ? '#1a8a18' : '#b45309'}
              bg={vs.licenseGroupFilled ? '#dcfce7' : '#fef3c7'}
            />
            {vs.licenseGroupFilled && profile?.license_group && (
              <Badge
                label={profile.license_group.some(g => ['A', 'A2', 'A1', 'AM'].includes(g)) ? 'Skupina pro motorky OK' : 'Chybi skupina A/A2/A1'}
                color={profile.license_group.some(g => ['A', 'A2', 'A1', 'AM'].includes(g)) ? '#1a8a18' : '#dc2626'}
                bg={profile.license_group.some(g => ['A', 'A2', 'A1', 'AM'].includes(g)) ? '#dcfce7' : '#fee2e2'}
              />
            )}
          </div>
          <VerificationDocsList docs={licenseDocs} />
        </div>

        <div className="p-4 rounded-lg" style={{ background: '#f1faf7' }}>
          <div className="flex items-center gap-2 mb-2">
            <span style={{ fontSize: 14 }}>{vs.hasIdentity ? '✅' : '❌'}</span>
            <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Doklad totoznosti (OP nebo pas)</span>
            <Badge label={vs.hasIdentity ? 'Vyfoceno' : 'Chybi'} color={vs.hasIdentity ? '#1a8a18' : '#dc2626'} bg={vs.hasIdentity ? '#dcfce7' : '#fee2e2'} />
          </div>
          {vs.hasIdentity && (
            <div className="flex gap-2">
              {vs.hasIdCard && <Badge label="Obcansky prukaz" color="#1a8a18" bg="#dcfce7" />}
              {vs.hasPassport && <Badge label="Cestovni pas" color="#1a8a18" bg="#dcfce7" />}
            </div>
          )}
          <VerificationDocsList docs={idDocs} />
        </div>
      </div>

      <div className="p-3 rounded-lg" style={{ background: vs.allOk ? '#dcfce7' : '#fef3c7', border: `1px solid ${vs.allOk ? '#86efac' : '#fcd34d'}` }}>
        <div className="flex items-center gap-2">
          <span style={{ fontSize: 16 }}>{vs.allOk ? '✅' : '⚠️'}</span>
          <span className="text-sm font-bold" style={{ color: vs.allOk ? '#1a8a18' : '#b45309' }}>
            {vs.allOk ? 'Vsechny doklady overeny — kody k boxu mohou byt uvolneny' : 'Doklady neuplne — kody k boxu NELZE uvolnit'}
          </span>
        </div>
        {!vs.allOk && (
          <ul className="mt-2 space-y-1" style={{ fontSize: 12, color: '#92400e' }}>
            {!vs.hasLicense && <li>• Chybi vyfoceny ridicsky prukaz</li>}
            {vs.hasLicense && !vs.licenseValid && <li>• Ridicsky prukaz je neplatny nebo expirovany</li>}
            {vs.hasLicense && !vs.licenseGroupFilled && <li>• Ridicske skupiny nejsou vyplneny v profilu</li>}
            {vs.hasLicense && vs.licenseGroupFilled && !profile?.license_group?.some(g => ['A', 'A2', 'A1', 'AM'].includes(g)) && <li>• Zakaznik nema ridicskou skupinu pro motorky (A/A2/A1/AM)</li>}
            {!vs.hasIdentity && <li>• Chybi vyfoceny doklad totoznosti (OP nebo pas)</li>}
          </ul>
        )}
      </div>
    </Card>
  )
}
