import { useState, useRef, useEffect } from 'react'
import Modal from '../../components/ui/Modal'
import Button from '../../components/ui/Button'
import { supabase } from '../../lib/supabase'

// Admin dodatečné nahrání fotek dokladů za zákazníka.
// REUSE existující infrastruktury: edge fn `scan-document` (Mindee OCR) +
// `save-verification-document` (uložení fotky + řádek v documents → trigger
// release_withheld_door_codes uvolní zadržené kódy). Nové je jen UX/UI ve Velíně.

// aspect = poměr stran vodícího rámečku (š/v). Občanka i řidičák jsou ISO ID-1
// (85,6 × 54 mm → ~1.585), pas se fotí datová strana na šířku (~1.42).
// next = další krok průvodce, na který flow plynule naváže po uložení.
const DOC_TYPES = [
  { key: 'op_front', scan: 'id', side: 'front', label: 'Občanský průkaz — líc', aspect: 1.585, next: 'op_back' },
  { key: 'op_back', scan: 'id', side: 'back', label: 'Občanský průkaz — rub', aspect: 1.585, next: null },
  { key: 'passport', scan: 'passport', side: null, label: 'Cestovní pas', aspect: 1.42, next: null },
  { key: 'dl_front', scan: 'dl', side: 'front', label: 'Řidičský průkaz — líc', aspect: 1.585, next: 'dl_back' },
  { key: 'dl_back', scan: 'dl', side: 'back', label: 'Řidičský průkaz — rub', aspect: 1.585, next: null },
]

function readFileAsDataUrl(file) {
  return new Promise((resolve, reject) => {
    const r = new FileReader()
    r.onload = () => resolve(r.result)
    r.onerror = reject
    r.readAsDataURL(file)
  })
}

export default function AdminDocUploadModal({ userId, bookingId, onClose, onUploaded }) {
  const [docKey, setDocKey] = useState('op_front')
  const [camState, setCamState] = useState('idle') // idle | starting | on | denied | unavailable
  const [imageData, setImageData] = useState(null) // data URL náhledu
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)
  const [result, setResult] = useState(null) // { ocr: 'ok'|'failed', fields, label }
  const videoRef = useRef(null)
  const streamRef = useRef(null)
  const fileRef = useRef(null)

  const docType = DOC_TYPES.find(d => d.key === docKey) || DOC_TYPES[0]

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
    const maxW = 1600
    const scale = Math.min(1, maxW / v.videoWidth)
    const w = Math.round(v.videoWidth * scale)
    const h = Math.round(v.videoHeight * scale)
    const c = document.createElement('canvas')
    c.width = w; c.height = h
    c.getContext('2d').drawImage(v, 0, 0, w, h)
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

      const next = docType.next ? DOC_TYPES.find(d => d.key === docType.next) : null
      setResult({ ocr: ocrStatus, fields, label: docType.label, nextLabel: next?.label || null })
      setImageData(null)
      if (next) {
        // Plynulé pokračování: přepneme na další stranu dokladu. Kamera (pokud
        // běží) zůstává zapnutá, takže uživatel rovnou fotí, bez dalších kliků.
        setDocKey(next.key)
      } else {
        stopCamera()
        setCamState('idle')
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
        <div className="text-xs font-extrabold uppercase tracking-wide mb-1" style={{ color: '#5a6b63' }}>Typ dokladu</div>
        <div className="flex flex-wrap gap-2">
          {DOC_TYPES.map(d => (
            <button key={d.key} onClick={() => { setDocKey(d.key); retake() }}
              className="rounded-btn text-sm font-bold cursor-pointer"
              style={{
                padding: '6px 12px', border: 'none',
                background: docKey === d.key ? '#74FB71' : '#f1faf7',
                color: '#1a2e22',
                boxShadow: docKey === d.key ? '0 4px 16px rgba(116,251,113,.35)' : 'none',
              }}>
              {d.label}
            </button>
          ))}
        </div>
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
                  {/* Vodící rámeček ve tvaru dokladu – pomáhá se zarovnáním a ostřením */}
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
                Vyfoťte doklad fotoaparátem zařízení nebo nahrajte fotku ze souborů.
              </div>
              {camState === 'denied' && (
                <div className="text-xs mb-3" style={{ color: '#b45309' }}>
                  ⚠️ Přístup k fotoaparátu byl odmítnut. Povolte kameru v nastavení prohlížeče, nebo použijte nahrání ze zařízení.
                </div>
              )}
              {camState === 'unavailable' && (
                <div className="text-xs mb-3" style={{ color: '#b45309' }}>
                  ⚠️ Fotoaparát není dostupný (potřeba HTTPS / podporovaný prohlížeč). Použijte nahrání ze zařízení.
                </div>
              )}
              <div className="flex justify-center gap-3 flex-wrap">
                <Button green onClick={startCamera} disabled={camState === 'starting'}>
                  {camState === 'starting' ? 'Spouštím kameru…' : '📷 Zapnout fotoaparát'}
                </Button>
                <Button onClick={() => fileRef.current?.click()}>📁 Nahrát ze zařízení</Button>
              </div>
              <input ref={fileRef} type="file" accept="image/*" capture="environment"
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
