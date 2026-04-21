import { rgeocode, MAPY_CZ_API_KEY } from '../../lib/mapyCz'

// Map picker pro vyzvednuti / vraceni v ramci rezervace.
// Pouziva Mapy.cz tiles + Mapy.cz rgeocode.
export default function BookingMapPicker({ showMapPicker, setShowMapPicker, setPickupAddress, setReturnAddress, onSelect }) {
  if (!showMapPicker) return null

  async function confirm() {
    const iframe = document.getElementById('velin-map-iframe')
    if (!(iframe && iframe.contentWindow && iframe.contentWindow._getCenter)) {
      setShowMapPicker(null); return
    }
    const c = iframe.contentWindow._getCenter()
    const result = await rgeocode(c.lat, c.lng)
    if (result && result.full) {
      if (showMapPicker === 'pickup') setPickupAddress(result.full)
      else setReturnAddress(result.full)
      onSelect?.({ kind: showMapPicker, lat: c.lat, lng: c.lng, address: result.full, rg: result })
    } else {
      const fallback = `${Number(c.lat).toFixed(6)}, ${Number(c.lng).toFixed(6)}`
      if (showMapPicker === 'pickup') setPickupAddress(fallback)
      else setReturnAddress(fallback)
      onSelect?.({ kind: showMapPicker, lat: c.lat, lng: c.lng, address: fallback })
    }
    setShowMapPicker(null)
  }

  const tileUrl = `https://api.mapy.cz/v1/maptiles/basic/256/{z}/{x}/{y}?apikey=${MAPY_CZ_API_KEY}`

  return (
    <div style={{ position: 'fixed', inset: 0, zIndex: 99999, background: '#fff', display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '12px 20px', background: '#fff', borderBottom: '1px solid #e5e7eb', zIndex: 1 }}>
        <button onClick={() => setShowMapPicker(null)} style={{ background: 'none', border: 'none', fontSize: 22, cursor: 'pointer' }}>{'✕'}</button>
        <span style={{ fontSize: 15, fontWeight: 700 }}>Vyberte misto na mape</span>
        <button onClick={confirm}
          style={{ background: '#1a8a18', color: '#fff', border: 'none', borderRadius: 8, padding: '8px 18px', fontSize: 14, fontWeight: 700, cursor: 'pointer' }}>
          Potvrdit
        </button>
      </div>
      <div style={{ flex: 1, position: 'relative' }}>
        <iframe id="velin-map-iframe" style={{ width: '100%', height: '100%', border: 'none' }}
          srcDoc={`<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"><\/script>
<style>html,body{margin:0;padding:0;height:100%;width:100%}#m{height:100%;width:100%}.lg-credit{position:absolute;left:8px;bottom:4px;z-index:500}.lg-credit img{width:90px;vertical-align:middle}</style></head>
<body><div id="m"></div>
<a class="lg-credit" href="https://mapy.cz/" target="_blank"><img src="https://api.mapy.cz/img/api/logo.svg" alt="Mapy.cz"/></a>
<script>
var map=L.map("m",{zoomControl:true}).setView([49.8175,15.4730],7);
L.tileLayer(${JSON.stringify(tileUrl)},{minZoom:0,maxZoom:19,attribution:'<a href="https://api.mapy.cz/copyright" target="_blank">Mapy.cz &amp; Seznam.cz a.s.</a>'}).addTo(map);
window._getCenter=function(){var c=map.getCenter();return{lat:c.lat,lng:c.lng};};
<\/script></body></html>`} />
        <div style={{ position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%,-50%)', zIndex: 10, pointerEvents: 'none', fontSize: 36, textShadow: '0 2px 6px rgba(0,0,0,.3)' }}>{'📍'}</div>
      </div>
    </div>
  )
}
