import { useState } from 'react'
import Card from '../../components/ui/Card'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import { supabase } from '../../lib/supabase'
import AdminDocUploadModal from './AdminDocUploadModal'

const SIDE_LABEL = { front: 'Líc', back: 'Rub' }

const OCR_FIELD_LABELS = {
  document_number: 'Číslo dokladu',
  given_names: 'Jméno',
  surname: 'Příjmení',
  birth_date: 'Datum narození',
  expiry_date: 'Platnost do',
  issue_date: 'Datum vydání',
  nationality: 'Národnost',
  sex: 'Pohlaví',
  mrz: 'MRZ',
  categories: 'Skupiny',
  authority: 'Vydáno',
  address: 'Adresa',
}

function MindeeStatusBadge({ status }) {
  if (status === 'ok') return <Badge label="Mindee sken OK" color="#1a8a18" bg="#dcfce7" />
  if (status === 'failed') return <Badge label="Mindee selhal — manuální" color="#b45309" bg="#fef3c7" />
  return <Badge label="Foto v archivu" color="#1a2e22" bg="#f1faf7" />
}

function OcrFieldsSummary({ fields }) {
  if (!fields || typeof fields !== 'object') return null
  const entries = Object.entries(fields).filter(([_, v]) => v != null && v !== '')
  if (!entries.length) return null
  return (
    <div className="mt-2 p-2 rounded text-xs" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
      <div className="font-bold mb-1" style={{ color: '#1a2e22' }}>Naskenované údaje:</div>
      <div className="grid gap-x-3 gap-y-0.5" style={{ gridTemplateColumns: '1fr 1fr', color: '#1a2e22' }}>
        {entries.map(([k, v]) => (
          <div key={k} className="truncate">
            <span style={{ color: '#5a6b63' }}>{OCR_FIELD_LABELS[k] || k}:</span>{' '}
            <span className="font-medium">{typeof v === 'object' ? JSON.stringify(v) : String(v)}</span>
          </div>
        ))}
      </div>
    </div>
  )
}

function DocPageRow({ doc, onPreview, onDelete }) {
  const status = doc?.metadata?.mindee_status
  const captured = doc?.metadata?.captured_at || doc?.created_at
  const ocr = doc?.metadata?.ocr_fields
  const icon = status === 'ok' ? '✅' : status === 'failed' ? '⚠️' : '📷'
  return (
    <div className="p-2 rounded-lg" style={{ background: '#fff', border: status === 'failed' ? '1px solid #fcd34d' : '1px solid #d4e8e0' }}>
      <div className="flex items-center gap-2 flex-wrap">
        <span style={{ fontSize: 16 }}>{icon}</span>
        <div className="flex-1 min-w-0">
          <div className="text-sm font-bold truncate" style={{ color: '#1a2e22' }}>
            {doc.name || doc.file_name || doc.type}
          </div>
          <div className="text-xs" style={{ color: '#5a6b63' }}>
            {captured ? new Date(captured).toLocaleString('cs-CZ') : '—'}
          </div>
        </div>
        <MindeeStatusBadge status={status} />
        {doc.file_path && (
          <button onClick={() => onPreview(doc)} className="text-sm font-bold cursor-pointer"
            style={{ color: '#2563eb', background: 'none', border: 'none' }}>Náhled</button>
        )}
        <button onClick={() => onDelete(doc)} className="text-sm font-bold cursor-pointer"
          style={{ color: '#dc2626', background: 'none', border: 'none' }}>Smazat</button>
      </div>
      {status === 'ok' && <OcrFieldsSummary fields={ocr} />}
      {status === 'failed' && (
        <div className="mt-2 text-xs italic" style={{ color: '#92400e' }}>
          Mindee OCR selhal — fotka je uložená v archivu, údaje doplňte ručně do profilu zákazníka.
        </div>
      )}
    </div>
  )
}

function groupDocsBySide(docs) {
  const out = { front: null, back: null, other: [] }
  // newest first (callers should pre-sort DESC); pick the most recent per slot
  for (const d of docs) {
    const side = d?.metadata?.side
    if (side === 'front' && !out.front) out.front = d
    else if (side === 'back' && !out.back) out.back = d
    else out.other.push(d)
  }
  return out
}

function ScanCounts({ docs }) {
  if (!docs || !docs.length) return null
  const ok = docs.filter(d => d?.metadata?.mindee_status === 'ok').length
  const fail = docs.filter(d => d?.metadata?.mindee_status === 'failed').length
  const legacy = docs.length - ok - fail
  return (
    <div className="text-xs mb-2" style={{ color: '#1a2e22' }}>
      Celkem skenů: <strong>{docs.length}</strong>
      {' '}• Mindee OK: <strong style={{ color: ok > 0 ? '#1a8a18' : '#1a2e22' }}>{ok}</strong>
      {' '}• Manuálně (Mindee selhal): <strong style={{ color: fail > 0 ? '#b45309' : '#1a2e22' }}>{fail}</strong>
      {legacy > 0 && <> • Legacy: <strong>{legacy}</strong></>}
    </div>
  )
}

function DocSlots({ docs, requireBothSides, onPreview, onDelete, emptyNote }) {
  if (!docs || !docs.length) {
    return (
      <div className="text-xs italic mt-2" style={{ color: '#5a6b63' }}>
        {emptyNote || 'Žádné nahrané fotky.'}
      </div>
    )
  }
  const grouped = groupDocsBySide(docs)
  return (
    <div className="space-y-2 mt-2">
      <ScanCounts docs={docs} />
      {requireBothSides ? (
        <>
          <div className="text-xs font-extrabold uppercase tracking-wide" style={{ color: '#5a6b63' }}>{SIDE_LABEL.front}</div>
          {grouped.front
            ? <DocPageRow doc={grouped.front} onPreview={onPreview} onDelete={onDelete} />
            : <div className="p-2 rounded-lg text-xs" style={{ background: '#fef3c7', color: '#92400e', border: '1px solid #fcd34d' }}>⚠️ Chybí líc</div>}
          <div className="text-xs font-extrabold uppercase tracking-wide" style={{ color: '#5a6b63' }}>{SIDE_LABEL.back}</div>
          {grouped.back
            ? <DocPageRow doc={grouped.back} onPreview={onPreview} onDelete={onDelete} />
            : <div className="p-2 rounded-lg text-xs" style={{ background: '#fef3c7', color: '#92400e', border: '1px solid #fcd34d' }}>⚠️ Chybí rub</div>}
          {grouped.other.length > 0 && (
            <>
              <div className="text-xs font-extrabold uppercase tracking-wide pt-1" style={{ color: '#5a6b63' }}>Další / starší fotky</div>
              {grouped.other.map(d => <DocPageRow key={d.id} doc={d} onPreview={onPreview} onDelete={onDelete} />)}
            </>
          )}
        </>
      ) : (
        [grouped.front, grouped.back, ...grouped.other]
          .filter(Boolean)
          .map(d => <DocPageRow key={d.id} doc={d} onPreview={onPreview} onDelete={onDelete} />)
      )}
    </div>
  )
}

function formatBookingRange(b) {
  const s = b?.start_date ? new Date(b.start_date).toLocaleDateString('cs-CZ') : '—'
  const e = b?.end_date ? new Date(b.end_date).toLocaleDateString('cs-CZ') : '—'
  return `${s} – ${e}`
}

function BookingContextBanner({ upcomingBookings, allChildOnly, hasAdultBooking, noUpcoming }) {
  if (noUpcoming) {
    return (
      <div className="p-3 mb-3 rounded-lg text-xs" style={{ background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
        ℹ️ Zákazník nemá žádnou aktivní ani nadcházející rezervaci. Doklady ŘP + OP/Pas budou potřeba u motorek vyžadujících ŘP. Pro dětské motorky (license_required = N) doklady nepotřeba.
      </div>
    )
  }
  return (
    <div className="p-3 mb-3 rounded-lg text-xs" style={{ background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}>
      <div className="font-bold mb-1">Aktivní / nadcházející rezervace ({upcomingBookings.length}):</div>
      <ul className="space-y-0.5">
        {upcomingBookings.map(b => {
          const isChild = String(b.motorcycles?.license_required || '').toUpperCase() === 'N'
          return (
            <li key={b.id}>
              {isChild ? '🧒' : '🏍️'} {b.motorcycles?.model || 'Motorka'} · {formatBookingRange(b)} · {' '}
              <span style={{ color: isChild ? '#1a8a18' : '#1a2e22' }}>
                {isChild ? 'dětská — bez dokladů' : 'vyžaduje ŘP + OP/Pas'}
              </span>
            </li>
          )
        })}
      </ul>
      {allChildOnly && (
        <div className="mt-2" style={{ color: '#1a8a18' }}>
          🧒 Pouze dětské motorky — kódy k boxu se uvolnily automaticky bez nutnosti dokladů.
        </div>
      )}
      {hasAdultBooking && (
        <div className="mt-2" style={{ color: '#b45309' }}>
          🏍️ Pro dospělou motorku je potřeba ověřený ŘP + OP/Pas, jinak kódy NELZE uvolnit.
        </div>
      )}
    </div>
  )
}

export default function CustomerVerificationSection({ vs, profile, verificationDocs, upcomingBookings = [], hasAdultBooking = false, allChildOnly = false, noUpcoming = false, onChanged }) {
  // Pro dětskou-only rezervaci se ŘP zobrazuje jen informativně — backend kódy stejně uvolní
  const licenseOptional = allChildOnly && !vs.hasLicense
  // Skupiny A/A2/A1 jsou irelevantní, když není potřeba ŘP
  const showAdultGroupCheck = !allChildOnly && vs.licenseGroupFilled && profile?.license_group
  const [previewUrl, setPreviewUrl] = useState(null)
  const [previewDoc, setPreviewDoc] = useState(null)
  const [confirmDelete, setConfirmDelete] = useState(null)
  const [deleting, setDeleting] = useState(false)
  const [error, setError] = useState(null)
  const [showUpload, setShowUpload] = useState(false)

  const licenseDocs = (verificationDocs || []).filter(d => d.type === 'drivers_license' || d.type === 'license_photo')
  const idCardDocs = (verificationDocs || []).filter(d => d.type === 'id_card' || d.type === 'id_photo')
  const passportDocs = (verificationDocs || []).filter(d => d.type === 'passport')
  const anyManual = (verificationDocs || []).some(d => d.metadata?.mindee_status === 'failed')

  async function openPreview(doc) {
    setError(null)
    if (!doc.file_path) { setError('Tento záznam nemá uloženou fotku.'); return }
    try {
      const { data, error: e } = await supabase.storage.from('documents').createSignedUrl(doc.file_path, 60 * 5)
      if (e) throw e
      setPreviewUrl(data.signedUrl); setPreviewDoc(doc)
    } catch (e) { setError('Náhled selhal: ' + e.message) }
  }

  async function performDelete(doc) {
    setDeleting(true); setError(null)
    try {
      if (doc.file_path) {
        try { await supabase.storage.from('documents').remove([doc.file_path]) } catch {}
      }
      const { error: e } = await supabase.from('documents').delete().eq('id', doc.id)
      if (e) throw e
      setConfirmDelete(null)
      if (onChanged) await onChanged()
    } catch (e) {
      setError('Smazání selhalo: ' + e.message)
    }
    setDeleting(false)
  }

  return (
    <Card>
      <h3 className="text-sm font-extrabold uppercase tracking-widest mb-4" style={{ color: '#1a2e22' }}>Overeni dokladu zakaznika</h3>

      {error && <div className="p-2 mb-3 rounded-lg" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      <BookingContextBanner
        upcomingBookings={upcomingBookings}
        allChildOnly={allChildOnly}
        hasAdultBooking={hasAdultBooking}
        noUpcoming={noUpcoming}
      />

      {/* Admin: dodatečné nahrání dokladů — jen když zákazník nemá ověřené doklady */}
      {!vs.allOk && profile?.id && (
        <div className="mb-3 flex items-center gap-3 flex-wrap">
          <Button green onClick={() => setShowUpload(true)}>+ Nahrát doklady</Button>
          <span className="text-xs" style={{ color: '#5a6b63' }}>
            Vyfoťte nebo nahrajte doklad za zákazníka — proběhne OCR a kódy k boxu se uvolní.
          </span>
        </div>
      )}

      {showUpload && profile?.id && (
        <AdminDocUploadModal
          userId={profile.id}
          bookingId={null}
          onClose={() => setShowUpload(false)}
          onUploaded={onChanged}
        />
      )}

      {anyManual && (
        <div className="p-2 mb-3 rounded-lg" style={{ background: '#fef3c7', border: '1px solid #fcd34d', color: '#92400e', fontSize: 13 }}>
          ⚠️ Některé doklady byly nahrané ručně (Mindee OCR selhal) — zkontrolujte fotky a údaje v profilu.
        </div>
      )}

      <div className="space-y-3 mb-4">
        {/* Řidičský průkaz */}
        <div className="p-4 rounded-lg" style={{ background: licenseOptional ? '#f9fafb' : '#f1faf7' }}>
          <div className="flex items-center gap-2 mb-2 flex-wrap">
            <span style={{ fontSize: 14 }}>{licenseOptional ? '➖' : vs.hasLicense ? '✅' : vs.licenseTypedOnly ? '⚠️' : '❌'}</span>
            <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Ridicsky prukaz (RP)</span>
            {licenseOptional ? (
              <Badge label="Pro dětskou motorku není potřeba" color="#1a8a18" bg="#dcfce7" />
            ) : (
              <Badge
                label={vs.hasLicensePhoto ? 'Vyfoceno' : vs.licenseOcrVerified ? 'Overeno pres OCR' : vs.licenseTypedOnly ? 'Zadano rucne — neovereno' : 'Chybi'}
                color={vs.hasLicense ? '#1a8a18' : vs.licenseTypedOnly ? '#b45309' : '#dc2626'}
                bg={vs.hasLicense ? '#dcfce7' : vs.licenseTypedOnly ? '#fef3c7' : '#fee2e2'}
              />
            )}
          </div>
          {!licenseOptional && (
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
              {showAdultGroupCheck && (
                <Badge
                  label={profile.license_group.some(g => ['A', 'A2', 'A1', 'AM'].includes(g)) ? 'Skupina pro motorky OK' : 'Chybi skupina A/A2/A1'}
                  color={profile.license_group.some(g => ['A', 'A2', 'A1', 'AM'].includes(g)) ? '#1a8a18' : '#dc2626'}
                  bg={profile.license_group.some(g => ['A', 'A2', 'A1', 'AM'].includes(g)) ? '#dcfce7' : '#fee2e2'}
                />
              )}
            </div>
          )}
          <DocSlots docs={licenseDocs} requireBothSides
            onPreview={openPreview} onDelete={d => setConfirmDelete(d)}
            emptyNote={licenseOptional
              ? 'Fotka ŘP nenahrána — pro aktuální dětskou rezervaci není potřeba. Pokud si zákazník později rezervuje dospělou motorku, bude nutné ŘP doplnit.'
              : vs.licenseDataOnly
                ? `Fotka ŘP nenahrána (volitelná). Číslo ŘP ${profile?.license_number ? `(${profile.license_number}) ` : ''}je ověřené přes OCR a uložené v profilu — odbavení i kódy k boxu fungují.`
                : vs.licenseTypedOnly
                  ? `⚠️ Číslo ŘP ${profile?.license_number ? `(${profile.license_number}) ` : ''}je zadané jen ručně ve formuláři — NENÍ ověřené přes OCR ani nahraná fotka. Doklad je potřeba naskenovat (Mindee) nebo nahrát fotku.`
                  : 'Žádné nahrané fotky.'} />
        </div>

        {/* Doklad totoznosti */}
        <div className="p-4 rounded-lg" style={{ background: '#f1faf7' }}>
          <div className="flex items-center gap-2 mb-2 flex-wrap">
            <span style={{ fontSize: 14 }}>{vs.hasIdentity ? '✅' : vs.identityTypedOnly ? '⚠️' : '❌'}</span>
            <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Doklad totoznosti (OP nebo pas)</span>
            <Badge
              label={(vs.hasIdCard || vs.hasPassport) ? 'Vyfoceno' : vs.idOcrVerified ? 'Overeno pres OCR' : vs.identityTypedOnly ? 'Zadano rucne — neovereno' : 'Chybi'}
              color={vs.hasIdentity ? '#1a8a18' : vs.identityTypedOnly ? '#b45309' : '#dc2626'}
              bg={vs.hasIdentity ? '#dcfce7' : vs.identityTypedOnly ? '#fef3c7' : '#fee2e2'}
            />
            {vs.hasIdCard && <Badge label="Obcansky prukaz" color="#1a8a18" bg="#dcfce7" />}
            {vs.hasPassport && <Badge label="Cestovni pas" color="#1a8a18" bg="#dcfce7" />}
          </div>

          {idCardDocs.length > 0 && (
            <div className="mt-3">
              <div className="text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Občanský průkaz (líc + rub)</div>
              <DocSlots docs={idCardDocs} requireBothSides
                onPreview={openPreview} onDelete={d => setConfirmDelete(d)} />
            </div>
          )}

          {passportDocs.length > 0 && (
            <div className="mt-3">
              <div className="text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Cestovní pas</div>
              <DocSlots docs={passportDocs} requireBothSides={false}
                onPreview={openPreview} onDelete={d => setConfirmDelete(d)} />
            </div>
          )}

          {idCardDocs.length === 0 && passportDocs.length === 0 && (
            vs.idOcrVerified ? (
              <div className="mt-3 p-2 rounded-lg text-xs" style={{ background: '#f1faf7', color: '#1a2e22', border: '1px solid #d4e8e0' }}>
                ✅ Doklad totožnosti je ověřený přes OCR — číslo {profile?.id_number ? `(${profile.id_number}) ` : ''}je uložené v profilu. Fotka nahraná není (volitelná) — odbavení i kódy k boxu fungují.
              </div>
            ) : vs.identityTypedOnly ? (
              <div className="mt-3 p-2 rounded-lg text-xs" style={{ background: '#fef3c7', color: '#92400e', border: '1px solid #fcd34d' }}>
                ⚠️ Číslo dokladu {profile?.id_number ? `(${profile.id_number}) ` : ''}je zadané jen ručně ve formuláři — NENÍ ověřené přes OCR ani nahraná fotka. Zákazník musí naskenovat (Mindee) nebo nahrát OP (líc + rub) nebo pas.
              </div>
            ) : (
              <div className="mt-3 p-2 rounded-lg text-xs" style={{ background: '#fef3c7', color: '#92400e', border: '1px solid #fcd34d' }}>
                ⚠️ Žádný sken dokladu totožnosti ani číslo dokladu v profilu — zákazník musí nahrát OP (líc + rub) nebo pas.
              </div>
            )
          )}
        </div>
      </div>

      {/* Kontextový status panel — reaguje na typ rezervace */}
      {allChildOnly ? (
        <div className="p-3 rounded-lg" style={{ background: '#dcfce7', border: '1px solid #86efac' }}>
          <div className="flex items-center gap-2 flex-wrap">
            <span style={{ fontSize: 16 }}>🧒</span>
            <span className="text-sm font-bold" style={{ color: '#1a8a18' }}>
              Aktuální rezervace pouze na dětskou motorku — kódy k boxu byly uvolněny automaticky
            </span>
          </div>
          <div className="text-xs mt-2" style={{ color: '#1a2e22' }}>
            Pro dětskou motorku (<code>license_required = N</code>) není potřeba ŘP ani doklad totožnosti — backend kódy uvolnil bez kontroly dokladů. Pokud si zákazník později rezervuje dospělou motorku, doklady bude muset doplnit.
          </div>
        </div>
      ) : noUpcoming ? (
        <div className="p-3 rounded-lg" style={{ background: '#f1faf7', border: '1px solid #d4e8e0' }}>
          <div className="flex items-center gap-2 flex-wrap">
            <span style={{ fontSize: 16 }}>{vs.allOk ? '✅' : 'ℹ️'}</span>
            <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>
              {vs.allOk
                ? 'Doklady ověřeny — zákazník je připraven na jakoukoliv budoucí rezervaci'
                : 'Žádná aktuální rezervace — kódy k boxu se nyní neřeší'}
            </span>
          </div>
          {!vs.allOk && (
            <div className="text-xs mt-2" style={{ color: '#1a2e22' }}>
              Pro budoucí rezervaci dospělé motorky bude potřeba nahrát: ŘP (s platnou skupinou A/A2/A1/AM) + OP nebo pas. Pro dětské motorky doklady nepotřeba.
            </div>
          )}
        </div>
      ) : (
        <div className="p-3 rounded-lg" style={{ background: vs.allOk ? '#dcfce7' : '#fef3c7', border: `1px solid ${vs.allOk ? '#86efac' : '#fcd34d'}` }}>
          <div className="flex items-center gap-2">
            <span style={{ fontSize: 16 }}>{vs.allOk ? '✅' : '⚠️'}</span>
            <span className="text-sm font-bold" style={{ color: vs.allOk ? '#1a8a18' : '#b45309' }}>
              {vs.allOk ? 'Vsechny doklady overeny — kody k boxu mohou byt uvolneny' : 'Doklady neuplne — kody k boxu NELZE uvolnit'}
            </span>
          </div>
          {!vs.allOk && (
            <ul className="mt-2 space-y-1" style={{ fontSize: 12, color: '#92400e' }}>
              {!vs.hasLicense && (vs.licenseTypedOnly
                ? <li>• Ridicsky prukaz: cislo je zadane jen rucne (bez OCR skenu i fotky) — NENI overeno, kody nelze uvolnit</li>
                : <li>• Chybi ridicsky prukaz — neni nahrana fotka ani overene cislo RP (OCR) v profilu</li>)}
              {vs.hasLicense && !vs.licenseValid && <li>• Ridicsky prukaz je neplatny nebo expirovany (platnost neni vyplnena nebo uz uplynula)</li>}
              {vs.hasLicense && !vs.licenseGroupFilled && <li>• Ridicske skupiny nejsou vyplneny v profilu</li>}
              {vs.hasLicense && vs.licenseGroupFilled && !vs.hasMotoGroup && <li>• Zakaznik nema ridicskou skupinu pro motorky (A/A2/A1/AM)</li>}
              {!vs.hasIdentity && (vs.identityTypedOnly
                ? <li>• Doklad totoznosti: cislo je zadane jen rucne (bez OCR skenu i fotky) — NENI overeno, kody nelze uvolnit</li>
                : <li>• Chybi doklad totoznosti — neni nahrana fotka OP/pasu ani overene cislo (OCR) v profilu</li>)}
            </ul>
          )}
        </div>
      )}

      {previewUrl && (
        <Modal open title={previewDoc?.name || 'Foto dokladu'} onClose={() => { setPreviewUrl(null); setPreviewDoc(null) }} wide>
          <div className="flex justify-center" style={{ background: '#0f1a14', padding: 12, borderRadius: 8 }}>
            <img src={previewUrl} alt="doklad" style={{ maxWidth: '100%', maxHeight: 600, borderRadius: 4 }} />
          </div>
          {previewDoc?.metadata?.ocr_fields && (
            <div className="mt-3"><OcrFieldsSummary fields={previewDoc.metadata.ocr_fields} /></div>
          )}
          <div className="flex justify-between gap-3 mt-3">
            <Button onClick={() => { setConfirmDelete(previewDoc); setPreviewUrl(null); setPreviewDoc(null) }}
              style={{ background: '#fee2e2', color: '#dc2626' }}>Smazat fotku</Button>
            <Button onClick={() => { setPreviewUrl(null); setPreviewDoc(null) }}>Zavřít</Button>
          </div>
        </Modal>
      )}

      {confirmDelete && (
        <Modal open title="Smazat fotku dokladu?" onClose={() => !deleting && setConfirmDelete(null)}>
          <p className="text-sm mb-4" style={{ color: '#1a2e22' }}>
            Opravdu chcete trvale smazat nahranou fotku <strong>{confirmDelete.name || confirmDelete.file_name || confirmDelete.type}</strong>?
            Akce je nevratná a zákazník bude muset doklad nahrát znovu.
          </p>
          <div className="flex justify-end gap-2">
            <Button onClick={() => setConfirmDelete(null)} disabled={deleting}>Zrušit</Button>
            <Button onClick={() => performDelete(confirmDelete)} disabled={deleting}
              style={{ background: '#dc2626', color: '#fff' }}>
              {deleting ? 'Mažu…' : 'Smazat'}
            </Button>
          </div>
        </Modal>
      )}
    </Card>
  )
}
