import { useState, useEffect, useRef } from 'react'
import { supabase } from '../../lib/supabase'
import { uploadHtmlAsPdf } from '../../lib/htmlToPdf'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import SignaturePad from '../../components/ui/SignaturePad'
import { buildDocVars, listAccessoryItems } from './bookingDocTemplates'
import { buildElectronicProtocolHtml, HANDOVER_CHECKS, EXTRA_GEAR_CHECKS, DAMAGE_CHECKS } from './bookingDocElectronic'
import { sendProtocolEmail } from './protocolEmail'
import { loadAccessoryTypes } from '../BranchHelpers'

// Elektronický předávací protokol / protokol o poškození — vyplnění na tabletu
// (checkboxy + volný text) a podpis perem. Uloží podepsané HTML do generated_documents.
// `verifiedCode` — kód motorky, kterým byla rezervace při rychlém odbavení z Velína
// nalezena (= ověření identity); protokol ho má předvyplněný a označený jako ověřený.
export default function ElectronicProtocolModal({ open, type, bookingId, onClose, onSaved, verifiedCode = '' }) {
  const isDamage = type === 'damage_protocol'
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState(null)
  const [vars, setVars] = useState(null)
  const [accessories, setAccessories] = useState([])
  // Číselník velikostí per typ výbavy (accessory_types) — pro změnu velikosti při předání
  const [sizesByType, setSizesByType] = useState({})
  const [mileage, setMileage] = useState('')
  const [visualState, setVisualState] = useState('')
  const [notes, setNotes] = useState('')
  const [damageDesc, setDamageDesc] = useState('')
  const [missingGear, setMissingGear] = useState('')
  const [checks, setChecks] = useState({})
  // Předávací protokol — jediná kolonka „Poškození" (zaškrtnutí + popis)
  const [handoverDamage, setHandoverDamage] = useState({ checked: false, desc: '' })
  // Ověření identity — zákazník nadiktuje svůj přístupový kód k motorce (zná ho
  // jen on z app/e-mailu); spolu s nahranými doklady tím potvrdíme totožnost.
  const [motoCode, setMotoCode] = useState('')        // očekávaný kód (z branch_door_codes)
  const [codeInput, setCodeInput] = useState('')      // co zadal operátor dle zákazníka
  const [codeVerified, setCodeVerified] = useState(false)
  const [codeChecked, setCodeChecked] = useState(false)
  // Samoobslužná pobočka (branches.type = 'samoobslužná', shodně s DB _is_self_service_booking): podpis
  // ve Velíně nastaví bookings.handover_protocol_filled_at (hradlo kódu motorky na displeji, §1 návrhu);
  // už podepsaný protokol (appka / displej) se podruhé nevystavuje — `alreadySigned` modal zablokuje.
  const [selfService, setSelfService] = useState(false)
  const [alreadySigned, setAlreadySigned] = useState(null)
  const custSig = useRef(null)
  const operSig = useRef(null)

  useEffect(() => { if (open) load() }, [open, bookingId, type])

  async function load() {
    setLoading(true); setError(null)
    try {
      const { data: booking, error: bErr } = await supabase.from('bookings').select('*, motorcycles!moto_id(model, spz, vin, year, license_required, branches(type, address, zip, city))').eq('id', bookingId).single()
      if (bErr || !booking) throw new Error('Rezervace nenalezena: ' + (bErr?.message || 'no data'))
      let customer = {}
      if (booking.user_id) { const { data: prof } = await supabase.from('profiles').select('id, full_name, email, phone, street, city, zip, country, ico, dic, license_number, license_expiry').eq('id', booking.user_id).single(); if (prof) customer = prof }
      const v = buildDocVars(booking, customer, bookingId)
      v._customer_id = customer.id || booking.user_id || null
      setVars(v)
      const self = booking.motorcycles?.branches?.type === 'samoobslužná'
      setSelfService(self)
      setAlreadySigned(!isDamage && self && booking.handover_protocol_filled_at ? booking.handover_protocol_filled_at : null)
      setMileage(isDamage ? '' : (booking.mileage_start ? String(booking.mileage_start) : ''))
      // origSize drží velikost z rezervace — při uložení se propíše jen skutečná změna
      setAccessories(listAccessoryItems(booking, booking.motorcycles || {}).map(i => ({ ...i, checked: true, origSize: i.size })))
      if (!isDamage) {
        try {
          const types = await loadAccessoryTypes()
          const map = {}; types.forEach(t => { map[t.key] = t.sizes || [] })
          setSizesByType(map)
        } catch { setSizesByType({}) }
      }
      const init = {}
      if (isDamage) { DAMAGE_CHECKS.forEach(d => { init[d.key] = { checked: false, note: '' } }) }
      else { [...HANDOVER_CHECKS, ...EXTRA_GEAR_CHECKS].forEach(d => { init[d.key] = false }) }
      setChecks(init)
      setVisualState(''); setNotes(''); setDamageDesc(''); setMissingGear(''); setHandoverDamage({ checked: false, desc: '' })
      // Načti přístupový kód k motorce pro tuto rezervaci (pro ověření identity).
      setCodeInput(''); setCodeVerified(false); setCodeChecked(false)
      const { data: dc } = await supabase.from('branch_door_codes').select('door_code')
        .eq('booking_id', bookingId).eq('code_type', 'motorcycle')
        .order('created_at', { ascending: false }).limit(1)
      const code = dc?.[0]?.door_code || ''
      setMotoCode(code || verifiedCode)
      if (verifiedCode) { setCodeInput(verifiedCode); setCodeVerified(true); setCodeChecked(true) }
    } catch (e) { setError(e.message) }
    setLoading(false)
  }

  function toggleHandover(key) { setChecks(c => ({ ...c, [key]: !c[key] })) }
  function toggleDamage(key) { setChecks(c => ({ ...c, [key]: { ...(c[key] || {}), checked: !c[key]?.checked } })) }
  function setDamageNote(key, note) { setChecks(c => ({ ...c, [key]: { ...(c[key] || {}), note } })) }
  // Odškrtnutí vrací velikost z rezervace (origSize): dokument u nepřevzaté položky ukáže objednanou velikost, ne rozpracovanou změnu.
  function toggleAccessory(i) { setAccessories(a => a.map((x, idx) => idx === i ? { ...x, checked: !x.checked, size: x.checked ? x.origSize : x.size } : x)) }
  function setAccessorySize(i, size) { setAccessories(a => a.map((x, idx) => idx === i ? { ...x, size } : x)) }

  function verifyCode() {
    const ok = !!motoCode && codeInput.trim() === String(motoCode).trim()
    setCodeVerified(ok); setCodeChecked(true)
  }

  async function handleSave() {
    // Identita: pokud má rezervace kód k motorce, musí se před uložením ověřit.
    if (motoCode && !codeVerified) {
      setError('Ověřte kód k motorce (identita zákazníka) — zadejte kód, který zákazník obdržel, a klikněte na „Ověřit“.')
      return
    }
    setSaving(true); setError(null)
    try {
      const customerSig = custSig.current?.toDataURL() || null
      if (!customerSig) { setError('Chybí podpis nájemce — podepište se prosím perem.'); setSaving(false); return }
      const operatorSig = operSig.current?.toDataURL() || null
      // Skutečnost z protokolu propíšeme do rezervace — UPDATE *_size sloupců spustí trigger
      // gear_shortage_on_booking → přepočet deficitů v Logistice zboží.
      // Zaškrtnutá položka se změněnou velikostí → nová velikost PŘED uložením protokolu. NEZAŠKRTNUTÁ
      // položka (zákazník si ji nevzal) → NULL = položka z rezervace odebrána, ale až PO úspěšném uložení
      // protokolu (níže) — kdyby uložení selhalo, výbava v rezervaci nesmí zmizet. Historii (gear_changes
      // from→null) zapíše DB trigger track_booking_content_changes (admin). Ceny / booking_extras se NEMĚNÍ.
      const removedUpd = {}
      if (!isDamage) {
        const upd = {}
        accessories.forEach(a => {
          if (!a.field) return
          if (!a.checked) removedUpd[a.field] = null
          else if (a.size && a.size !== a.origSize) upd[a.field] = a.size
        })
        const hasSizeUpd = Object.keys(upd).length > 0
        if (hasSizeUpd || (selfService && Object.keys(removedUpd).length > 0)) {
          // Samoobsluha: stejný guard jako edge — podepsal-li zákazník mezitím na displeji / v appce,
          // jeho protokol je závazný a výbava v rezervaci se z Velína už nemění (0 zasažených řádků).
          // Jen odebrání bez změny velikosti → guard ověří select (zápis NULL až po uložení protokolu).
          let q = hasSizeUpd ? supabase.from('bookings').update(upd) : supabase.from('bookings').select('id')
          q = q.eq('id', bookingId)
          if (selfService) q = q.is('handover_protocol_filled_at', null)
          const { data: rows, error: sErr } = await (hasSizeUpd ? q.select('id') : q)
          if (sErr) throw new Error('Propsání výbavy z protokolu (změna velikosti / odebrání položky) do rezervace selhalo: ' + sErr.message)
          if (selfService && !rows?.length) {
            setError('Předávací protokol už je podepsán (aplikace / displej pobočky) — výbava v rezervaci se nemění a druhý protokol se nevystavuje. Podepsané PDF najdete v Dokumentech.')
            setSaving(false); return
          }
        }
      }
      const form = { mileage, visualState, notes, damageDesc, missingGear, accessories, checks, damage: handoverDamage, identityCodeRequired: !!motoCode, identityVerified: codeVerified }
      const html = buildElectronicProtocolHtml({ type, vars, form, signatures: { customer: customerSig, operator: operatorSig } })
      const docId = crypto.randomUUID()
      const docName = (isDamage ? 'Protokol o poškození' : 'Předávací protokol') + ' (elektronický)'
      const filled = { ...vars, _signed_html: html, _doc_name: docName, _doc_type: type, _electronic: true, _signed_at: new Date().toISOString() }
      // PDF nahrajeme PŘED insertem, aby sync trigger (generated_documents → documents)
      // viděl reálnou cestu k souboru a zákazník dostal funkční dokument v appce.
      let pdfPath = null
      try { pdfPath = await uploadHtmlAsPdf(supabase, `generated/${bookingId}/${type}-${docId}.pdf`, html) } catch {}
      const { error: gErr } = await supabase.from('generated_documents').insert({ id: docId, template_id: null, booking_id: bookingId, customer_id: vars._customer_id, filled_data: filled, pdf_path: pdfPath })
      if (gErr) throw gErr
      // Odebrané (odškrtnuté) položky → NULL až teď, po uloženém protokolu; u samoobsluhy PŘED zápisem
      // handover_protocol_filled_at níže (stejný guard .is(null) jako výše). Protokol už existuje → chyba
      // zápisu uložení neshodí (opakované uložení by vystavilo druhý protokol), ale operátor ji uvidí
      // (alert před onSaved + `gearRemovalFailed` v info) — chyba i 0 zasažených řádků (RLS / guard).
      let gearRemovalFailed = false
      if (Object.keys(removedUpd).length > 0) {
        let rq = supabase.from('bookings').update(removedUpd).eq('id', bookingId)
        if (selfService) rq = rq.is('handover_protocol_filled_at', null)
        const { data: rRows, error: rErr } = await rq.select('id')
        gearRemovalFailed = !!rErr || !rRows?.length
        if (gearRemovalFailed) console.warn('[ElectronicProtocolModal] removing unticked gear from booking failed:', rErr?.message || '0 rows updated')
      }
      // Samoobslužná pobočka: podpis ve Velíně = stav protokolu na rezervaci. Trigger
      // trg_handover_signed_notify_kiosk pak jednotce pošle protocol_signed (overlay na
      // displeji zmizí / kóje se otevře) a appka přestane protokol vynucovat. `.is(null)`:
      // kdyby mezitím podepsal zákazník, jeho čas se nepřepíše. Obslužnou pobočku řeší
      // DB trigger _activate_on_handover_protocol_doc (aktivace + filled_at) — tam nic.
      let protocolStateSet = null
      if (!isDamage && selfService) {
        const { error: fErr } = await supabase.from('bookings')
          .update({ handover_protocol_filled_at: filled._signed_at, handover_protocol_autofilled: false })
          .eq('id', bookingId).is('handover_protocol_filled_at', null)
        protocolStateSet = !fErr
        if (fErr) console.warn('[ElectronicProtocolModal] handover_protocol_filled_at update failed:', fErr.message)
      }
      // Propsat stav tachometru z protokolu do dat. Předávací protokol → mileage_start
      // (trigger zvedne motorcycles.mileage). Protokol o poškození → jen mileage_end
      // (pro „Najeto" v souhrnu, motorku neovlivní). Best-effort, neblokuje uložení.
      try {
        const km = parseInt(String(mileage).replace(/[^\d]/g, ''), 10)
        if (Number.isFinite(km) && km > 0) {
          await supabase.from('bookings').update(isDamage ? { mileage_end: km } : { mileage_start: km }).eq('id', bookingId)
        }
      } catch {}
      const info = { html, type, docId, pdfPath, docName, bookingId, customerId: vars._customer_id, customerEmail: vars.customer_email || '', customerName: vars.customer_name || '', moto: `${vars.moto_model || ''}${vars.moto_spz ? ` (${vars.moto_spz})` : ''}`, rentalPeriod: vars.rental_period || '', bookingNumber: vars.booking_number || '' }
      // Protokol se zákazníkovi odešle e-mailem AUTOMATICKY hned po uložení
      // (dřív jen z karty Doklady po ručním kliknutí — z odbavení odjezdu
      // se neposílal vůbec). Best-effort: selhání mailu uložení neshodí,
      // rodič dostane výsledek v info.emailSent/emailError (možnost „Odeslat znovu").
      let emailResult = { sent: false, error: null }
      if (info.customerEmail) {
        try { emailResult = await sendProtocolEmail(info) } catch (e) { emailResult = { sent: false, error: e.message || String(e) } }
      }
      if (gearRemovalFailed) window.alert('Protokol je uložený, ale odškrtnutou výbavu (' + accessories.filter(a => a.field && !a.checked).map(a => a.label || a.field).join(', ') + ') se nepodařilo odebrat z rezervace — upravte výbavu v rezervaci ručně.')
      onSaved && onSaved({ ...info, emailSent: emailResult.sent, emailError: emailResult.error, protocolStateSet, gearRemovalFailed })
    } catch (e) {
      // 23505 = unikátní index generated_documents_handover_once (protokol ze samoobsluhy už existuje)
      const dup = e?.code === '23505' || /handover_once/.test(e?.message || '')
      setError(dup
        ? 'Předávací protokol už je podepsán (aplikace / displej pobočky) — najdete ho v Dokumentech. Druhý se nevystavuje.'
        : 'Uložení selhalo: ' + e.message)
    }
    setSaving(false)
  }

  const title = isDamage ? 'Protokol o poškození — elektronicky' : 'Předávací protokol — elektronicky'
  const cbStyle = { width: 22, height: 22, accentColor: '#3dba3a', cursor: 'pointer', flexShrink: 0 }
  const labelStyle = { fontSize: 14, color: '#0f1a14', cursor: 'pointer', lineHeight: 1.3 }
  const inputStyle = { width: '100%', padding: '10px 12px', borderRadius: 10, border: '1px solid #b6dccb', fontSize: 14 }

  return (
    <Modal open={open} title={title} onClose={onClose} wide>
      {loading ? (
        <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>
      ) : alreadySigned ? (
        // Samoobsluha: protokol se podepisuje právě jednou (appka / displej / Velín) — podruhé se nevystavuje
        <div className="space-y-4">
          {vars && (
            <div className="p-3 rounded-card" style={{ background: '#f1faf7', fontSize: 13, color: '#1a2e22' }}>
              <strong>{vars.customer_name}</strong> · {vars.moto_model} ({vars.moto_spz}) · {vars.rental_period}
            </div>
          )}
          <div className="p-3 rounded-card" style={{ background: '#dcfce7', color: '#166534', fontSize: 13 }}>
            <strong>Předávací protokol už je podepsán</strong> ({new Date(alreadySigned).toLocaleString('cs-CZ')}) — zákazník ho podepsal
            v aplikaci nebo na displeji pobočky. Podepsané PDF je v Dokumentech; na samoobslužné pobočce se protokol podepisuje jen jednou.
          </div>
          <div className="flex justify-end"><Button onClick={onClose}>Zavřít</Button></div>
        </div>
      ) : (
        <div className="space-y-5">
          {error && <div className="p-3 rounded-card" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}
          {vars && (
            <div className="p-3 rounded-card" style={{ background: '#f1faf7', fontSize: 13, color: '#1a2e22' }}>
              <strong>{vars.customer_name}</strong> · {vars.moto_model} ({vars.moto_spz}) · {vars.rental_period}
            </div>
          )}

          {/* Ověření identity — kód k motorce (jen Velín, ne app) */}
          <div className="p-3 rounded-card" style={{ border: '2px solid #2563eb', background: '#eff6ff' }}>
            <label style={{ fontSize: 12, fontWeight: 800, color: '#1e3a8a', display: 'block', marginBottom: 6 }}>Ověření identity — kód k motorce</label>
            <p style={{ fontSize: 12, color: '#1e3a8a', marginBottom: 8 }}>Požádejte zákazníka o jeho přístupový kód k motorce (z aplikace / e-mailu) a ověřte ho. Spolu s nahranými doklady tím potvrdíte totožnost přebírajícího.</p>
            {verifiedCode && codeVerified ? (
              // Rychlé odbavení kódem: rezervace byla nalezena právě tímto kódem,
              // identita je ověřena — kolonka je vyplněná a zamčená.
              <>
                <input type="text" value={codeInput} readOnly disabled style={{ ...inputStyle, background: '#f1faf7', fontWeight: 800, letterSpacing: 2 }} />
                <p style={{ fontSize: 12, fontWeight: 700, color: '#15803d', marginTop: 6 }}>✓ Kód souhlasí — rezervace jím byla vyhledána, identita ověřena.</p>
              </>
            ) : motoCode ? (
              <>
                <div className="flex items-center gap-2">
                  <input type="text" inputMode="numeric" value={codeInput}
                    onChange={e => { setCodeInput(e.target.value); setCodeVerified(false); setCodeChecked(false) }}
                    onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); verifyCode() } }}
                    style={inputStyle} placeholder="Kód k motorce od zákazníka" />
                  <Button onClick={verifyCode}>Ověřit</Button>
                </div>
                {codeChecked && (codeVerified
                  ? <p style={{ fontSize: 12, fontWeight: 700, color: '#15803d', marginTop: 6 }}>✓ Kód souhlasí — identita ověřena.</p>
                  : <p style={{ fontSize: 12, fontWeight: 700, color: '#dc2626', marginTop: 6 }}>✗ Kód nesouhlasí. Zkontrolujte kód u zákazníka.</p>)}
              </>
            ) : (
              <p style={{ fontSize: 12, color: '#b45309' }}>Pro tuto rezervaci není vygenerován kód k motorce (např. dětská motorka nebo zadržený kód). Ověření kódem se přeskočí.</p>
            )}
          </div>

          <div>
            <label style={{ fontSize: 12, fontWeight: 700, color: '#1a2e22', display: 'block', marginBottom: 6 }}>{isDamage ? 'Stav tachometru při vrácení (km)' : 'Stav km při předání'}</label>
            <input type="number" inputMode="numeric" value={mileage} onChange={e => setMileage(e.target.value)} style={inputStyle} placeholder="km" />
          </div>

          {isDamage && (
            <div>
              <label style={{ fontSize: 12, fontWeight: 700, color: '#1a2e22', display: 'block', marginBottom: 6 }}>Celkový vizuální stav</label>
              <textarea value={visualState} onChange={e => setVisualState(e.target.value)} rows={2} style={inputStyle} placeholder="Popis celkového stavu při vrácení" />
            </div>
          )}

          {!isDamage && (
            <div>
              <h3 className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Kontrola předání</h3>
              <div className="space-y-2">
                {HANDOVER_CHECKS.map(c => (
                  <label key={c.key} className="flex items-center gap-3 p-2 rounded-lg" style={{ background: '#f8faf9' }}>
                    <input type="checkbox" checked={!!checks[c.key]} onChange={() => toggleHandover(c.key)} style={cbStyle} />
                    <span style={labelStyle}>{c.label}</span>
                  </label>
                ))}
              </div>
            </div>
          )}

          {!isDamage && (
            <div>
              <h3 className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Doplňkové vybavení</h3>
              <div className="space-y-2">
                {EXTRA_GEAR_CHECKS.map(c => (
                  <label key={c.key} className="flex items-center gap-3 p-2 rounded-lg" style={{ background: '#f8faf9' }}>
                    <input type="checkbox" checked={!!checks[c.key]} onChange={() => toggleHandover(c.key)} style={cbStyle} />
                    <span style={labelStyle}>{c.label}</span>
                  </label>
                ))}
              </div>
            </div>
          )}

          {!isDamage && (
            <div>
              <h3 className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Poškození</h3>
              <div className="p-2 rounded-lg" style={{ background: '#f8faf9' }}>
                <label className="flex items-center gap-3">
                  <input type="checkbox" checked={handoverDamage.checked} onChange={() => setHandoverDamage(d => ({ ...d, checked: !d.checked }))} style={cbStyle} />
                  <span style={labelStyle}>Poškození při předání</span>
                </label>
                {handoverDamage.checked && (
                  <textarea value={handoverDamage.desc} onChange={e => setHandoverDamage(d => ({ ...d, desc: e.target.value }))} rows={2} style={{ ...inputStyle, marginTop: 8 }} placeholder="Popis poškození" />
                )}
              </div>
            </div>
          )}

          {isDamage ? (
            <div>
              <h3 className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Zjištěná poškození</h3>
              <div className="space-y-2">
                {DAMAGE_CHECKS.map(c => (
                  <div key={c.key} className="p-2 rounded-lg" style={{ background: '#f8faf9' }}>
                    <label className="flex items-center gap-3">
                      <input type="checkbox" checked={!!checks[c.key]?.checked} onChange={() => toggleDamage(c.key)} style={cbStyle} />
                      <span style={labelStyle}>{c.label}</span>
                    </label>
                    {checks[c.key]?.checked && (
                      <input type="text" value={checks[c.key]?.note || ''} onChange={e => setDamageNote(c.key, e.target.value)} style={{ ...inputStyle, marginTop: 8 }} placeholder="Popis poškození (volitelné)" />
                    )}
                  </div>
                ))}
              </div>
            </div>
          ) : (
            accessories.length > 0 && (
              <div>
                <h3 className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>Předané příslušenství</h3>
                <p style={{ fontSize: 12, color: '#4b5f52', marginBottom: 8 }}>Pokud zákazník dostal jinou velikost, změňte ji zde. Co si nevzal, odškrtněte — položka se z rezervace odebere. U zaškrtnutých položek se skutečnost propíše do rezervace a Logistiky zboží.</p>
                <div className="space-y-2">
                  {accessories.map((a, i) => {
                    const opts = sizesByType[a.type] || []
                    const optList = opts.includes(a.size) ? opts : [a.size, ...opts]
                    // Nezaškrtnuto = nepřevzato → položka se při uložení z rezervace odebere (velikost zamčená)
                    const off = !a.checked
                    const sizeStyle = { padding: '6px 10px', borderRadius: 8, border: `1px solid ${!off && a.size !== a.origSize ? '#f59e0b' : '#b6dccb'}`, fontSize: 14, fontWeight: 700, background: off ? '#f1f5f3' : '#fff', color: off ? '#9ca3af' : undefined }
                    return (
                      <div key={i} className="flex items-center gap-3 p-2 rounded-lg" style={{ background: '#f8faf9' }}>
                        <input type="checkbox" checked={a.checked} onChange={() => toggleAccessory(i)} style={cbStyle} />
                        <span style={{ ...labelStyle, flex: 1, ...(off ? { textDecoration: 'line-through', color: '#9ca3af' } : {}) }} onClick={() => toggleAccessory(i)}>{a.label}</span>
                        {opts.length > 0 ? (
                          <select value={a.size} disabled={off} onChange={e => setAccessorySize(i, e.target.value)} style={sizeStyle}>
                            {optList.map(s => <option key={s} value={s}>{s}</option>)}
                          </select>
                        ) : (
                          <input type="text" value={a.size} disabled={off} onChange={e => setAccessorySize(i, e.target.value)}
                            style={{ ...sizeStyle, width: 80, textAlign: 'center' }} />
                        )}
                        {off ? (
                          <span style={{ fontSize: 11, fontWeight: 700, color: '#dc2626', whiteSpace: 'nowrap' }}>nepřevzato — odebere se z rezervace</span>
                        ) : a.size !== a.origSize && (
                          <span style={{ fontSize: 11, fontWeight: 700, color: '#b45309', whiteSpace: 'nowrap' }}>bylo {a.origSize}</span>
                        )}
                      </div>
                    )
                  })}
                </div>
              </div>
            )
          )}

          {isDamage ? (
            <>
              <div>
                <label style={{ fontSize: 12, fontWeight: 700, color: '#1a2e22', display: 'block', marginBottom: 6 }}>Podrobný popis poškození</label>
                <textarea value={damageDesc} onChange={e => setDamageDesc(e.target.value)} rows={3} style={inputStyle} placeholder="Volitelný podrobnější popis" />
              </div>
              <div>
                <label style={{ fontSize: 12, fontWeight: 700, color: '#1a2e22', display: 'block', marginBottom: 6 }}>Chybějící / poškozené vybavení</label>
                <textarea value={missingGear} onChange={e => setMissingGear(e.target.value)} rows={2} style={inputStyle} placeholder="Volitelné" />
              </div>
            </>
          ) : (
            <div>
              <label style={{ fontSize: 12, fontWeight: 700, color: '#1a2e22', display: 'block', marginBottom: 6 }}>Poznámky</label>
              <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2} style={inputStyle} placeholder="Volitelné poznámky k předání" />
            </div>
          )}

          <div className={`grid grid-cols-1 ${isDamage ? 'sm:grid-cols-2' : ''} gap-4 pt-2`}>
            {isDamage && <SignaturePad ref={operSig} label="Podpis pronajímatele (volitelné)" />}
            <SignaturePad ref={custSig} label={`Podpis nájemce — ${vars?.customer_name || ''}`} />
          </div>

          <div className="flex justify-end gap-3 pt-2">
            <Button onClick={onClose} disabled={saving}>Zrušit</Button>
            <Button green onClick={handleSave} disabled={saving}>{saving ? 'Ukládám…' : 'Uložit podepsaný protokol'}</Button>
          </div>
        </div>
      )}
    </Modal>
  )
}
