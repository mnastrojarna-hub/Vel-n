import { useState, useRef } from 'react'
import { supabase } from '../../lib/supabase'

/**
 * Univerzální nahrávač obrázků pro Velín.
 * - Drag & drop ze souborového systému
 * - Klik pro výběr souborů
 * - Volitelně přidání obrázku přes URL
 * - Náhledy s tlačítkem ✕ pro odebrání
 * - První obrázek = hlavní (HLAVNÍ badge volitelný)
 *
 * Props:
 *   value          string[]  – aktuální URL obrázků
 *   onChange       (urls)    – callback při změně
 *   folder         string    – cesta v bucketu (např. 'blog/abcd', 'motos/xyz')
 *   bucket         string    – výchozí 'media'
 *   multiple       bool      – výchozí true
 *   max            number    – max počet obrázků (volitelné)
 *   showMainBadge  bool      – výchozí true (zvýrazní první jako hlavní)
 *   allowUrl       bool      – výchozí true (umožní přidat přes URL)
 *   single         bool      – pokud true, drží jen 1 obrázek (přepisuje)
 *   helperText     string    – nápověda pod komponentou
 *   alts           string[]  – volitelné — paralelní pole SEO popisků k obrázkům.
 *                              Pokud předáno + onAltsChange, pod každým náhledem se
 *                              objeví input pro krátký popisek (např. „zepředu").
 *                              Web pak skládá finální alt jako "{model/název} – {popisek}".
 *   onAltsChange   (alts)    – callback při změně popisků (paralelní pole s `value`)
 *   altPlaceholder string    – placeholder do alt inputu (např. „zepředu, zboku…")
 */
export default function ImageUploader({
  value = [],
  onChange,
  folder,
  bucket = 'media',
  multiple = true,
  max,
  showMainBadge = true,
  allowUrl = true,
  single = false,
  helperText,
  alts,
  onAltsChange,
  altPlaceholder = 'Popisek pro SEO (např. „zepředu")',
}) {
  const urls = Array.isArray(value) ? value : []
  const altsArr = Array.isArray(alts) ? alts : []
  const altsEnabled = Array.isArray(alts) && typeof onAltsChange === 'function'
  const [uploading, setUploading] = useState(false)
  const [progress, setProgress] = useState({ done: 0, total: 0 })
  const [dragOver, setDragOver] = useState(false)
  const [showUrlInput, setShowUrlInput] = useState(false)
  const [urlInput, setUrlInput] = useState('')
  const [err, setErr] = useState(null)
  const inputRef = useRef(null)

  const canAddMore = !max || urls.length < max
  const effectiveMultiple = single ? false : multiple

  function emit(next) {
    onChange?.(next)
  }

  // Helper: po změně urls dorovná paralelní alts pole na stejnou délku.
  // Mapuje staré altsArr podle URL → nový alts. URLs, které v původním poli nebyly,
  // dostanou prázdný string.
  function emitAlts(nextUrls, nextAlts) {
    if (!altsEnabled) return
    if (Array.isArray(nextAlts)) {
      onAltsChange(nextAlts)
      return
    }
    // Dorovnat alts podle nového pole urls — zachovat popisky pro URLs, které
    // jsou pořád v poli (najít podle url string), nové URLs dostanou ''.
    const next = nextUrls.map(u => {
      const idx = urls.indexOf(u)
      return idx >= 0 ? (altsArr[idx] || '') : ''
    })
    onAltsChange(next)
  }

  // Komprese + zmenšení před nahráním. Snižuje storage i egress (~15×).
  // PNG zůstává PNG (kvůli průhlednosti), ostatní rastry → JPEG 80 %. Max 1600 px.
  // GIF/SVG (animace/vektory) i už dostatečně malé obrázky se nahrají beze změny.
  async function compressImage(file) {
    const type = file.type || ''
    if (type === 'image/gif' || type === 'image/svg+xml') return null
    let bitmap
    try {
      bitmap = typeof createImageBitmap === 'function'
        ? await createImageBitmap(file)
        : await new Promise((res, rej) => {
            const img = new Image()
            const u = URL.createObjectURL(file)
            img.onload = () => { URL.revokeObjectURL(u); res(img) }
            img.onerror = (e) => { URL.revokeObjectURL(u); rej(e) }
            img.src = u
          })
    } catch { return null }
    const w = bitmap.width, h = bitmap.height
    if (!w || !h) { bitmap.close?.(); return null }
    const MAX_DIM = 1600
    const scale = Math.min(1, MAX_DIM / Math.max(w, h))
    // Už malý a v rozměru → neztrácet kvalitu rekompresí, nahraj originál.
    if (scale === 1 && file.size <= 400 * 1024) { bitmap.close?.(); return null }
    const tw = Math.round(w * scale), th = Math.round(h * scale)
    const canvas = document.createElement('canvas')
    canvas.width = tw; canvas.height = th
    const ctx = canvas.getContext('2d')
    ctx.drawImage(bitmap, 0, 0, tw, th)
    bitmap.close?.()
    const outType = type === 'image/png' ? 'image/png' : 'image/jpeg'
    const blob = await new Promise(res =>
      canvas.toBlob(res, outType, outType === 'image/jpeg' ? 0.8 : undefined))
    if (!blob || blob.size >= file.size) return null // nezhoršovat
    return { blob, contentType: outType, ext: outType === 'image/png' ? 'png' : 'jpg' }
  }

  async function uploadFile(file) {
    if (!file || !file.type?.startsWith('image/')) return null
    let body = file
    let contentType = file.type
    let ext = (file.name.split('.').pop() || 'jpg').toLowerCase().replace(/[^a-z0-9]/g, '')
    try {
      const c = await compressImage(file)
      if (c) { body = c.blob; contentType = c.contentType; ext = c.ext }
    } catch (e) { console.warn('Komprese selhala, nahrávám originál:', e) }
    const safeBase = (file.name.replace(/\.[^.]+$/, '') || 'img')
      .toLowerCase()
      .normalize('NFD').replace(/[̀-ͯ]/g, '')
      .replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')
      .slice(0, 40) || 'img'
    const stamp = Date.now().toString(36) + Math.random().toString(36).slice(2, 6)
    const path = `${folder}/${stamp}-${safeBase}.${ext}`
    const { error } = await supabase.storage.from(bucket).upload(path, body, {
      cacheControl: '31536000',
      upsert: false,
      contentType,
    })
    if (error) throw error
    const { data } = supabase.storage.from(bucket).getPublicUrl(path)
    return data.publicUrl
  }

  async function handleFiles(fileList) {
    if (!fileList || fileList.length === 0) return
    if (!folder) { setErr('ImageUploader: chybí prop "folder"'); return }
    setErr(null)
    const files = Array.from(fileList).filter(f => f.type?.startsWith('image/'))
    if (files.length === 0) { setErr('Vyberte prosím obrázky (JPG, PNG, WebP, GIF)'); return }

    let toUpload = files
    if (max) {
      const remaining = Math.max(0, max - urls.length)
      toUpload = single ? files.slice(0, 1) : files.slice(0, remaining)
    } else if (single) {
      toUpload = files.slice(0, 1)
    }

    setUploading(true)
    setProgress({ done: 0, total: toUpload.length })
    const uploaded = []
    try {
      for (const file of toUpload) {
        try {
          const url = await uploadFile(file)
          if (url) uploaded.push(url)
        } catch (e) {
          console.error('Upload error:', e)
          setErr(`Chyba při nahrávání: ${e.message || e}`)
        }
        setProgress(p => ({ ...p, done: p.done + 1 }))
      }
      if (uploaded.length > 0) {
        const nextUrls = single ? [uploaded[0]] : [...urls, ...uploaded]
        emit(nextUrls)
        emitAlts(nextUrls)
      }
    } finally {
      setUploading(false)
      setProgress({ done: 0, total: 0 })
      if (inputRef.current) inputRef.current.value = ''
    }
  }

  function onDrop(e) {
    e.preventDefault(); e.stopPropagation()
    setDragOver(false)
    if (!canAddMore && !single) return
    handleFiles(e.dataTransfer?.files)
  }

  function onDragOver(e) {
    e.preventDefault(); e.stopPropagation()
    if (!dragOver) setDragOver(true)
  }

  function onDragLeave(e) {
    e.preventDefault(); e.stopPropagation()
    setDragOver(false)
  }

  function handlePick() {
    if (!canAddMore && !single) return
    inputRef.current?.click()
  }

  function handleAddUrl() {
    const u = urlInput.trim()
    if (!u) return
    let nextUrls = urls
    if (single) nextUrls = [u]
    else if (!urls.includes(u)) nextUrls = [...urls, u]
    if (nextUrls !== urls) { emit(nextUrls); emitAlts(nextUrls) }
    setUrlInput('')
    setShowUrlInput(false)
  }

  function handleRemove(url) {
    const nextUrls = urls.filter(x => x !== url)
    emit(nextUrls)
    emitAlts(nextUrls)
  }

  function moveToFront(url) {
    if (urls[0] === url) return
    const nextUrls = [url, ...urls.filter(x => x !== url)]
    emit(nextUrls)
    emitAlts(nextUrls)
  }

  function handleAltChange(index, newAlt) {
    if (!altsEnabled) return
    const next = urls.map((_, i) => i === index ? newAlt : (altsArr[i] || ''))
    onAltsChange(next)
  }

  return (
    <div>
      <div
        onDrop={onDrop}
        onDragOver={onDragOver}
        onDragLeave={onDragLeave}
        onClick={handlePick}
        role="button"
        tabIndex={0}
        className="rounded-card text-center cursor-pointer transition-all"
        style={{
          padding: '18px 14px',
          background: dragOver ? '#dcfce7' : '#f1faf7',
          border: `2px dashed ${dragOver ? '#22c55e' : '#74FB71'}`,
          opacity: (!canAddMore && !single) ? 0.55 : 1,
          pointerEvents: uploading ? 'none' : 'auto',
        }}
      >
        <div style={{ fontSize: 28, lineHeight: 1 }}>📷</div>
        <div className="text-sm font-extrabold mt-1" style={{ color: '#1a2e22' }}>
          {uploading
            ? `Nahrávám… ${progress.done}/${progress.total}`
            : (!canAddMore && !single)
              ? `Maximum ${max} obrázků dosaženo`
              : 'Přetáhněte obrázky sem nebo klikněte pro výběr'}
        </div>
        <div className="text-xs mt-0.5" style={{ color: '#6b8f7b' }}>
          JPG, PNG, WebP, GIF{single ? '' : ' — můžete vybrat více najednou'}
        </div>
        <input
          ref={inputRef}
          type="file"
          accept="image/*"
          multiple={effectiveMultiple}
          onChange={e => handleFiles(e.target.files)}
          style={{ display: 'none' }}
        />
      </div>

      {allowUrl && (
        <div className="mt-2">
          {!showUrlInput ? (
            <button
              type="button"
              onClick={() => setShowUrlInput(true)}
              className="text-xs font-bold cursor-pointer bg-transparent border-none"
              style={{ color: '#2563eb', padding: 0 }}
            >
              + Přidat přes URL
            </button>
          ) : (
            <div className="flex gap-2">
              <input
                type="url"
                value={urlInput}
                autoFocus
                onChange={e => setUrlInput(e.target.value)}
                onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); handleAddUrl() } }}
                placeholder="https://…"
                className="flex-1 rounded-btn text-sm outline-none"
                style={{ padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0' }}
              />
              <button
                type="button"
                onClick={handleAddUrl}
                className="rounded-btn text-sm font-extrabold cursor-pointer"
                style={{ padding: '6px 12px', background: '#74FB71', color: '#1a2e22', border: 'none' }}
              >Přidat</button>
              <button
                type="button"
                onClick={() => { setShowUrlInput(false); setUrlInput('') }}
                className="rounded-btn text-sm font-bold cursor-pointer"
                style={{ padding: '6px 10px', background: '#f1faf7', color: '#1a2e22', border: 'none' }}
              >Zrušit</button>
            </div>
          )}
        </div>
      )}

      {helperText && (
        <div className="text-xs mt-2" style={{ color: '#6b8f7b', lineHeight: 1.5 }}>{helperText}</div>
      )}

      {err && <p className="mt-2 text-sm" style={{ color: '#dc2626' }}>{err}</p>}

      {urls.length > 0 && (
        <div className="flex flex-wrap gap-2 mt-3">
          {urls.map((url, i) => (
            <div key={url + i} style={{ width: altsEnabled ? 140 : 84 }}>
              <div className="relative group" style={{ width: altsEnabled ? 140 : 84, height: altsEnabled ? 140 : 84 }}>
                {showMainBadge && i === 0 && !single && (
                  <div className="absolute top-1 left-1 z-10" style={{
                    background: '#74FB71', color: '#1a2e22', borderRadius: 4,
                    padding: '1px 5px', fontSize: 9, fontWeight: 800, letterSpacing: 0.3,
                  }}>HLAVNÍ</div>
                )}
                <img
                  src={url}
                  alt={`Foto ${i + 1}`}
                  loading="lazy"
                  decoding="async"
                  className="w-full h-full object-cover rounded-lg"
                  style={{ border: '1px solid #d4e8e0' }}
                  onError={e => { e.target.style.opacity = 0.3 }}
                />
                <div className="absolute inset-x-0 bottom-0 flex justify-between opacity-0 group-hover:opacity-100 transition-opacity" style={{ padding: 3 }}>
                  {!single && i !== 0 && showMainBadge ? (
                    <button
                      type="button"
                      onClick={() => moveToFront(url)}
                      title="Nastavit jako hlavní"
                      className="cursor-pointer"
                      style={{
                        background: 'rgba(116,251,113,.95)', color: '#1a2e22', border: 'none',
                        borderRadius: 4, fontSize: 9, fontWeight: 800, padding: '1px 5px',
                      }}
                    >HLAVNÍ</button>
                  ) : <span />}
                  <button
                    type="button"
                    onClick={() => handleRemove(url)}
                    title="Odebrat"
                    className="cursor-pointer"
                    style={{
                      background: 'rgba(220,38,38,.85)', color: '#fff', border: 'none',
                      borderRadius: 50, width: 20, height: 20, fontSize: 11, lineHeight: 1,
                    }}
                  >✕</button>
                </div>
              </div>
              {altsEnabled && (
                <input
                  type="text"
                  value={altsArr[i] || ''}
                  onChange={e => handleAltChange(i, e.target.value)}
                  placeholder={altPlaceholder}
                  title="Krátký popisek toho, co je na fotce. Web složí finální alt z názvu položky + tohoto popisku."
                  className="w-full mt-1 rounded-btn text-xs outline-none"
                  style={{ padding: '4px 6px', background: '#f1faf7', border: '1px solid #d4e8e0', color: '#1a2e22' }}
                />
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
