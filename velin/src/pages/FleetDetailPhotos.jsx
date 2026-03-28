import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import Card from '../components/ui/Card'

function PhotoGallery({ motoId }) {
  const [photos, setPhotos] = useState([])
  const [dbImages, setDbImages] = useState([])
  const [uploading, setUploading] = useState(false)
  const [urlInput, setUrlInput] = useState('')
  const [showUrlInput, setShowUrlInput] = useState(false)

  useEffect(() => { loadPhotos(); loadDbImages() }, [motoId])

  async function loadDbImages() {
    try {
      const { data } = await supabase.from('motorcycles').select('image_url, images').eq('id', motoId).single()
      if (data) setDbImages(data.images || [])
    } catch {}
  }

  async function syncToDb(urls) {
    const cleaned = urls.filter(u => u && typeof u === 'string')
    await supabase.from('motorcycles').update({
      image_url: cleaned[0] || null,
      images: cleaned
    }).eq('id', motoId)
    setDbImages(cleaned)
  }

  async function loadPhotos() {
    try {
      const { data } = await supabase.storage.from('media').list(`motos/${motoId}`)
      if (data) setPhotos(data.filter(f => f.name !== '.emptyFolderPlaceholder' && f.name !== 'manual'))
    } catch { setPhotos([]) }
  }

  async function handleUpload(e) {
    const file = e.target.files?.[0]; if (!file) return; setUploading(true)
    const { error } = await supabase.storage.from('media').upload(`motos/${motoId}/${file.name}`, file, { upsert: true })
    if (error) { console.error('Upload error:', error); setUploading(false); return }
    await loadPhotos()
    const url = getUrl(file.name)
    // Re-read current DB state to avoid stale data
    const { data: fresh } = await supabase.from('motorcycles').select('images').eq('id', motoId).single()
    const current = (fresh?.images || []).filter(u => u && typeof u === 'string')
    if (!current.includes(url)) {
      await syncToDb([...current, url])
    }
    setUploading(false)
  }

  async function handleAddUrl() {
    const url = urlInput.trim(); if (!url) return
    const updated = [...dbImages, url]
    await syncToDb(updated)
    setUrlInput(''); setShowUrlInput(false)
  }

  async function handleRemoveImage(url, storageName) {
    if (storageName) {
      await supabase.storage.from('media').remove([`motos/${motoId}/${storageName}`])
      await loadPhotos()
    }
    const updated = dbImages.filter(u => u !== url)
    await syncToDb(updated)
  }

  const getUrl = (name) => supabase.storage.from('media').getPublicUrl(`motos/${motoId}/${name}`).data.publicUrl

  const allImages = [...new Set([...dbImages, ...photos.map(p => getUrl(p.name))])]

  return (
    <div className="mt-5">
      <div className="flex items-center gap-3 mb-2">
        <span className="text-sm font-extrabold uppercase tracking-wide" style={{ color: '#1a2e22' }}>Fotogalerie ({allImages.length})</span>
        <label className="rounded-btn text-sm font-extrabold cursor-pointer" style={{ padding: '4px 14px', background: '#f1faf7', color: '#1a2e22' }}>
          {uploading ? 'Nahrávám…' : '+ Foto'}<input type="file" accept="image/*" onChange={handleUpload} className="hidden" />
        </label>
        <button onClick={() => setShowUrlInput(!showUrlInput)} className="rounded-btn text-sm font-extrabold cursor-pointer"
          style={{ padding: '4px 14px', background: '#dbeafe', color: '#2563eb', border: 'none' }}>
          + URL
        </button>
      </div>
      {showUrlInput && (
        <div className="flex gap-2 mb-2">
          <input type="url" value={urlInput} onChange={e => setUrlInput(e.target.value)}
            placeholder="https://..."
            className="flex-1 rounded-btn text-sm outline-none"
            style={{ padding: '6px 10px', background: '#f1faf7', border: '1px solid #d4e8e0' }}
            onKeyDown={e => e.key === 'Enter' && handleAddUrl()} />
          <button onClick={handleAddUrl} className="rounded-btn text-sm font-extrabold cursor-pointer"
            style={{ padding: '6px 12px', background: '#74FB71', color: '#1a2e22', border: 'none' }}>
            Přidat
          </button>
        </div>
      )}
      <div className="flex flex-wrap gap-2">
        {allImages.map((url, i) => {
          const storagePhoto = photos.find(p => getUrl(p.name) === url)
          return (
            <div key={url} className="relative group" style={{ width: 80, height: 80 }}>
              {i === 0 && <div className="absolute top-1 left-1 z-10" style={{ background: '#74FB71', color: '#1a2e22', borderRadius: 4, padding: '1px 4px', fontSize: 8, fontWeight: 800 }}>HLAVNÍ</div>}
              <img src={url} alt={`Foto ${i + 1}`} className="w-full h-full object-cover rounded-lg" onError={e => { e.target.style.display = 'none' }} />
              <button onClick={() => handleRemoveImage(url, storagePhoto?.name)}
                className="absolute top-1 right-1 opacity-0 group-hover:opacity-100 cursor-pointer"
                style={{ background: 'rgba(220,38,38,.8)', color: '#fff', border: 'none', borderRadius: 50, width: 18, height: 18, fontSize: 9 }}>✕</button>
            </div>
          )
        })}
      </div>
    </div>
  )
}

function PerformanceTab({ motoId }) {
  const [perf, setPerf] = useState(null)
  const [loading, setLoading] = useState(true)
  useEffect(() => {
    supabase.from('moto_performance').select('*').eq('moto_id', motoId).single()
      .then(({ data }) => { setPerf(data); setLoading(false) }).catch(() => { setPerf(null); setLoading(false) })
  }, [motoId])
  if (loading) return <div className="py-8 text-center"><div className="animate-spin inline-block rounded-full h-6 w-6 border-t-2 border-brand-gd" /></div>
  if (!perf) return <Card><p style={{ color: '#1a2e22', fontSize: 13 }}>Žádné výkonové statistiky</p></Card>
  return (
    <Card>
      <div className="grid grid-cols-3 gap-4">
        {Object.entries(perf).filter(([k]) => !['id', 'moto_id', 'created_at', 'updated_at'].includes(k)).map(([k, v]) => (
          <div key={k} className="p-3 rounded-lg" style={{ background: '#f1faf7' }}>
            <div className="text-sm font-extrabold uppercase tracking-wide mb-1" style={{ color: '#1a2e22' }}>{k.replace(/_/g, ' ')}</div>
            <div className="text-lg font-bold" style={{ color: '#0f1a14' }}>{typeof v === 'number' ? v.toLocaleString('cs-CZ') : String(v ?? '—')}</div>
          </div>
        ))}
      </div>
    </Card>
  )
}

export { PhotoGallery, PerformanceTab }
