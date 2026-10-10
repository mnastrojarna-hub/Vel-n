import { useState } from 'react'
import Card from '../../components/ui/Card'
import Badge from '../../components/ui/Badge'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import { supabase } from '../../lib/supabase'
import { docSide, isMarkerPath, fmtYmd, isChildMotoRow, hasMotoLicenseGroup } from '../../lib/docVerification'
import AdminDocUploadModal from './AdminDocUploadModal'
import { DocSlots, OcrFieldsSummary } from './CustomerDocSlots'

function formatBookingRange(b) {
  const s = b?.start_date ? new Date(b.start_date).toLocaleDateString('cs-CZ') : '—'
  const e = b?.end_date ? new Date(b.end_date).toLocaleDateString('cs-CZ') : '—'
  return `${s} – ${e}`
}

// Verdikt dokladů PER rezervace (backend get_docs_gate_checklist) — `verdicts` = Map booking_id → vs
function BookingContextBanner({ upcomingBookings, allChildOnly, hasAdultBooking, noUpcoming, verdicts }) {
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
          const v = verdicts?.get(b.id)
          const isChild = v ? v.isChildMoto : isChildMotoRow(b.motorcycles)
          return (
            <li key={b.id}>
              {isChild ? '🧒' : '🏍️'} {b.motorcycles?.model || 'Motorka'} · {formatBookingRange(b)} · {' '}
              <span style={{ color: isChild ? '#1a8a18' : '#1a2e22' }}>
                {isChild ? 'dětská — bez dokladů' : 'vyžaduje ŘP + OP/Pas'}
              </span>
              {!isChild && v && (
                <span style={{ color: v.allOk ? '#1a8a18' : '#b45309' }}>
                  {' · '}{v.allOk ? '✅ doklady kompletní' : `⚠️ ${v.reason || 'doklady neúplné'}`}
                </span>
              )}
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
          🏍️ Pro dospělou motorku je potřeba OP (líc + rub) nebo pas, ŘP (líc + rub), věk 18+, platnost ŘP do konce pronájmu a skupina ŘP pro motorku — jinak kódy NELZE uvolnit.
        </div>
      )}
    </div>
  )
}

// `vs` = NEJHORŠÍ verdikt přes nadcházející dospělé rezervace (backend get_docs_gate_checklist, záloha
// klient — lib/docsGate.js); `verdicts` = [{ booking, vs }] pro výpis per rezervace.
export default function CustomerVerificationSection({ vs, verdicts = [], profile, verificationDocs, upcomingBookings = [], hasAdultBooking = false, allChildOnly = false, noUpcoming = false, onChanged }) {
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
  const verdictMap = new Map(verdicts.filter(x => x.booking).map(x => [x.booking.id, x.vs]))
  const missing = Array.isArray(vs.missing) ? vs.missing : []
  // Nahrát doklady jde VŽDY, když něco chybí (dřív jen při !allOk podle volného pravidla)
  const needsUpload = !vs.allOk || missing.length > 0 || !vs.hasLicense || !vs.hasIdentity
  const reqGroups = (vs.requiredGroups || ['A']).join('/')
  const expTxt = vs.licenseExpiryDate ? fmtYmd(vs.licenseExpiryDate) : profile?.license_expiry
  // Bez konkrétní motorky (žádná dospělá rezervace) backend stačí AM/B — pro „připraven na motorku“
  // ale musí mít skupinu pro motorky (A/A2/A1/AM), jinak by B-only zákazník svítil zeleně.
  const motoGroupOk = vs.requiredGroups ? vs.hasMotoGroup : hasMotoLicenseGroup(profile?.license_group)

  async function openPreview(doc) {
    setError(null)
    if (!doc.file_path) { setError('Tento záznam nemá uloženou fotku.'); return }
    if (isMarkerPath(doc.file_path)) { setError('Záznam bez fotky — doklad je potřeba nahrát znovu.'); return }
    try {
      const { data, error: e } = await supabase.storage.from('documents').createSignedUrl(doc.file_path, 60 * 5)
      if (e) throw e
      setPreviewUrl(data.signedUrl); setPreviewDoc(doc)
    } catch (e) {
      setError(/not found/i.test(e?.message || '') ? 'Soubor v úložišti chybí — doklad je potřeba nahrát znovu' : 'Náhled selhal: ' + e.message)
    }
  }

  // Oprava chybně označené strany dokladu (historicky se rub ukládal jako líc,
  // protože upload modal stranu nenabízel). Zapíše metadata.side (`target` z tlačítka;
  // fotka bez strany má dvě explicitní volby) + opraví popisek. UPDATE documents spustí
  // backendový přepočet brány dokladů (zadržené kódy uvolní sám) → reload ukáže nový stav.
  async function swapSide(doc, target) {
    setError(null)
    const next = target === 'front' || target === 'back' ? target : (docSide(doc) === 'back' ? 'front' : 'back')
    const nextLabel = next === 'front' ? 'líc' : 'rub'
    const upd = { metadata: { ...(doc.metadata || {}), side: next } }
    if (doc.name) {
      upd.name = / — (líc|rub)/.test(doc.name)
        ? doc.name.replace(/ — (líc|rub)/, ` — ${nextLabel}`)
        : doc.name.replace(/^([^(]*?)(\s*\()/, `$1 — ${nextLabel}$2`)
    }
    try {
      const { error: e } = await supabase.from('documents').update(upd).eq('id', doc.id)
      if (e) throw e
      if (onChanged) await onChanged()
    } catch (e) {
      setError('Změna strany selhala: ' + e.message)
    }
  }

  async function performDelete(doc) {
    setDeleting(true); setError(null)
    try {
      if (doc.file_path && !isMarkerPath(doc.file_path)) {
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
        verdicts={verdictMap}
      />

      {/* Admin: dodatečné nahrání dokladů — kdykoli něco chybí */}
      {needsUpload && profile?.id && (
        <div className="mb-3 flex items-center gap-3 flex-wrap">
          <Button green onClick={() => setShowUpload(true)}>+ Nahrát doklady</Button>
          <span className="text-xs" style={{ color: '#5a6b63' }}>
            Vyfoťte nebo nahrajte doklad za zákazníka (každou stranu zvlášť) — proběhne OCR; kódy k boxu se uvolní samy, až bude vše kompletní.
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
        <div className="p-4 max-sm:p-3 rounded-lg" style={{ background: licenseOptional ? '#f9fafb' : '#f1faf7' }}>
          <div className="flex items-center gap-2 mb-2 flex-wrap">
            <span style={{ fontSize: 14 }}>{licenseOptional ? '➖' : vs.hasLicense ? '✅' : (vs.licFront || vs.licBack || vs.licenseTypedOnly) ? '⚠️' : '❌'}</span>
            <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Ridicsky prukaz (RP)</span>
            {licenseOptional ? (
              <Badge label="Pro dětskou motorku není potřeba" color="#1a8a18" bg="#dcfce7" />
            ) : (
              <Badge
                label={vs.hasLicense ? 'Lic + rub nahrany' : (vs.licFront || vs.licBack) ? `Lic ${vs.licFront ? '✓' : '✗'} / Rub ${vs.licBack ? '✓' : '✗'}` : vs.licenseOcrVerified ? 'Jen OCR — chybi fotky' : vs.licenseTypedOnly ? 'Zadano rucne — neovereno' : 'Chybi'}
                color={vs.hasLicense ? '#1a8a18' : (vs.licFront || vs.licBack || vs.licenseTypedOnly) ? '#b45309' : '#dc2626'}
                bg={vs.hasLicense ? '#dcfce7' : (vs.licFront || vs.licBack || vs.licenseTypedOnly) ? '#fef3c7' : '#fee2e2'}
              />
            )}
          </div>
          {!licenseOptional && (
            <div className="flex flex-wrap gap-2">
              <Badge
                label={vs.licenseValid ? `Platny do ${expTxt}` : vs.licenseExpiryDate ? `Neplatny k terminu pronajmu (do ${expTxt})` : profile?.license_expiry ? `Platnost necitelna (${profile.license_expiry})` : 'Platnost nevyplnena'}
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
                  label={vs.requiredGroups ? (vs.hasMotoGroup ? `Skupina pro motorku OK (${reqGroups})` : `Skupina nestaci (potreba ${reqGroups})`) : (motoGroupOk ? 'Skupina pro motorky OK' : 'Chybi skupina A/A2/A1/AM')}
                  color={motoGroupOk ? '#1a8a18' : '#dc2626'}
                  bg={motoGroupOk ? '#dcfce7' : '#fee2e2'}
                />
              )}
            </div>
          )}
          <DocSlots docs={licenseDocs} requireBothSides
            onPreview={openPreview} onDelete={d => setConfirmDelete(d)} onSwapSide={swapSide}
            emptyNote={licenseOptional
              ? 'Fotka ŘP nenahrána — pro aktuální dětskou rezervaci není potřeba. Pokud si zákazník později rezervuje dospělou motorku, bude nutné ŘP doplnit.'
              : vs.licenseDataOnly
                ? `⚠️ Fotky ŘP nenahrány. Číslo ŘP ${profile?.license_number ? `(${profile.license_number}) ` : ''}je přečtené přes OCR, ale bez fotky líce i rubu se kódy k boxu NEUVOLNÍ — nahrajte obě strany.`
                : vs.licenseTypedOnly
                  ? `⚠️ Číslo ŘP ${profile?.license_number ? `(${profile.license_number}) ` : ''}je zadané jen ručně ve formuláři — NENÍ nahraná fotka. Je potřeba nahrát líc i rub ŘP.`
                  : 'Žádné nahrané fotky.'} />
        </div>

        {/* Doklad totoznosti */}
        <div className="p-4 max-sm:p-3 rounded-lg" style={{ background: '#f1faf7' }}>
          <div className="flex items-center gap-2 mb-2 flex-wrap">
            <span style={{ fontSize: 14 }}>{vs.hasIdentity ? '✅' : (vs.idFront || vs.idBack || vs.identityTypedOnly) ? '⚠️' : '❌'}</span>
            <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>Doklad totoznosti (OP nebo pas)</span>
            <Badge
              label={vs.hasIdentity ? 'Vyfoceno' : (vs.idFront || vs.idBack) ? `OP lic ${vs.idFront ? '✓' : '✗'} / rub ${vs.idBack ? '✓' : '✗'}` : vs.idOcrVerified ? 'Jen OCR — chybi fotky' : vs.identityTypedOnly ? 'Zadano rucne — neovereno' : 'Chybi'}
              color={vs.hasIdentity ? '#1a8a18' : (vs.idFront || vs.idBack || vs.identityTypedOnly) ? '#b45309' : '#dc2626'}
              bg={vs.hasIdentity ? '#dcfce7' : (vs.idFront || vs.idBack || vs.identityTypedOnly) ? '#fef3c7' : '#fee2e2'}
            />
            {!allChildOnly && (
              <Badge
                label={vs.ageOk ? `Vek 18+ OK${vs.dateOfBirth ? ` (nar. ${fmtYmd(vs.dateOfBirth)})` : ''}` : vs.dateOfBirth ? 'Mladsi 18 let' : 'Chybi datum narozeni'}
                color={vs.ageOk ? '#1a8a18' : '#dc2626'} bg={vs.ageOk ? '#dcfce7' : '#fee2e2'} />
            )}
            {vs.hasIdCard && <Badge label="Obcansky prukaz" color="#1a8a18" bg="#dcfce7" />}
            {vs.hasPassport && <Badge label="Cestovni pas" color="#1a8a18" bg="#dcfce7" />}
          </div>

          {idCardDocs.length > 0 && (
            <div className="mt-3">
              <div className="text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>Občanský průkaz (líc + rub)</div>
              <DocSlots docs={idCardDocs} requireBothSides
                onPreview={openPreview} onDelete={d => setConfirmDelete(d)} onSwapSide={swapSide} />
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
              <div className="mt-3 p-2 rounded-lg text-xs" style={{ background: '#fef3c7', color: '#92400e', border: '1px solid #fcd34d' }}>
                ⚠️ Číslo dokladu {profile?.id_number ? `(${profile.id_number}) ` : ''}je přečtené přes OCR, ale fotka nahraná není — bez OP (líc + rub) nebo pasu se kódy k boxu NEUVOLNÍ.
              </div>
            ) : vs.identityTypedOnly ? (
              <div className="mt-3 p-2 rounded-lg text-xs" style={{ background: '#fef3c7', color: '#92400e', border: '1px solid #fcd34d' }}>
                ⚠️ Číslo dokladu {profile?.id_number ? `(${profile.id_number}) ` : ''}je zadané jen ručně ve formuláři — NENÍ nahraná fotka. Je potřeba nahrát OP (líc + rub) nebo pas.
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
            <span style={{ fontSize: 16 }}>{vs.allOk && motoGroupOk ? '✅' : 'ℹ️'}</span>
            <span className="text-sm font-bold" style={{ color: '#1a2e22' }}>
              {vs.allOk && motoGroupOk
                ? 'Doklady ověřeny — zákazník je připraven na jakoukoliv budoucí rezervaci'
                : 'Žádná aktuální rezervace — kódy k boxu se nyní neřeší'}
            </span>
          </div>
          {!(vs.allOk && motoGroupOk) && (
            <div className="text-xs mt-2" style={{ color: '#1a2e22' }}>
              Pro budoucí rezervaci dospělé motorky bude potřeba: OP (líc + rub) nebo pas, ŘP (líc + rub) s platností do konce pronájmu a skupinou pro danou motorku, datum narození (18+). Pro dětské motorky doklady nepotřeba.
              {missing.length > 0 && <> Teď chybí: {missing.join('; ')}.</>}
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
          {/* Co chybí = backend missing[] (get_docs_gate_checklist); u více rezervací per rezervace */}
          {!vs.allOk && (
            <ul className="mt-2 space-y-1" style={{ fontSize: 12, color: '#92400e' }}>
              {verdicts.length > 1
                ? verdicts.filter(x => !x.vs.allOk).map(x => (
                  <li key={x.booking?.id || 'none'}>• {x.booking?.motorcycles?.model || 'Rezervace'} · {formatBookingRange(x.booking)}: {x.vs.reason || 'doklady neúplné'}</li>
                ))
                : missing.map(m => <li key={m}>• {m}</li>)}
              {(vs.licenseTypedOnly || vs.identityTypedOnly || vs.licenseDataOnly || vs.identityDataOnly) && (
                <li>• Čísla dokladů zadaná ručně nebo přečtená OCR fotky nenahrazují — je potřeba nahrát fotky dokladů</li>
              )}
            </ul>
          )}
          {vs.source === 'client' && (
            <div className="text-xs mt-2" style={{ color: '#5a6b63' }}>
              Kontrola na serveru je nedostupná — stav spočítán ve Velíně (bez ověření, že soubory v úložišti existují).
            </div>
          )}
        </div>
      )}

      {previewUrl && (
        <Modal open title={previewDoc?.name || 'Foto dokladu'} onClose={() => { setPreviewUrl(null); setPreviewDoc(null) }} wide>
          <div className="flex justify-center" style={{ background: '#0f1a14', padding: 12, borderRadius: 8 }}>
            {/* < 1024 px: výška fotky dle displeje (telefon na šířku nemá 600 px) */}
            <img src={previewUrl} alt="doklad" className="max-h-[600px] max-lg:max-h-[60dvh]" style={{ maxWidth: '100%', borderRadius: 4 }} />
          </div>
          {previewDoc?.metadata?.ocr_fields && (
            <div className="mt-3"><OcrFieldsSummary fields={previewDoc.metadata.ocr_fields} /></div>
          )}
          <div className="flex justify-between gap-3 mt-3 max-sm:flex-wrap">
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
