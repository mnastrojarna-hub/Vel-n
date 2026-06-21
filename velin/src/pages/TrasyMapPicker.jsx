import { useEffect, useMemo, useRef, useState } from 'react'
import { MAPY_CZ_API_KEY } from '../lib/mapyCz'

// Interaktivní mapa pro skládání trasy ve Velíně.
// - Klik do mapy přidá bod trasy (waypoint) nebo bod zájmu (POI) dle režimu
// - Tažením markeru se bod posune
// - Vykreslí SKUTEČNOU trasu (geometry z Mapy.com routing); dokud není, ukáže
//   rovné spojnice v pořadí start → waypointy → (u okruhu zpět)
// Leaflet se načítá v iframe (bez npm závislosti); srcDoc je STABILNÍ (počítá se
// jednou) → markery/trasa se aktualizují přes postMessage bez reloadu mapy.
//
// Props:
//   start      {lat,lng}|null    – pobočka (zelený start pin)
//   waypoints  [{lat,lng,label}] – body trasy
//   pois       [{lat,lng,name}]  – body zájmu
//   geometry   {coordinates:[[lng,lat],…]}|null – skutečná trasa (volitelné)
//   isLoop     bool              – okruh (čára se vrací na start)
//   onAddWaypoint / onAddPoi / onMoveWaypoint / onMovePoi
export default function TrasyMapPicker({
  start, waypoints = [], pois = [], geometry = null, isLoop = false,
  onAddWaypoint, onAddPoi, onMoveWaypoint, onMovePoi,
}) {
  const iframeRef = useRef(null)
  const readyRef = useRef(false)
  const lastCountRef = useRef(-1)
  const [mode, setMode] = useState('wp') // 'wp' | 'poi'

  const tileUrl = `https://api.mapy.cz/v1/maptiles/outdoor/256/{z}/{x}/{y}?apikey=${MAPY_CZ_API_KEY}`

  // Počáteční střed — JEN jednou (stabilní srcDoc → iframe se nereloaduje).
  const initial = useRef(null)
  if (!initial.current) {
    const pts = [
      ...(start && start.lat && start.lng ? [start] : []),
      ...waypoints.filter(w => w.lat && w.lng),
      ...pois.filter(p => p.lat && p.lng),
    ]
    if (pts.length) {
      const lat = pts.reduce((s, p) => s + Number(p.lat), 0) / pts.length
      const lng = pts.reduce((s, p) => s + Number(p.lng), 0) / pts.length
      initial.current = { lat, lng, z: 11 }
    } else {
      initial.current = { lat: 49.8175, lng: 15.4730, z: 7 }
    }
  }

  // Pošli aktuální stav do iframe (markery + trasa). `fit` = přizpůsobit výřez.
  function pushState(fit) {
    const win = iframeRef.current?.contentWindow
    if (!win || !readyRef.current) return
    win.postMessage({
      __mg: 'trasy-map',
      type: 'render',
      fit: !!fit,
      start: start && start.lat != null && start.lng != null
        ? { lat: Number(start.lat), lng: Number(start.lng) } : null,
      waypoints: waypoints
        .filter(w => w.lat !== '' && w.lng !== '' && w.lat != null && w.lng != null)
        .map(w => ({ lat: Number(w.lat), lng: Number(w.lng), label: w.label || '' })),
      pois: pois
        .filter(p => p.lat !== '' && p.lng !== '' && p.lat != null && p.lng != null)
        .map(p => ({ lat: Number(p.lat), lng: Number(p.lng), name: p.name || '' })),
      geometry: geometry && Array.isArray(geometry.coordinates)
        ? geometry.coordinates.map(c => [c[1], c[0]]) : null,
      isLoop: !!isLoop,
    }, '*')
  }

  // Příjem zpráv z iframe.
  useEffect(() => {
    function onMsg(e) {
      const d = e.data
      if (!d || d.__mg !== 'trasy-map') return
      if (d.type === 'ready') {
        readyRef.current = true
        lastCountRef.current = -1
        pushState(true)
      } else if (d.type === 'click') {
        if (mode === 'wp') onAddWaypoint?.(d.lat, d.lng)
        else onAddPoi?.(d.lat, d.lng)
      } else if (d.type === 'move') {
        if (d.kind === 'wp') onMoveWaypoint?.(d.index, d.lat, d.lng)
        else onMovePoi?.(d.index, d.lat, d.lng)
      }
    }
    window.addEventListener('message', onMsg)
    return () => window.removeEventListener('message', onMsg)
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mode, onAddWaypoint, onAddPoi, onMoveWaypoint, onMovePoi])

  // Re-render markerů/trasy. Výřez přizpůsobíme JEN když přibyl/ubyl bod
  // (ne při tažení ani při dopočtu geometrie) — ať mapa neposkakuje.
  useEffect(() => {
    const count = waypoints.length + pois.length
    const fit = count !== lastCountRef.current
    lastCountRef.current = count
    pushState(fit)
  })

  const srcDoc = useMemo(() => `<!DOCTYPE html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"><\/script>
<style>html,body{margin:0;padding:0;height:100%}#m{height:100%;width:100%}
.pin{display:flex;align-items:center;justify-content:center;border-radius:50%;border:2px solid #fff;
  box-shadow:0 1px 4px rgba(0,0,0,.4);font-weight:800;color:#fff;font-size:12px;font-family:sans-serif}
.wp{background:#8b5cf6;width:26px;height:26px}
.poi{background:#1a8a18;width:24px;height:24px}
.start{background:#13C14E;width:30px;height:30px;color:#0f1a14;font-size:16px}
.lg-credit{position:absolute;left:8px;bottom:4px;z-index:500}.lg-credit img{width:80px}</style></head>
<body><div id="m"></div>
<a class="lg-credit" href="https://mapy.cz/" target="_blank"><img src="https://api.mapy.cz/img/api/logo.svg" alt="Mapy.cz"/></a>
<script>
var map=L.map("m",{zoomControl:true}).setView([${initial.current.lat},${initial.current.lng}],${initial.current.z});
L.tileLayer(${JSON.stringify(tileUrl)},{minZoom:0,maxZoom:19,attribution:'<a href="https://api.mapy.cz/copyright" target="_blank">Mapy.cz &amp; Seznam.cz a.s.</a>'}).addTo(map);
var layer=L.layerGroup().addTo(map);
function icon(cls,txt){return L.divIcon({html:'<div class="pin '+cls+'">'+txt+'</div>',className:'',iconSize:[26,26],iconAnchor:[13,13]});}
function send(o){o.__mg='trasy-map';parent.postMessage(o,'*');}
map.on('click',function(e){send({type:'click',lat:e.latlng.lat,lng:e.latlng.lng});});
window.addEventListener('message',function(e){
  var d=e.data; if(!d||d.__mg!=='trasy-map'||d.type!=='render') return;
  layer.clearLayers();
  var pts=[], line=[];
  if(d.start){line.push([d.start.lat,d.start.lng]);pts.push([d.start.lat,d.start.lng]);
    L.marker([d.start.lat,d.start.lng],{icon:icon('start','★'),zIndexOffset:1000}).addTo(layer).bindTooltip('Pobočka (start)');}
  (d.waypoints||[]).forEach(function(w,i){
    line.push([w.lat,w.lng]);pts.push([w.lat,w.lng]);
    var m=L.marker([w.lat,w.lng],{icon:icon('wp',String(i+1)),draggable:true}).addTo(layer);
    m.bindTooltip(w.label||('Bod '+(i+1)));
    m.on('dragend',function(ev){var p=ev.target.getLatLng();send({type:'move',kind:'wp',index:i,lat:p.lat,lng:p.lng});});
  });
  if(d.isLoop&&d.start) line.push([d.start.lat,d.start.lng]);
  if(d.geometry&&d.geometry.length>1){
    L.polyline(d.geometry,{color:'#1a8a18',weight:5,opacity:.9}).addTo(layer);
    for(var g=0;g<d.geometry.length;g++) pts.push(d.geometry[g]);
  } else if(line.length>1){
    L.polyline(line,{color:'#1a8a18',weight:4,opacity:.85,dashArray:'6,8'}).addTo(layer);
  }
  (d.pois||[]).forEach(function(p,i){
    pts.push([p.lat,p.lng]);
    var m=L.marker([p.lat,p.lng],{icon:icon('poi','●'),draggable:true}).addTo(layer);
    m.bindTooltip(p.name||('Bod zájmu '+(i+1)));
    m.on('dragend',function(ev){var q=ev.target.getLatLng();send({type:'move',kind:'poi',index:i,lat:q.lat,lng:q.lng});});
  });
  if(d.fit&&pts.length>1){try{map.fitBounds(pts,{padding:[30,30],maxZoom:15});}catch(err){}}
  else if(d.fit&&pts.length===1){map.setView(pts[0],13);}
}, false);
send({type:'ready'});
<\/script></body></html>`, [])

  const tabBtn = (key, label) => (
    <button type="button" onClick={() => setMode(key)}
      className="rounded-btn text-sm font-extrabold cursor-pointer border-none"
      style={{
        padding: '6px 14px',
        background: mode === key ? (key === 'wp' ? '#8b5cf6' : '#1a8a18') : '#f1faf7',
        color: mode === key ? '#fff' : '#1a2e22',
      }}>
      {label}
    </button>
  )

  return (
    <div className="rounded-card overflow-hidden" style={{ border: '1px solid #d4e8e0' }}>
      <div className="flex items-center gap-2 flex-wrap" style={{ padding: '8px 10px', background: '#f1faf7', borderBottom: '1px solid #d4e8e0' }}>
        <span className="text-xs font-bold" style={{ color: '#1a2e22' }}>Klikni do mapy:</span>
        {tabBtn('wp', '➕ Bod trasy')}
        {tabBtn('poi', '📍 Bod zájmu')}
        <span className="text-xs ml-auto" style={{ color: '#6b8f7b' }}>Markery lze posouvat tažením</span>
      </div>
      <iframe ref={iframeRef} title="Mapa trasy" style={{ width: '100%', height: 340, border: 'none', display: 'block' }} srcDoc={srcDoc} />
    </div>
  )
}
