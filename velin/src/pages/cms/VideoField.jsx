import { useState } from 'react'
import { supabase } from '../../lib/supabase'

// Pole typu 'video' v Textech webu (např. video „jak se obsloužit“ u pobočky).
// Hodnota = veřejná URL: buď nahraný soubor v bucketu `media` (prefix z
// field.storagePrefix), nebo odkaz na YouTube. Ukládá se tlačítkem „Uložit“
// v řádku pole (stejně jako texty) — web/appka zobrazí přehrávač, prázdné = bez videa.
const MAX_MB = 50 // limit nahrávaného souboru Supabase Storage (výchozí 50 MB)

export default function VideoField({ value, onChange, storagePrefix }) {
  const [uploading, setUploading] = useState(false)
  const [err, setErr] = useState(null)
  const url = (value || '').trim()
  const isYt = /youtu\.?be/i.test(url)

  async function upload(e) {
    const file = e.target.files?.[0]
    e.target.value = ''
    if (!file) return
    setErr(null)
    if (!/^video\//.test(file.type)) { setErr('Vyberte videosoubor (MP4 / WebM / MOV).'); return }
    if (file.size > MAX_MB * 1024 * 1024) {
      setErr(`Soubor má ${(file.size / 1048576).toFixed(0)} MB — limit je ${MAX_MB} MB. Video zmenšete (např. 720p MP4) nebo ho nahrajte na YouTube a vložte odkaz.`)
      return
    }
    setUploading(true)
    const safe = file.name.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9.]+/g, '-')
    const path = `${storagePrefix || 'videos/'}${Date.now()}-${safe}`
    const { error } = await supabase.storage.from('media').upload(path, file, { contentType: file.type, upsert: false })
    setUploading(false)
    if (error) { setErr(error.message || 'Nahrání selhalo'); return }
    onChange(supabase.storage.from('media').getPublicUrl(path).data.publicUrl)
  }

  return (
    <div className="rounded-card" style={{ border: '1px solid #d4e8e0', padding: 12, background: '#f8fcfa' }}>
      {url && !isYt && (
        <video src={url} controls preload="metadata" style={{ width: '100%', maxHeight: 260, borderRadius: 10, background: '#000', marginBottom: 8 }} />
      )}
      {url && isYt && (
        <div className="text-xs mb-2" style={{ color: '#1a2e22' }}>▶ YouTube: <a href={url} target="_blank" rel="noopener noreferrer">{url}</a></div>
      )}
      {!url && <div className="text-xs mb-2" style={{ color: '#6b8f7b' }}>Zatím bez videa — na webu ani v appce se sekce nezobrazí.</div>}
      <div className="flex gap-2 items-center flex-wrap">
        <label className="rounded-btn text-xs font-extrabold cursor-pointer" style={{ padding: '8px 14px', background: '#1a2e22', color: '#fff' }}>
          {uploading ? 'Nahrávám…' : '⬆ Nahrát video'}
          <input type="file" accept="video/mp4,video/webm,video/quicktime" onChange={upload} disabled={uploading} style={{ display: 'none' }} />
        </label>
        {url && (
          <button type="button" onClick={() => onChange('')} className="rounded-btn text-xs font-extrabold cursor-pointer"
            style={{ padding: '8px 14px', background: '#fee2e2', color: '#991b1b', border: '1px solid #fecaca' }}>
            Odebrat video
          </button>
        )}
      </div>
      <input
        type="url" value={url} onChange={e => onChange(e.target.value)}
        placeholder="…nebo vložte odkaz (https://youtu.be/… nebo URL videa)"
        className="w-full mt-2 text-sm rounded-btn" style={{ padding: '8px 10px', border: '1px solid #d4e8e0' }}
      />
      <div className="text-xs mt-1" style={{ color: '#6b8f7b' }}>
        MP4 do {MAX_MB} MB (ideálně 720p, na výšku i na šířku). Po nahrání nebo vložení odkazu klikněte na „Uložit“.
      </div>
      {err && <div className="text-xs font-bold mt-1" style={{ color: '#dc2626' }}>✗ {err}</div>}
    </div>
  )
}
