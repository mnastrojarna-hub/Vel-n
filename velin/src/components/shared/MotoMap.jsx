import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import Card from '../ui/Card'

/* Mapa motorek — zobrazuje sdílené polohy z tabulky moto_locations */
export default function MotoMap({ singleMotoId = null }) {
  const [locations, setLocations] = useState([])
  const [loading, setLoading] = useState(true)
  const [selected, setSelected] = useState(null)

  useEffect(() => { loadLocations() }, [singleMotoId])

  async function loadLocations() {
    setLoading(true)
    let query = supabase
      .from('moto_locations')
      .select('*, motorcycles(id, model, spz, status)')
    if (singleMotoId) query = query.eq('moto_id', singleMotoId)
    const { data } = await query
    setLocations(data || [])
    setLoading(false)
  }

  if (loading) return <div className="py-6 text-center"><div className="animate-spin inline-block rounded-full h-5 w-5 border-t-2 border-brand-gd" /></div>

  if (locations.length === 0) {
    return (
      <Card>
        <SectionTitle>Poloha motorek</SectionTitle>
        <p style={{ color: '#8aab99', fontSize: 13 }}>Žádná motorka nesdílí polohu</p>
      </Card>
    )
  }

  // Fallback — pokud tabulka moto_locations neexistuje, zkus motorcycles.last_location
  const hasCoords = locations.some(l => l.lat && l.lng)

  return (
    <Card>
      <SectionTitle>{singleMotoId ? 'Poslední poloha' : 'Poloha motorek'}</SectionTitle>

      {hasCoords ? (
        <div className="relative rounded-lg overflow-hidden" style={{ height: 320, background: '#e8f5e9' }}>
          {/* OpenStreetMap embed */}
          <iframe
            title="Mapa motorek"
            width="100%" height="100%"
            style={{ border: 'none' }}
            src={getMapUrl(locations)}
          />
          {/* Overlay s polohy */}
          <div className="absolute bottom-0 left-0 right-0 p-3" style={{ background: 'linear-gradient(transparent, rgba(15,26,20,.85))' }}>
            <div className="flex flex-wrap gap-2">
              {locations.filter(l => l.lat && l.lng).map(l => (
                <button key={l.moto_id} onClick={() => setSelected(l)}
                  className="rounded-btn text-[10px] font-bold cursor-pointer"
                  style={{ padding: '4px 10px', background: selected?.moto_id === l.moto_id ? '#74FB71' : 'rgba(255,255,255,.9)', color: '#0f1a14', border: 'none' }}>
                  {l.motorcycles?.model || '?'} · {l.motorcycles?.spz || ''}
                </button>
              ))}
            </div>
          </div>
        </div>
      ) : (
        /* Fallback — tabulkové zobrazení poloh */
        <div className="space-y-2">
          {locations.map(l => (
            <div key={l.moto_id || l.id} className="flex items-center gap-3 p-3 rounded-lg" style={{ background: '#f1faf7' }}>
              <div className="flex-1">
                <span className="font-bold text-sm">{l.motorcycles?.model || '—'}</span>
                <span className="text-xs font-mono ml-2" style={{ color: '#8aab99' }}>{l.motorcycles?.spz}</span>
              </div>
              <div className="text-xs" style={{ color: '#4a6357' }}>
                {l.lat && l.lng ? (
                  <a href={`https://maps.google.com/?q=${l.lat},${l.lng}`} target="_blank" rel="noreferrer"
                    className="underline" style={{ color: '#2563eb' }}>
                    {Number(l.lat).toFixed(5)}, {Number(l.lng).toFixed(5)}
                  </a>
                ) : l.address || 'Poloha neznámá'}
              </div>
              <div className="text-[10px]" style={{ color: '#8aab99' }}>
                {l.updated_at ? `${timeSince(l.updated_at)} ago` : ''}
              </div>
            </div>
          ))}
        </div>
      )}

      {selected && (
        <div className="mt-3 p-3 rounded-lg" style={{ background: '#f1faf7' }}>
          <div className="font-bold text-sm">{selected.motorcycles?.model} ({selected.motorcycles?.spz})</div>
          <div className="text-xs mt-1" style={{ color: '#4a6357' }}>
            Souřadnice: {Number(selected.lat).toFixed(5)}, {Number(selected.lng).toFixed(5)}
          </div>
          <div className="text-xs" style={{ color: '#8aab99' }}>
            Aktualizace: {selected.updated_at?.slice(0, 16) || '—'}
          </div>
          <a href={`https://maps.google.com/?q=${selected.lat},${selected.lng}`} target="_blank" rel="noreferrer"
            className="inline-block mt-2 rounded-btn text-xs font-bold"
            style={{ padding: '6px 14px', background: '#74FB71', color: '#1a2e22', textDecoration: 'none' }}>
            Otevřít v Google Maps
          </a>
        </div>
      )}
    </Card>
  )
}

function getMapUrl(locations) {
  const valid = locations.filter(l => l.lat && l.lng)
  if (valid.length === 0) return ''
  const center = valid[0]
  // OpenStreetMap embed s markerem
  return `https://www.openstreetmap.org/export/embed.html?bbox=${Number(center.lng) - 0.05},${Number(center.lat) - 0.03},${Number(center.lng) + 0.05},${Number(center.lat) + 0.03}&layer=mapnik&marker=${center.lat},${center.lng}`
}

function timeSince(dateStr) {
  const diff = (Date.now() - new Date(dateStr).getTime()) / 1000
  if (diff < 60) return `${Math.round(diff)}s`
  if (diff < 3600) return `${Math.round(diff / 60)}min`
  if (diff < 86400) return `${Math.round(diff / 3600)}h`
  return `${Math.round(diff / 86400)}d`
}

function SectionTitle({ children }) {
  return <h3 className="text-[10px] font-extrabold uppercase tracking-widest mb-3" style={{ color: '#8aab99' }}>{children}</h3>
}
