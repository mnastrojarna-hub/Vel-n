import { useState, useRef, useEffect } from 'react'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import { supabase } from '../../lib/supabase'

// Admin dodatečné nahrání fotek dokladů za zákazníka.
// REUSE existující infrastruktury: edge fn `scan-document` (Mindee OCR) +
// `save-verification-document` (uložení fotky + řádek v documents → trigger
// release_withheld_door_codes uvolní zadržené kódy). Nové je jen UX/UI ve Velíně.
//
// Focení má 100% stejný flow jako appka / web rezervace (pages-rezervace-camera.js):
//   1) z jednoho stisku se pořídí BURST více snímků (BURST_FRAMES),
//   2) u každého se spočte ostrost (Laplacian variance) ve vodícím rámečku,
//   3) snímky se seřadí od nejostřejšího — nejostřejší je náhled k uložení,
//   4) OCR (Mindee) jede přes snímky od nejostřejšího, dokud nějaký nevrátí pole
//      (burst OCR). Pokud Mindee NEODPOVÍ / nevrátí pole, fotka se i tak uloží
//      (mindee_status='failed') → výsledek je VŽDY success.
// Ručně vyplněná čísla v profilu mají přednost před OCR — applyOcrToProfile
// proto nikdy nepřepíše už vyplněné id_number / license_number / license_expiry,
// jen doplní prázdná pole a nastaví verified_at (reálný sken proběhl).

// Počet snímků v burstu (web/app dělá 5; minimum pro výběr nejostřejšího jsou 3).
const BURST_FRAMES = 5
const BURST_INTERVAL_MS = 300

function sleep(ms) { return new Promise(r => setTimeout(r, ms)) }

// Ostrost snímku = rozptyl (variance) Laplacian-like operátoru přes podvzorek
// pixelů v šedi. Vyšší = ostřejší. Stejný princip jako web pages-rezervace-camera.js.
function computeSharpness(ctx, w, h) {
  try {
    if (w < 12 || h < 12) return 0
    const data = ctx.getImageData(0, 0, w, h).data
    let sum = 0, sumSq = 0, n = 0
    const gray = (i) => 0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2]
    for (let y = 1; y < h - 1; y += 4) {
      for (let x = 1; x < w - 1; x += 4) {
        const c = (y * w + x) * 4
        const l = (y * w + (x - 1)) * 4
        const r = (y * w + (x + 1)) * 4
        const t = ((y - 1) * w + x) * 4
        const b = ((y + 1) * w + x) * 4
        const lap = Math.abs(4 * gray(c) - gray(l) - gray(r) - gray(t) - gray(b))
        sum += lap; sumSq += lap * lap; n++
      }
    }
    if (n === 0) return 0
    const mean = sum / n
    return sumSq / n - mean * mean
  } catch { return 0 }
}

function stripB64(dataUrl) {
  return dataUrl && dataUrl.includes(',') ? dataUrl.split(',')[1] : dataUrl
}

// Má OCR výsledek alespoň jedno použitelné pole pro daný typ dokladu?
// (Stejná logika jako _rezOcrBurst na webu.)
function hasUsefulFields(scan, d) {
  if (!d || typeof d !== 'object') return false
  if (scan === 'dl') return !!(d.licenseNumber || d.licenseCategory || d.licenseExpiry || d.idNumber)
  return !!(d.idNumber || d.firstName || d.lastName || d.dateOfBirth)
}

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
  const [imageData, setImageData] = useState(null) // data URL náhledu (nejostřejší snímek)
  const [burstFrames, setBurstFrames] = useState([]) // [b64,…] seřazené od nejostřejšího (jen z kamery)
  const [capturing, setCapturing] = useState(false) // probíhá burst snímání
  const [burstProgress, setBurstProgress] = useState(0) // n pořízených snímků
  const [pendingFiles, setPendingFiles] = useState([]) // fronta dalších souborů (líc+rub z úložiště najednou)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)
  const [result, setResult] = useState(null) // { ocr: 'ok'|'failed', fields, label, nextLabel, mode }
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
    setBurstFrames([])
    setPendingFiles([])
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

  // Jeden snímek ořízlý na vodící rámeček → vrací { dataUrl, b64, sharp }.
  function grabFrame(v, aspect) {
    const { sx, sy, sw, sh } = cropRectForGuide(v.videoWidth, v.videoHeight, aspect)
    const maxW = 1600
    const scale = Math.min(1, maxW / sw)
    const w = Math.round(sw * scale)
    const h = Math.round(sh * scale)
    const c = document.createElement('canvas')
    c.width = w; c.height = h
    const ctx = c.getContext('2d')
    ctx.drawImage(v, sx, sy, sw, sh, 0, 0, w, h)
    const sharp = computeSharpness(ctx, w, h)
    const dataUrl = c.toDataURL('image/jpeg', 0.85)
    return { dataUrl, b64: stripB64(dataUrl), sharp }
  }

  // Burst snímání jako v appce/webu: pořídí BURST_FRAMES snímků, seřadí podle
  // ostrosti a nejostřejší nabídne jako náhled. Všechny snímky (od nejostřejšího)
  // si ponecháme pro burst OCR. Kameru ZÁMĚRNĚ nezastavujeme – po uložení jde
  // plynule pokračovat na rub bez nového getUserMedia (iOS vyžaduje gesto).
  async function captureBurst() {
    const v = videoRef.current
    if (!v || !v.videoWidth || capturing || busy) return
    setError(null); setResult(null); setPendingFiles([])
    setCapturing(true); setBurstProgress(0)
    const frames = []
    for (let i = 0; i < BURST_FRAMES; i++) {
      if (!videoRef.current || !videoRef.current.videoWidth) break
      frames.push(grabFrame(videoRef.current, docType.aspect))
      setBurstProgress(i + 1)
      if (i < BURST_FRAMES - 1) await sleep(BURST_INTERVAL_MS)
    }
    frames.sort((a, b) => b.sharp - a.sharp)
    setBurstFrames(frames.map(f => f.b64))
    setImageData(frames.length ? frames[0].dataUrl : null)
    setCapturing(false)
    setBurstProgress(0)
  }

  async function onFilePick(e) {
    const files = Array.from(e.target.files || [])
    e.target.value = ''
    if (!files.length) return
    setError(null); setResult(null); setBurstFrames([])
    try {
      const urls = await Promise.all(files.map(readFileAsDataUrl))
      // Líc + rub najednou: u dvoustranného dokladu (OP/ŘP) bere víc vybraných
      // souborů jako po sobě jdoucí strany — první = aktuální krok, zbytek do fronty.
      if (flow.steps.length > 1 && urls.length > 1) {
        setStepIdx(0)
        setImageData(urls[0])
        setPendingFiles(urls.slice(1))
      } else {
        setPendingFiles([])
        setImageData(urls[0])
      }
    } catch {
      setError('Nepodařilo se načíst soubor.')
    }
  }

  function retake() {
    setImageData(null)
    setBurstFrames([])
    setResult(null)
    setError(null)
  }

  function selectFlow(key) {
    if (busy || capturing) return
    setFlowKey(key)
    setStepIdx(0)
    setPendingFiles([])
    retake()
  }

  // Zapíše OCR do profilu, ale RUČNĚ vyplněné údaje mají přednost před Mindee:
  // už vyplněné id_number / license_number / license_expiry se NIKDY nepřepíšou,
  // doplní se jen prázdná pole. verified_at se nastaví vždy (reálný sken proběhl),
  // takže doklad je ověřený i když si necháme ručně zadané číslo.
  async function applyOcrToProfile(scanType, fields) {
    if (!fields) return
    const empty = (v) => !(v != null && String(v).trim() !== '')
    let cur = {}
    try {
      const { data } = await supabase.from('profiles')
        .select('id_number, license_number, license_expiry').eq('id', userId).single()
      cur = data || {}
    } catch { /* když se profil nenačte, raději nic nepřepisujeme */ cur = { id_number: 'x', license_number: 'x', license_expiry: 'x' } }
    const upd = {}
    const now = new Date().toISOString()
    if (scanType === 'id') {
      if (fields.idNumber && empty(cur.id_number)) upd.id_number = fields.idNumber
      upd.id_verified_at = now
    }
    if (scanType === 'passport') {
      if (fields.idNumber && empty(cur.id_number)) upd.id_number = fields.idNumber
      upd.passport_verified_at = now
    }
    if (scanType === 'dl') {
      if (fields.licenseNumber && empty(cur.license_number)) upd.license_number = fields.licenseNumber
      if (fields.licenseExpiry && empty(cur.license_expiry)) { upd.license_expiry = fields.licenseExpiry; upd.license_verified_until = fields.licenseExpiry }
      upd.license_verified_at = now
    }
    if (Object.keys(upd).length > 0) {
      try { await supabase.from('profiles').update(upd).eq('id', userId) } catch { /* fotka stejně dorazí */ }
    }
  }

  async function uploadCurrent() {
    if (!imageData || busy || capturing) return
    setBusy(true); setError(null)
    try {
      // Snímky pro OCR: z kamery máme burst (od nejostřejšího), z úložiště 1 soubor.
      const frames = burstFrames.length ? burstFrames : [stripB64(imageData)]

      // 1) Burst OCR přes scan-document (Mindee) — zkoušíme od nejostřejšího,
      //    dokud nějaký snímek nevrátí použitelná pole. Pokud Mindee NEODPOVÍ
      //    nebo nevrátí pole, pokračujeme s mindee_status='failed' (fotka se
      //    stejně uloží → výsledek je vždy success).
      let ocrStatus = 'failed'
      let fields = null
      let bestB64 = frames[0]
      for (const b64 of frames) {
        try {
          const { data: ocr, error: ocrErr } = await supabase.functions.invoke('scan-document', {
            body: { image_base64: b64, document_type: docType.scan, user_id: userId },
          })
          // Líc/pas: vyžadujeme čitelné identifikační pole (číslo/jméno). Rub nenese
          // čísla → stačí, že Mindee vrátil jakákoli data (typicky adresa/skupiny).
          const ok = !ocrErr && ocr?.success && ocr?.data && (
            docType.side === 'back'
              ? Object.keys(ocr.data).length > 0
              : hasUsefulFields(docType.scan, ocr.data)
          )
          if (ok) {
            ocrStatus = 'ok'
            fields = ocr.data
            bestB64 = b64 // ulož ten snímek, který se reálně přečetl
            break
          }
        } catch { /* OCR výpadek nesmí zablokovat uložení fotky */ }
      }
      // Profil aktualizujeme jen z líce / pasu (rub nenese čísla); ruční zápis vyhrává.
      if (ocrStatus === 'ok' && docType.side !== 'back') await applyOcrToProfile(docType.scan, fields)

      // 2) Uložení fotky přes existující edge fn save-verification-document
      //    (vloží řádek do documents → trigger release_withheld_door_codes uvolní kódy)
      const { data: saveRes, error: saveErr } = await supabase.functions.invoke('save-verification-document', {
        body: {
          user_id: userId,
          booking_id: bookingId || null,
          doc_type: docType.scan,
          image_base64: bestB64,
          mindee_status: ocrStatus,
          ocr_fields: ocrStatus === 'ok' ? fields : null,
          doc_side: docType.side,
        },
      })
      if (saveErr) throw saveErr
      if (saveRes && saveRes.success === false) throw new Error(saveRes.error || 'Uložení selhalo')

      // Další soubor z fronty (líc+rub vybrané najednou z úložiště)?
      const hasPendingFile = pendingFiles.length > 0
      setResult({
        ocr: ocrStatus, fields, label: docType.label,
        nextLabel: nextStep ? stepLabel(flow, nextStep) : null,
        mode: camState === 'on' ? 'camera' : (hasPendingFile ? 'file' : 'idle'),
      })
      setBurstFrames([])
      if (nextStep) {
        // Plynulé pokračování v rámci jednoho dokladu: přepneme na další stranu.
        setStepIdx(stepIdx + 1)
        if (hasPendingFile) {
          // Z úložiště vybrané strany jedou automaticky za sebou.
          const [next, ...rest] = pendingFiles
          setPendingFiles(rest)
          setImageData(next)
        } else {
          // Kamera (pokud běží) zůstává zapnutá → uživatel rovnou fotí rub.
          setImageData(null)
        }
      } else {
        // Doklad je kompletní – flow končí, kameru vypneme a vrátíme na začátek
        // (uživatel může vybrat další doklad, např. ŘP po OP).
        setImageData(null)
        setPendingFiles([])
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
          ✅ {result.label} uložen{result.ocr === 'ok' ? ' — Mindee OCR proběhlo, údaje doplněny do profilu (ručně zadané se zachovávají).' : ' (Mindee OCR neproběhlo — fotka uložena, ověří se na pobočce).'}
          {result.nextLabel
            ? (result.mode === 'camera'
                ? <>{' '}Pokračujte: vyfoťte <strong>{result.nextLabel}</strong> — kamera je připravená.</>
                : result.mode === 'file'
                  ? <>{' '}Pokračuji další vybranou stranou: <strong>{result.nextLabel}</strong>.</>
                  : <>{' '}Pokračujte: vyfoťte nebo nahrajte <strong>{result.nextLabel}</strong>.</>)
            : <>{' '}Zadržené kódy k boxu se uvolní, jakmile jsou doklady kompletní.</>}
        </div>
      )}

      <div className="mb-3">
        <div className="text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#5a6b63' }}>Doklad</div>
        <div className="flex flex-wrap gap-2">
          {FLOWS.map(f => (
            <button key={f.key} onClick={() => selectFlow(f.key)} disabled={busy || capturing}
              className="rounded-btn text-sm font-bold cursor-pointer"
              style={{
                padding: '6px 12px', border: 'none',
                background: flowKey === f.key ? '#74FB71' : '#f1faf7',
                color: '#1a2e22',
                boxShadow: flowKey === f.key ? '0 4px 16px rgba(116,251,113,.35)' : 'none',
                opacity: (busy || capturing) ? .6 : 1,
              }}>
              {f.label}
            </button>
          ))}
        </div>
        {flow.steps.length > 1 && (
          <div className="text-xs mt-2" style={{ color: '#5a6b63' }}>
            Krok {stepIdx + 1} / {flow.steps.length}: <strong>{step.label}</strong>
            {' · '}vyfotíte obě strany za sebou, nebo z úložiště vyberte líc i rub najednou.
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
                      {capturing
                        ? `Snímám… ${burstProgress}/${BURST_FRAMES} — držte doklad v rámečku`
                        : `Zarovnejte do rámečku: ${docType.label}`}
                    </span>
                  </div>
                </div>
              </div>
              <div className="flex flex-col items-center mt-3">
                <Button green onClick={captureBurst} disabled={capturing || busy}>
                  {capturing ? `📸 Snímám… ${burstProgress}/${BURST_FRAMES}` : '📸 Vyfotit'}
                </Button>
                <div className="text-xs mt-2" style={{ color: '#5a6b63' }}>
                  Pořídí se {BURST_FRAMES} snímků a vybere se nejostřejší (stejně jako v aplikaci).
                </div>
              </div>
            </div>
          ) : (
            <div className="p-4 rounded-lg text-center" style={{ background: '#f1faf7', border: '1px dashed #b6dccb' }}>
              <div className="text-sm mb-3" style={{ color: '#1a2e22' }}>
                Vyfoťte <strong>{docType.label}</strong> fotoaparátem zařízení, nebo nahrajte fotku z úložiště (galerie).
                {flow.steps.length > 1 && <> U {flow.label} můžete z úložiště vybrat <strong>líc i rub najednou</strong> — nahrají se za sebou.</>}
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
                  ne přímo kamera (focení řeší samostatné tlačítko „Zapnout fotoaparát").
                  `multiple` → u OP/ŘP lze vybrat líc i rub naráz (zpracují se za sebou). */}
              <input ref={fileRef} type="file" accept="image/*" multiple={flow.steps.length > 1}
                onChange={onFilePick} style={{ display: 'none' }} />
            </div>
          )}
        </div>
      )}

      <div className="flex justify-end mt-2">
        <Button onClick={handleClose} disabled={busy || capturing}>Hotovo</Button>
      </div>
    </Modal>
  )
}
