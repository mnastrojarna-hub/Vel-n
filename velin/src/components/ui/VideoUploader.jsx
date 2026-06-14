import { useState, useRef } from 'react'
import { supabase } from '../../lib/supabase'

/**
 * Nahrávač MP4 videí pro Velín (flotila).
 * Vychází z ImageUploader, ale BEZ komprese (video se uploaduje 1:1) a s <video>
 * náhledy. Videa se ukládají do stejného public bucketu `media` jako fotky.
 *
 * - Drag & drop / klik pro výběr (accept video/mp4)
 * - Náhledy s tlačítkem ✕ pro odebrání + „1." pro nastavení pořadí
 * - Pořadí videí = pořadí přehrávání na webu (hero, detail, rezervace) i v appce
 *
 * Props:
 *   value      string[]  – aktuální URL videí
 *   onChange   (urls)    – callback při změně
 *   folder     string    – cesta v bucketu (např. 'motos/<id>/videos')
 *   bucket     string    – výchozí 'media'
 *   max        number    – max počet videí (volitelné)
 *   maxSizeMb  number    – max velikost souboru v MB (výchozí 100)
 *   helperText string    – nápověda pod komponentou
 */
export default function VideoUploader({
  value = [],
  onChange,
  folder,
  bucket = 'media',
  max,
  maxSizeMb = 100,
  helperText,
}) {
  const urls = Array.isArray(value) ? value : []
  const [uploading, setUploading] = useState(false)
  const [progress, setProgress] = useState({ done: 0, total: 0 })
  const [dragOver, setDragOver] = useState(false)
  const [err, setErr] = useState(null)
  const inputRef = useRef(null)

  const canAddMore = !max || urls.length < max

  function emit(next) { onChange?.(next) }

  async function uploadFile(file) {
    if (!file || !file.type?.startsWith('video/')) return null
    const ext = (file.name.split('.').pop() || 'mp4').toLowerCase().replace(/[^a-z0-9]/g, '') || 'mp4'
    const safeBase = (file.name.replace(/\.[^.]+$/, '') || 'video')
      .toLowerCase()
      .normalize('NFD').replace(/[̀-ͯ]/g, '')
      .replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')
      .slice(0, 40) || 'video'
    const stamp = Date.now().toString(36) + Math.random().toString(36).slice(2, 6)
    const path = `${folder}/${stamp}-${safeBase}.${ext}`
    const { error } = await supabase.storage.from(bucket).upload(path, file, {
      cacheControl: '31536000',
      upsert: false,
      contentType: file.type || 'video/mp4',
    })
    if (error) throw error
    const { data } = supabase.storage.from(bucket).getPublicUrl(path)
    return data.publicUrl
  }

  async function handleFiles(fileList) {
    if (!fileList || fileList.length === 0) return
    if (!folder) { setErr('VideoUploader: chybí prop "folder"'); return }
    setErr(null)
    let files = Array.from(fileList).filter(f => f.type?.startsWith('video/'))
    if (files.length === 0) { setErr('Vyberte prosím video (MP4)'); return }
    const tooBig = files.find(f => f.size > maxSizeMb * 1024 * 1024)
    if (tooBig) { setErr(`Video „${tooBig.name}" je příliš velké (max ${maxSizeMb} MB).`); return }

    if (max) {
      const remaining = Math.max(0, max - urls.length)
      files = files.slice(0, remaining)
    }

    setUploading(true)
    setProgress({ done: 0, total: files.length })
    const uploaded = []
    try {
      for (const file of files) {
        try {
          const url = await uploadFile(file)
          if (url) uploaded.push(url)
        } catch (e) {
          console.error('Video upload error:', e)
          setErr(`Chyba při nahrávání: ${e.message || e}`)
        }
        setProgress(p => ({ ...p, done: p.done + 1 }))
      }
      if (uploaded.length > 0) emit([...urls, ...uploaded])
    } finally {
      setUploading(false)
      setProgress({ done: 0, total: 0 })
      if (inputRef.current) inputRef.current.value = ''
    }
  }

  function onDrop(e) {
    e.preventDefault(); e.stopPropagation()
    setDragOver(false)
    if (!canAddMore) return
    handleFiles(e.dataTransfer?.files)
  }
  function onDragOver(e) { e.preventDefault(); e.stopPropagation(); if (!dragOver) setDragOver(true) }
  function onDragLeave(e) { e.preventDefault(); e.stopPropagation(); setDragOver(false) }
  function handlePick() { if (canAddMore) inputRef.current?.click() }
  function handleRemove(url) { emit(urls.filter(x => x !== url)) }
  function moveToFront(url) {
    if (urls[0] === url) return
    emit([url, ...urls.filter(x => x !== url)])
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
          opacity: canAddMore ? 1 : 0.55,
          pointerEvents: uploading ? 'none' : 'auto',
        }}
      >
        <div style={{ fontSize: 28, lineHeight: 1 }}>🎬</div>
        <div className="text-sm font-extrabold mt-1" style={{ color: '#1a2e22' }}>
          {uploading
            ? `Nahrávám… ${progress.done}/${progress.total}`
            : !canAddMore
              ? `Maximum ${max} videí dosaženo`
              : 'Přetáhněte MP4 video sem nebo klikněte pro výběr'}
        </div>
        <div className="text-xs mt-0.5" style={{ color: '#6b8f7b' }}>
          MP4 — max {maxSizeMb} MB na soubor — můžete vybrat více najednou
        </div>
        <input
          ref={inputRef}
          type="file"
          accept="video/mp4,video/*"
          multiple
          onChange={e => handleFiles(e.target.files)}
          style={{ display: 'none' }}
        />
      </div>

      {helperText && (
        <div className="text-xs mt-2" style={{ color: '#6b8f7b', lineHeight: 1.5 }}>{helperText}</div>
      )}

      {err && <p className="mt-2 text-sm" style={{ color: '#dc2626' }}>{err}</p>}

      {urls.length > 0 && (
        <div className="flex flex-wrap gap-2 mt-3">
          {urls.map((url, i) => (
            <div key={url + i} style={{ width: 150 }}>
              <div className="relative group" style={{ width: 150, height: 96 }}>
                {i === 0 && (
                  <div className="absolute top-1 left-1 z-10" style={{
                    background: '#74FB71', color: '#1a2e22', borderRadius: 4,
                    padding: '1px 5px', fontSize: 9, fontWeight: 800, letterSpacing: 0.3,
                  }}>1. PŘEHRÁT</div>
                )}
                <video
                  src={url}
                  muted
                  playsInline
                  preload="metadata"
                  controls
                  className="w-full h-full object-cover rounded-lg"
                  style={{ border: '1px solid #d4e8e0', background: '#000' }}
                />
                <div className="absolute inset-x-0 bottom-0 flex justify-between opacity-0 group-hover:opacity-100 transition-opacity" style={{ padding: 3 }}>
                  {i !== 0 ? (
                    <button
                      type="button"
                      onClick={() => moveToFront(url)}
                      title="Přehrávat jako první"
                      className="cursor-pointer"
                      style={{
                        background: 'rgba(116,251,113,.95)', color: '#1a2e22', border: 'none',
                        borderRadius: 4, fontSize: 9, fontWeight: 800, padding: '1px 5px',
                      }}
                    >1.</button>
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
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
