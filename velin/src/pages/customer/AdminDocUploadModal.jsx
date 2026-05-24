import { useState, useRef, useEffect } from 'react'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import { supabase } from '../../lib/supabase'

// Admin dodatečné nahrání fotek dokladů za zákazníka.
// REUSE existující infrastruktury: edge fn `scan-document` (Mindee OCR) +
// `save-verification-document` (uložení fotky + řádek v documents → trigger
// release_withheld_door_codes uvolní zadržené kódy). Nové je jen UX/UI ve Velíně.

// Doklady jsou organizované do "flow" — uživatel vybere jeden doklad a průvodce
// ho provede všemi jeho stranami v jednom plynulém toku (líc → rub), bez nutnosti
// klikat každou stranu zvlášť. aspect = poměr stran vodícího rámečku (š/v):
// občanka i řidičák jsou ISO ID-1 (85,6 × 54 mm → ~1.585), pas se fotí datová
// strana na šířku (~1.42).
const FLOWS = [
  { key: 'op', scan: 'id', label: 'Občanský průkaz', steps: [
    { side: 'front', label: 'líc', aspect: 1.585 },
    { side: 'back', label: 'rub', aspect: 1.585 },
  ] },
  { key: 'passport', scan: 'passport', label: 'Cestovní pas', steps: [
    { side: null, label: 'datová strana', aspect: 1.42 },
  ] },
  { key: 'dl', scan: 'dl', label: 'Řidičský průkaz', steps: [
    { side: 'front', label: 'líc', aspect: 1.585 },
    { side: 'back', label: 'rub', aspect: 1.585 },
  ] },
]

function stepLabel(flow, step) {
  return flow.steps.length > 1 ? `${flow.label} — ${step.label}` : flow.label
}

function readFileAsDataUrl(file) {
  return new Promise((resolve, reject) => {
    const r = new FileReader()
    r.onload = () => resolve(r.result)
    r.onerror = reject
    r.readAsDataURL(file)
  })
}

// Ořez pořízeného snímku na vodící rámeček, aby se uložil jen samotný doklad bez
// okolního pozadí. Geometrii zrcadlíme 1:1 s overlay rámečkem v renderu (šířka
// 88 %, výška dopočítaná z poměru stran a omezená na 84 % výšky), takže výřez
// přesně odpovídá zelenému rámečku, do kterého uživatel doklad zarovnal.
// <video> má jen max-width/max-height (žádnou pevnou velikost), takže zobrazená
// plocha má stejný poměr stran jako nativní snímek a normalizované souřadnice
// rámečku sedí přímo na zdrojové rozlišení.
function cropRectForGuide(vw, vh, aspect) {
  let fw = 0.88 * vw
  let fh = fw / aspect
  const maxH = 0.84 * vh
  if (fh > maxH) fh = maxH
  return { sx: (vw - fw) / 2, sy: (vh - fh) / 2, sw: fw, sh: fh }
}

export default function AdminDocUploadModal({ userId, bookingId, onClose, onUploaded }) {
  const [flowKey, setFlowKey] = useState('op')
  const [stepIdx, setStepIdx] = useState(0)
  const [camState, setCamState] = useState('idle') // idle | starting | on | denied | unavailable
  const [imageData, setImageData] = useState(null) // data URL náhledu
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)
  const [result, setResult] = useState(null) // { ocr: 'ok'|'failed', fields, label, nextLabel }
  const videoRef = useRef(null)
  const streamRef = useRef(null)
  const fileRef = useRef(null)

  const flow = FLOWS.find(f => f.key === flowKey) || FLOWS[0]
  const step = flow.steps[stepIdx] || flow.steps[0]
  const nextStep = flow.steps[stepIdx + 1] || null
  const docType = { scan: flow.scan, side: step.side, aspect: step.aspect, label: stepLabel(flow, step) }

  function stopCamera() {
    if (streamRef.current) {
      streamRef.current.getTracks().forEach(t => t.stop())
      streamRef.current = null
    }
  }

  useEffect(() => () => stopCamera(), [])

  // <video> se do DOM vykreslí až když camState === 'on' a není zobrazen
  // náhled (imageData). Stream proto připojíme až po vykreslení elementu –
  // jinak je videoRef.current null a obraz zůstane černý (typicky iOS Safari).
  // Závislost na imageData zajistí znovupřipojení streamu při návratu z náhledu
  // na živou kameru (např. plynulé focení rubu po líci).
  useEffect(() => {
    if (camState !== 'on' || imageData) return
    const v = videoRef.current
    if (!v || !streamRef.current) return
    v.srcObject = streamRef.current
    const p = v.play()
    if (p && typeof p.catch === 'function') p.catch(() => {})
  }, [camState, imageData])

  async function startCamera() {
    setError(null)
    setImageData(null)
    setResult(null)
    setCamState('starting')
    if (!navigator.mediaDevices?.getUserMedia) {
      setCamState('unavailable')
      return
    }
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: { ideal: 'environment' } },
        audio: false,
      })
      streamRef.current = stream
      // Nejdřív vykreslíme <video> (camState='on'); připojení streamu
      // řeší useEffect výše, až element existuje v DOM.
      setCamState('on')
    } catch (e) {
      setCamState(e?.name === 'NotAllowedError' || e?.name === 'SecurityError' ? 'denied' : 'unavailable')
    }
  }

  function capture() {
    const v = videoRef.current
    if (!v || !v.videoWidth) return
    // Ořízneme na vodící rámeček → uloží se jen doklad, ne pozadí.
    const { sx, sy, sw, sh } = cropRectForGuide(v.videoWidth, v.videoHeight, docType.aspect)
    const maxW = 1600
    const scale = Math.min(1, maxW / sw)
    const w = Math.round(sw * scale)
    const h = Math.round(sh * scale)
    const c = document.createElement('canvas')
    c.width = w; c.height = h
    c.getContext('2d').drawImage(v, sx, sy, sw, sh, 0, 0, w, h)
    setImageData(c.toDataURL('image/jpeg', 0.85))
    // Kameru ZÁMĚRNĚ nezastavujeme – stream běží dál (camState zůstává 'on'),
    // aby šlo po uložení plynule pokračovat na další stranu dokladu bez nového
    // getUserMedia (iOS vyžaduje pro getUserMedia uživatelské gesto).
  }

  async function onFilePick(e) {
    const f = e.target.files?.[0]
    if (!f) return
    setError(null); setResult(null)
    try {
      setImageData(await readFileAsDataUrl(f))
    } catch {
      setError('Nepodařilo se načíst soubor.')
    }
    e.target.value = ''
  }

  function retake() {
    setImageData(null)
    setResult(null)
    setError(null)
  }

  function selectFlow(key) {
    if (busy) return
    setFlowKey(key)
    setStepIdx(0)
    retake()
  }

  async function applyOcrToProfile(scanType, fields) {
    if (!fields) return
    const upd = {}
    const now = new Date().toISOString()
    if (scanType === 'id' && fields.idNumber) { upd.id_number = fields.idNumber; upd.id_verified_at = now }
    if (scanType === 'passport' && fields.idNumber) { upd.id_number = fields.idNumber; upd.passport_verified_at = now }
    if (scanType === 'dl') {
      if (fields.licenseNumber) { upd.license_number = fields.licenseNumber; upd.license_verified_at = now }
      if (fields.licenseExpiry) { upd.license_expiry = fields.licenseExpiry; upd.license_verified_until = fields.licenseExpiry }
    }
    if (Object.keys(upd).length > 0) {
      try { await supabase.from('profiles').update(upd).eq('id', userId) } catch { /* fotka stejně dorazí */ }
    }
  }

  async function uploadCurrent() {
    if (!imageData || busy) return
    setBusy(true); setError(null)
    try {
      // 1) OCR přes existující edge fn scan-document (Mindee)
      let ocrStatus = 'failed'
      let fields = null
      try {
        const { data: ocr, error: ocrErr } = await supabase.functions.invoke('scan-document', {
          body: { image_base64: imageData, document_type: docType.scan, user_id: userId },
        })
        if (!ocrErr && ocr?.success && ocr?.data) {
          ocrStatus = 'ok'
          fields = ocr.data
          // Profil aktualizujeme jen z líce / pasu (rub nenese čísla)
          if (docType.side !== 'back') await applyOcrToProfile(docType.scan, fields)
        }
      } catch { /* OCR výpadek nesmí zablokovat uložení fotky */ }

      // 2) Uložení fotky přes existující edge fn save-verification-document
      //    (vloží řádek do documents → trigger release_withheld_door_codes uvolní kódy)
      const { data: saveRes, error: saveErr } = await supabase.functions.invoke('save-verification-document', {
        body: {
          user_id: userId,
          booking_id: bookingId || null,
          doc_type: docType.scan,
          image_base64: imageData,
          mindee_status: ocrStatus,
          ocr_fields: ocrStatus === 'ok' ? fields : null,
          doc_side: docType.side,
        },
      })
      if (saveErr) throw saveErr
      if (saveRes && saveRes.success === false) throw new Error(saveRes.error || 'Uložení selhalo')

      setResult({ ocr: ocrStatus, fields, label: docType.label, nextLabel: nextStep ? stepLabel(flow, nextStep) : null })
      setImageData(null)
      if (nextStep) {
        // Plynulé pokračování v rámci jednoho dokladu: přepneme na další stranu.
        // Kamera (pokud běží) zůstává zapnutá, takže uživatel rovnou fotí rub,
        // bez dalších kliků a bez nového getUserMedia.
        setStepIdx(stepIdx + 1)
      } else {
        // Doklad je kompletní – flow končí, kameru vypneme a vrátíme na začátek
        // (uživatel může vybrat další doklad, např. ŘP po OP).
        stopCamera()
        setCamState('idle')
        setStepIdx(0)
      }
      if (onUploaded) await onUploaded()
    } catch (e) {
      setError('Nahrání selhalo: ' + (e?.message || String(e)))
    }
    setBusy(false)
  }

  function handleClose() {
    stopCamera()
    onClose && onClose()
  }

  return (
    <Modal open title="Nahrát doklady za zákazníka" onClose={handleClose} wide>
      {error && <div className="p-2 mb-3 rounded-lg" style={{ background: '#fee2e2', color: '#dc2626', fontSize: 13 }}>{error}</div>}

      {result && (
        <div className="p-2 mb-3 rounded-lg" style={{ background: '#dcfce7', border: '1px solid #86efac', color: '#1a8a18', fontSize: 13 }}>
          ✅ {result.label} uložen{result.ocr === 'ok' ? ' — Mindee OCR proběhlo, údaje uloženy do profilu.' : ' (Mindee OCR neproběhlo — fotka uložena, ověří se na pobočce).'}
          {result.nextLabel
            ? <>{' '}Pokračujte: vyfoťte <strong>{result.nextLabel}</strong> — kamera je připravená.</>
            : <>{' '}Zadržené kódy k boxu se uvolní, jakmile jsou doklady kompletní.</>}
        </div>
      )}

      <div className="mb-3">
        <div className="text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#5a6b63' }}>Doklad</div>
        <div className="flex flex-wrap gap-2">
          {FLOWS.map(f => (
            <button key={f.key} onClick={() => selectFlow(f.key)} disabled={busy}
              className="rounded-btn text-sm font-bold cursor-pointer"
              style={{
                padding: '6px 12px', border: 'none',
                background: flowKey === f.key ? '#74FB71' : '#f1faf7',
                color: '#1a2e22',
                boxShadow: flowKey === f.key ? '0 4px 16px rgba(116,251,113,.35)' : 'none',
                opacity: busy ? .6 : 1,
              }}>
              {f.label}
            </button>
          ))}
        </div>
        {flow.steps.length > 1 && (
          <div className="text-xs mt-2" style={{ color: '#5a6b63' }}>
            Krok {stepIdx + 1} / {flow.steps.length}: <strong>{step.label}</strong>
            {' · '}vyfotíte obě strany v jednom kroku za sebou.
          </div>
        )}
      </div>

      {/* Náhled pořízené fotky */}
      {imageData ? (
        <div className="mb-3">
          <div className="flex justify-center" style={{ background: '#0f1a14', padding: 12, borderRadius: 8 }}>
            <img src={imageData} alt="náhled dokladu" style={{ maxWidth: '100%', maxHeight: 360, borderRadius: 4 }} />
          </div>
          <div className="flex justify-between gap-3 mt-3">
            <Button onClick={retake} disabled={busy}>Znovu</Button>
            <Button green onClick={uploadCurrent} disabled={busy}>
              {busy ? 'Nahrávám…' : `Nahrát: ${docType.label}`}
            </Button>
          </div>
        </div>
      ) : (
        <div className="mb-3">
          {/* Živá kamera */}
          {camState === 'on' ? (
            <div>
              <div className="flex justify-center" style={{ background: '#0f1a14', padding: 12, borderRadius: 8 }}>
                <div style={{ position: 'relative', maxWidth: '100%', lineHeight: 0 }}>
                  <video ref={videoRef} playsInline muted autoPlay
                    style={{ display: 'block', maxWidth: '100%', maxHeight: 360, borderRadius: 4 }} />
                  {/* Vodící rámeček ve tvaru dokladu – pomáhá se zarovnáním a ostřením.
                      Snímek se po vyfocení ořízne přesně na tento rámeček (cropRectForGuide). */}
                  <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', pointerEvents: 'none' }}>
                    <div style={{
                      width: '88%',
                      maxHeight: '84%',
                      aspectRatio: String(docType.aspect),
                      border: '2px solid rgba(116,251,113,.95)',
                      borderRadius: 12,
                      boxShadow: '0 0 0 9999px rgba(0,0,0,.30)',
                    }} />
                  </div>
                  <div style={{ position: 'absolute', left: 0, right: 0, bottom: 8, textAlign: 'center', pointerEvents: 'none' }}>
                    <span style={{ fontSize: 12, color: '#fff', background: 'rgba(0,0,0,.5)', padding: '3px 10px', borderRadius: 999 }}>
                      Zarovnejte do rámečku: {docType.label}
                    </span>
                  </div>
                </div>
              </div>
              <div className="flex justify-center mt-3">
                <Button green onClick={capture}>📸 Vyfotit</Button>
              </div>
            </div>
          ) : (
            <div className="p-4 rounded-lg text-center" style={{ background: '#f1faf7', border: '1px dashed #b6dccb' }}>
              <div className="text-sm mb-3" style={{ color: '#1a2e22' }}>
                Vyfoťte <strong>{docType.label}</strong> fotoaparátem zařízení, nebo nahrajte fotku z úložiště (galerie).
              </div>
              {camState === 'denied' && (
                <div className="text-xs mb-3" style={{ color: '#b45309' }}>
                  ⚠️ Přístup k fotoaparátu byl odmítnut. Povolte kameru v nastavení prohlížeče, nebo použijte nahrání z úložiště.
                </div>
              )}
              {camState === 'unavailable' && (
                <div className="text-xs mb-3" style={{ color: '#b45309' }}>
                  ⚠️ Fotoaparát není dostupný (potřeba HTTPS / podporovaný prohlížeč). Použijte nahrání z úložiště.
                </div>
              )}
              <div className="flex justify-center gap-3 flex-wrap">
                <Button green onClick={startCamera} disabled={camState === 'starting'}>
                  {camState === 'starting' ? 'Spouštím kameru…' : '📷 Zapnout fotoaparát'}
                </Button>
                <Button onClick={() => fileRef.current?.click()}>📁 Nahrát z úložiště</Button>
              </div>
              {/* Bez atributu `capture` → na mobilu se otevře výběr z galerie/souborů,
                  ne přímo kamera (focení řeší samostatné tlačítko „Zapnout fotoaparát"). */}
              <input ref={fileRef} type="file" accept="image/*"
                onChange={onFilePick} style={{ display: 'none' }} />
            </div>
          )}
        </div>
      )}

      <div className="flex justify-end mt-2">
        <Button onClick={handleClose} disabled={busy}>Hotovo</Button>
      </div>
    </Modal>
  )
}
