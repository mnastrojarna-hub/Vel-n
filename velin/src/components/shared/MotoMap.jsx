import { useState, useEffect } from 'react'
import { supabase } from '../../lib/supabase'
import { MAPY_CZ_API_KEY, mapyLinkUrl } from '../../lib/mapyCz'
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
        <p style={{ color: '#1a2e22', fontSize: 13 }}>Žádná motorka nesdílí polohu</p>
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
          {/* Mapy.cz dlazdice + markery */}
          <iframe
            title="Mapa motorek"
            width="100%" height="100%"
            style={{ border: 'none' }}
            srcDoc={buildMotoMapHtml(locations)}
          />
          {/* Overlay s polohy */}
          <div className="absolute bottom-0 left-0 right-0 p-3" style={{ background: 'linear-gradient(transparent, rgba(15,26,20,.85))' }}>
            <div className="flex flex-wrap gap-2">
              {locations.filter(l => l.lat && l.lng).map(l => (
                <button key={l.moto_id} onClick={() => setSelected(l)}
                  className="rounded-btn text-sm font-bold cursor-pointer"
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
                <span className="text-sm font-mono ml-2" style={{ color: '#1a2e22' }}>{l.motorcycles?.spz}</span>
              </div>
              <div className="text-sm" style={{ color: '#1a2e22' }}>
                {l.lat && l.lng ? (
                  <a href={mapyLinkUrl(l.lat, l.lng)} target="_blank" rel="noreferrer"
                    className="underline" style={{ color: '#2563eb' }}>
                    {Number(l.lat).toFixed(5)}, {Number(l.lng).toFixed(5)}
                  </a>
                ) : l.address || 'Poloha neznámá'}
              </div>
              <div className="text-sm" style={{ color: '#1a2e22' }}>
                {l.updated_at ? `${timeSince(l.updated_at)} ago` : ''}
              </div>
            </div>
          ))}
        </div>
      )}

      {selected && (
        <div className="mt-3 p-3 rounded-lg" style={{ background: '#f1faf7' }}>
          <div className="font-bold text-sm">{selected.motorcycles?.model} ({selected.motorcycles?.spz})</div>
          <div className="text-sm mt-1" style={{ color: '#1a2e22' }}>
            Souřadnice: {Number(selected.lat).toFixed(5)}, {Number(selected.lng).toFixed(5)}
          </div>
          <div className="text-sm" style={{ color: '#1a2e22' }}>
            Aktualizace: {selected.updated_at?.slice(0, 16) || '—'}
          </div>
          <a href={mapyLinkUrl(selected.lat, selected.lng)} target="_blank" rel="noreferrer"
            className="inline-block mt-2 rounded-btn text-sm font-bold"
            style={{ padding: '6px 14px', background: '#74FB71', color: '#1a2e22', textDecoration: 'none' }}>
            Otevřít v Mapy.cz
          </a>
        </div>
      )}
    </Card>
  )
}

function buildMotoMapHtml(locations) {
  const valid = locations.filter(l => l.lat && l.lng).map(l => ({
    lat: Number(l.lat), lng: Number(l.lng),
    label: [l.motorcycles?.model, l.motorcycles?.spz].filter(Boolean).join(' • '),
  }))
  if (valid.length === 0) return ''
  const center = valid[0]
  const lats = valid.map(v => v.lat), lngs = valid.map(v => v.lng)
  const minLat = Math.min(...lats), maxLat = Math.max(...lats)
  const minLng = Math.min(...lngs), maxLng = Math.max(...lngs)
  const tileUrl = `https://api.mapy.cz/v1/maptiles/basic/256/{z}/{x}/{y}?apikey=${MAPY_CZ_API_KEY}`
  return `<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>html,body{margin:0;padding:0;height:100%;width:100%}#m{height:100%;width:100%}.lg-credit{position:absolute;left:8px;bottom:4px;z-index:500}.lg-credit img{width:80px}</style></head>
<body><div id="m"></div>
<a class="lg-credit" href="https://mapy.cz/" target="_blank"><img src="https://api.mapy.cz/img/api/logo.svg" alt="Mapy.cz"/></a>
<script>
var markers = ${JSON.stringify(valid)};
var map = L.map("m", { zoomControl: true }).setView([${center.lat}, ${center.lng}], 10);
L.tileLayer(${JSON.stringify(tileUrl)}, { minZoom: 0, maxZoom: 19, attribution: '<a href="https://api.mapy.cz/copyright" target="_blank">Mapy.cz &amp; Seznam.cz a.s.</a>' }).addTo(map);
var group = L.featureGroup();
markers.forEach(function(m) { L.marker([m.lat, m.lng]).bindPopup(m.label || '').addTo(group); });
group.addTo(map);
if (markers.length > 1) { map.fitBounds([[${minLat}, ${minLng}], [${maxLat}, ${maxLng}]], { padding: [30, 30] }); }
</script></body></html>`
}

function timeSince(dateStr) {
  const diff = (Date.now() - new Date(dateStr).getTime()) / 1000
  if (diff < 60) return `${Math.round(diff)}s`
  if (diff < 3600) return `${Math.round(diff / 60)}min`
  if (diff < 86400) return `${Math.round(diff / 3600)}h`
  return `${Math.round(diff / 86400)}d`
}

function SectionTitle({ children }) {
  return <h3 className="text-sm font-extrabold uppercase tracking-widest mb-3" style={{ color: '#1a2e22' }}>{children}</h3>
}
