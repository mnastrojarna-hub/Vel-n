export default function BookingMapPicker({ showMapPicker, setShowMapPicker, setPickupAddress, setReturnAddress }) {
  if (!showMapPicker) return null

  return (
    <div style={{ position: 'fixed', inset: 0, zIndex: 99999, background: '#fff', display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '12px 20px', background: '#fff', borderBottom: '1px solid #e5e7eb', zIndex: 1 }}>
        <button onClick={() => setShowMapPicker(null)} style={{ background: 'none', border: 'none', fontSize: 22, cursor: 'pointer' }}>{'\u2715'}</button>
        <span style={{ fontSize: 15, fontWeight: 700 }}>Vyberte misto na mape</span>
        <button onClick={() => {
          const iframe = document.getElementById('velin-map-iframe')
          if (iframe && iframe.contentWindow && iframe.contentWindow._getCenter) {
            const c = iframe.contentWindow._getCenter()
            fetch(`https://nominatim.openstreetmap.org/reverse?lat=${c.lat}&lon=${c.lng}&format=json&addressdetails=1&accept-language=cs`)
              .then(r => r.json())
              .then(data => {
                if (data && data.address) {
                  const addr = data.address
                  const street = (addr.road || '') + (addr.house_number ? ' ' + addr.house_number : '')
                  const city = addr.city || addr.town || addr.village || addr.municipality || ''
                  const full = [street, city].filter(Boolean).join(', ')
                  if (showMapPicker === 'pickup') setPickupAddress(full)
                  else setReturnAddress(full)
                }
                setShowMapPicker(null)
              }).catch(() => setShowMapPicker(null))
          } else { setShowMapPicker(null) }
        }} style={{ background: '#1a8a18', color: '#fff', border: 'none', borderRadius: 8, padding: '8px 18px', fontSize: 14, fontWeight: 700, cursor: 'pointer' }}>Potvrdit</button>
      </div>
      <div style={{ flex: 1, position: 'relative' }}>
        <iframe id="velin-map-iframe" style={{ width: '100%', height: '100%', border: 'none' }}
          srcDoc={`<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"><\/script>
<style>html,body{margin:0;padding:0;height:100%;width:100%}#m{height:100%;width:100%}</style></head>
<body><div id="m"></div><script>
var map=L.map("m",{zoomControl:true}).setView([49.4147,15.2953],10);
L.tileLayer("https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png",{maxZoom:19,subdomains:"abcd"}).addTo(map);
window._getCenter=function(){var c=map.getCenter();return{lat:c.lat,lng:c.lng};};
<\/script></body></html>`} />
        <div style={{ position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%,-50%)', zIndex: 10, pointerEvents: 'none', fontSize: 36, textShadow: '0 2px 6px rgba(0,0,0,.3)' }}>{'\ud83d\udccd'}</div>
      </div>
    </div>
  )
}
