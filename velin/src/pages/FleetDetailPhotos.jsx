import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import Card from '../components/ui/Card'
import ImageUploader from '../components/ui/ImageUploader'

function PhotoGallery({ motoId }) {
  const [images, setImages] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => { load() }, [motoId])

  async function load() {
    setLoading(true)
    try {
      const { data } = await supabase.from('motorcycles').select('images').eq('id', motoId).single()
      const list = Array.isArray(data?.images) ? data.images.filter(Boolean) : []
      setImages(list)
    } catch { setImages([]) }
    setLoading(false)
  }

  async function syncToDb(urls) {
    const cleaned = (urls || []).filter(u => u && typeof u === 'string')
    setImages(cleaned)
    await supabase.from('motorcycles').update({
      image_url: cleaned[0] || null,
      images: cleaned,
    }).eq('id', motoId)
  }

  if (loading) return null

  return (
    <div className="mt-5">
      <div className="text-sm font-extrabold uppercase tracking-wide mb-2" style={{ color: '#1a2e22' }}>
        Fotogalerie ({images.length})
      </div>
      <ImageUploader
        value={images}
        onChange={syncToDb}
        folder={`motos/${motoId}`}
        helperText="Přetáhněte fotky z počítače nebo klikněte pro výběr. První fotka je hlavní — zobrazí se v aplikaci, kalendáři i seznamu motorek."
      />
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
